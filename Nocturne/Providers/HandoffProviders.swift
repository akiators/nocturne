import Foundation

/// YouTube Music: официального публичного API воспроизведения не существует
/// (DRM/ToS). Реализуем честные функции: поиск через YouTube Data API v3 (бесплатный
/// ключ пользователя) и handoff в YouTube Music. Воспроизведение — не предоставляем.
final class YouTubeMusicProvider: MusicProvider {
    let id: ProviderID = .youTubeMusic
    let capabilities: ProviderCapabilities = [.search, .handoff, .auth]
    var isConfigured: Bool { settings.secret("yt_api_key") != nil }
    var setupHint: String { "Вставьте бесплатный ключ YouTube Data API (console.cloud.google.com → API и сервисы → Ключ). Воспроизведение недоступно по ToS — треки открываются в YouTube Music." }

    private let client = HTTPClient.shared
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                let title: String
                let channelTitle: String
                let thumbnails: [String: Thumb]
            }
            struct Thumb: Decodable { let url: String }
            struct IDBox: Decodable { let videoId: String? }
            let id: IDBox
            let snippet: Snippet
        }
        let items: [Item]?
    }

    func search(_ query: String, limit: Int) async throws -> SearchResults {
        guard let key = settings.secret("yt_api_key") else {
            throw ProviderError.notConfigured("YouTube Music")
        }
        guard let url = URL(string: "https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&videoCategoryId=10&maxResults=\(limit)&q=\(query.urlEncoded)&key=\(key.urlEncoded)") else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        let response = try await client.getJSON(url, as: SearchResponse.self)
        let tracks = (response.items ?? []).compactMap { item -> Track? in
            guard let videoID = item.id.videoId, !videoID.isEmpty else { return nil }
            let raw = item.snippet.title
            let parts = raw.components(separatedBy: " - ")
            let (artist, title) = parts.count >= 2
                ? (parts[0].trimmed, parts.dropFirst().joined(separator: " - ").trimmed)
                : (item.snippet.channelTitle, raw)
            return Track(provider: .youTubeMusic,
                         externalID: videoID,
                         title: title,
                         artist: artist,
                         duration: 0,
                         artworkURL: URL(string: item.snippet.thumbnails["medium"]?.url ?? ""),
                         streamURL: nil,
                         isPreview: false)
        }
        var results = SearchResults(tracks: tracks)
        results.byProvider[.youTubeMusic] = results
        return results
    }

    func handoffURL(for track: Track) -> URL? {
        URL(string: "https://music.youtube.com/watch?v=\(track.externalID)")
    }
}

/// VK Музыка: audio API закрыт для сторонних приложений с 2016 года, воспроизведение
/// и импорт без нарушений невозможны. Доступен только handoff — открытие аудиораздела VK.
final class VKMusicProvider: MusicProvider {
    let id: ProviderID = .vk
    let capabilities: ProviderCapabilities = [.handoff]
    var isConfigured: Bool { true }
    var setupHint: String { "VK не предоставляет публичный API аудио сторонним приложениям — доступно только открытие VK Музыки. Полное воспроизведение: Blocked (документировано)." }

    func search(_ query: String, limit: Int) async throws -> SearchResults {
        // Пустой результат вместо ошибки, чтобы общий поиск не падал.
        var results = SearchResults()
        results.byProvider[.vk] = results
        return results
    }

    func handoffURL(for track: Track) -> URL? {
        var components = URLComponents(string: "https://vk.com/audio")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(track.artist) \(track.title)")]
        return components?.url
    }

    func handoffSearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://vk.com/audio")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

/// SoundCloud: публичный API ограничен регистрацией приложений (закрыта выдача ключей),
/// оEmbed открыт. Реализуем метаданные по ссылке + handoff. Воспроизведение — не предоставляем.
final class SoundCloudProvider: MusicProvider {
    let id: ProviderID = .soundCloud
    let capabilities: ProviderCapabilities = [.handoff]
    var isConfigured: Bool { true }
    var setupHint: String { "SoundCloud закрыл выдачу API-ключей. Доступно открытие треков в SoundCloud по ссылке." }

    private let client = HTTPClient.shared

    struct OEmbedResponse: Decodable {
        let title: String?
        let authorName: String?
        let thumbnailURL: String?
        enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
            case thumbnailURL = "thumbnail_url"
        }
    }

    /// Метаданные трека по публичной ссылке (для импорта вручную).
    func resolveTrack(from url: URL) async throws -> Track {
        guard var components = URLComponents(url: URL(string: "https://soundcloud.com/oembed")!, resolvingAgainstBaseURL: false) else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        components.queryItems = [
            .init(name: "format", value: "json"),
            .init(name: "url", value: url.absoluteString)
        ]
        guard let requestURL = components.url else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        let response = try await client.getJSON(requestURL, as: OEmbedResponse.self)
        let parts = (response.title ?? "").components(separatedBy: " by ")
        let title = parts.first ?? response.title ?? "SoundCloud"
        let artist = parts.count > 1 ? parts.last! : (response.authorName ?? "SoundCloud")
        return Track(provider: .soundCloud,
                     externalID: url.absoluteString,
                     title: title,
                     artist: artist,
                     artworkURL: response.thumbnailURL.flatMap(URL.init(string:)))
    }

    func search(_ query: String, limit: Int) async throws -> SearchResults {
        var results = SearchResults()
        results.byProvider[.soundCloud] = results
        return results
    }

    func handoffURL(for track: Track) -> URL? {
        if track.externalID.hasPrefix("http") { return URL(string: track.externalID) }
        return URL(string: "https://soundcloud.com/search?q=\((track.artist + " " + track.title).urlEncoded)")
    }
}
