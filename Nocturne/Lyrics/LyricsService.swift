import Foundation

/// Сервис текстов: LRCLIB (открытый бесплатный API), кэш, перевод (LibreTranslate),
/// поиск трека по строке текста. Всё бесплатно, без квот.
final class LyricsService {
    private let store: LibraryStore
    private let settings: SettingsStore
    private let search: SearchService
    private let client = HTTPClient.shared

    init(store: LibraryStore, settings: SettingsStore, search: SearchService) {
        self.store = store
        self.settings = settings
        self.search = search
    }

    // MARK: - LRCLIB DTO

    struct LRCLIBTrack: Decodable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    // MARK: - Fetch

    func lyrics(for track: Track) async throws -> LyricsPayload {
        let key = track.id
        if let cached = store.cachedLyrics(trackKey: key) {
            return cached
        }

        let payload = try await fetchFromLRCLIB(track: track)
        store.saveLyrics(trackKey: key,
                         synced: payload.synced.map(syncedToText),
                         plain: payload.plain,
                         source: payload.source)
        return payload
    }

    private func fetchFromLRCLIB(track: Track) async throws -> LyricsPayload {
        let encodedArtist = track.artist.urlEncoded
        let encodedTitle = track.title.urlEncoded

        // Точный запрос
        if let url = URL(string: "https://lrclib.net/api/get?artist_name=\(encodedArtist)&track_name=\(encodedTitle)&duration=\(Int(track.duration))") {
            if let result = try? await client.getJSON(url, as: LRCLIBTrack.self, headers: Self.headers) {
                if let payload = mapLRCLIB(result, trackKey: track.id) {
                    return payload
                }
            }
        }

        // Поиск по названию
        if let url = URL(string: "https://lrclib.net/api/search?artist_name=\(encodedArtist)&track_name=\(encodedTitle)") {
            let results = (try? await client.getJSON(url, as: [LRCLIBTrack].self, headers: Self.headers)) ?? []
            let best = bestMatch(in: results, duration: track.duration)
            if let payload = mapLRCLIB(best, trackKey: track.id) {
                return payload
            }
        }

        throw ProviderError.unavailable("Текст для этого трека не найден в LRCLIB.")
    }

    static let headers = ["User-Agent": "Nocturne/0.1 (https://github.com/nocturne-music)"]

    private func bestMatch(in results: [LRCLIBTrack], duration: TimeInterval) -> LRCLIBTrack? {
        guard !results.isEmpty else { return nil }
        let withSynced = results.filter { ($0.syncedLyrics ?? "").count > 10 }
        let pool = withSynced.isEmpty ? results : withSynced
        return pool.min { a, b in
            let da = abs((a.duration ?? 0) - duration)
            let db = abs((b.duration ?? 0) - duration)
            return da < db
        }
    }

    private func mapLRCLIB(_ result: LRCLIBTrack?, trackKey: String) -> LyricsPayload? {
        guard let result else { return nil }
        let synced = result.syncedLyrics.flatMap(LRCParser.parse)
        let plain = result.plainLyrics
        guard synced != nil || (plain != nil && !(plain ?? "").isEmpty) else { return nil }
        return LyricsPayload(synced: synced, plain: plain, source: "LRCLIB", trackKey: trackKey)
    }

    private func syncedToText(_ lines: [LyricLine]) -> String {
        lines.map { line -> String in
            let total = Int(line.time)
            let minutes = total / 60
            let seconds = total % 60
            let fraction = Int((line.time - Double(total)) * 100)
            return String(format: "[%02d:%02d.%02d]%@", minutes, seconds, fraction, line.text)
        }.joined(separator: "\n")
    }

    // MARK: - Перевод (LibreTranslate — открытый движок, ключ опционален)

    func translatedLyrics(for track: Track, plainText: String) async throws -> String {
        if let cached = store.cachedTranslation(trackKey: track.id) {
            return cached
        }
        let target = settings.translationTarget
        let service = LibreTranslateService(url: settings.libreTranslateURL,
                                            apiKey: settings.secret("libretranslate_key"))
        let translated = try await service.translate(plainText, target: target)
        store.saveTranslation(trackKey: track.id, text: translated)
        return translated
    }

    // MARK: - Поиск по строке текста

    struct LyricsSearchHit: Identifiable {
        let id: String
        let artist: String
        let title: String
        let track: Track?
    }

    /// Поиск трека по строчке текста (аналог Plus-функции Mimose — бесплатно).
    func searchByLyrics(_ line: String, resolveTracks: Bool = true) async -> [LyricsSearchHit] {
        guard !line.trimmed.isEmpty else { return [] }
        guard let url = URL(string: "https://lrclib.net/api/search?q=\(line.urlEncoded)") else { return [] }
        let results = (try? await client.getJSON(url, as: [LRCLIBTrack].self, headers: Self.headers)) ?? []

        var hits: [LyricsSearchHit] = []
        var seen = Set<String>()
        for result in results.prefix(15) {
            guard let artist = result.artistName, let title = result.trackName else { continue }
            let dedupeKey = "\(artist)|\(title)".lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }
            var track: Track?
            if resolveTracks {
                track = await search.findTrack(artist: artist, title: title)
            }
            hits.append(LyricsSearchHit(id: dedupeKey, artist: artist, title: title, track: track))
        }
        return hits
    }
}

// MARK: - Translation

protocol TranslationService {
    func translate(_ text: String, target: String) async throws -> String
}

/// LibreTranslate: открытый само-хостируемый переводчик.
/// URL настраивается в настройках (публичные инстансы могут требовать ключ — поле есть).
struct LibreTranslateService: TranslationService {
    let url: String
    let apiKey: String?
    private let client = HTTPClient.shared

    struct Request: Encodable {
        let q: String
        let source: String
        let target: String
        let format: String
        let apiKey: String?
    }

    struct Response: Decodable {
        let translatedText: String?
        let error: String?
    }

    func translate(_ text: String, target: String) async throws -> String {
        let endpoint = url.trimmed.isEmpty
            ? "https://translate.fedilab.app/translate"
            : url.trimmed
        guard let baseURL = URL(string: endpoint) else {
            throw ProviderError.unavailable("Некорректный URL переводчика в настройках.")
        }
        let body = try JSONEncoder().encode(
            Request(q: text, source: "auto", target: target, format: "text", apiKey: apiKey)
        )
        let response = try await client.post(baseURL, body: body,
                                             headers: ["Content-Type": "application/json"],
                                             as: Response.self)
        if let error = response.error {
            throw ProviderError.unavailable("Переводчик: \(error)")
        }
        guard let translated = response.translatedText, !translated.isEmpty else {
            throw ProviderError.unavailable("Переводчик не вернул текст.")
        }
        return translated
    }
}
