import Foundation

/// Deezer через открытый публичный API api.deezer.com (без ключей и авторизации).
/// Легально доступны: поиск, метаданные, чарты, плейлисты, 30-секундные preview-фрагменты.
/// Полное воспроизведение и FLAC требуют подписки Deezer и не предоставляются сторонним
/// приложениям — для полных трек используется handoff в приложение Deezer.
final class DeezerProvider: MusicProvider {
    let id: ProviderID = .deezer
    let capabilities: ProviderCapabilities = [.search, .previewPlayback, .playlistImport, .relatedTracks, .handoff]
    var isConfigured: Bool { true }
    var setupHint: String { "Работает сразу, без аккаунта: поиск, метаданные и 30-секундные фрагменты. Полные треки — через приложение Deezer." }

    private let client = HTTPClient.shared
    private let baseURL = "https://api.deezer.com"

    // MARK: - Deezer DTO

    struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String; let pictureMedium: String?
                enum CodingKeys: String, CodingKey { case name; case pictureMedium = "picture_medium" } }
            struct Album: Decodable { let title: String?; let coverMedium: String?
                enum CodingKeys: String, CodingKey { case title; case coverMedium = "cover_medium" } }
            let id: Int64
            let title: String
            let duration: Int
            let preview: String?
            let explicitLyrics: Bool?
            let artist: Artist?
            let album: Album?
            enum CodingKeys: String, CodingKey {
                case id, title, duration, preview, artist, album
                case explicitLyrics = "explicit_lyrics"
            }
        }
        let data: [Item]?
        let error: DeezerError?
    }

    struct DeezerError: Decodable {
        let type: String?
        let message: String?
    }

    // MARK: - Mapping

    private func track(from item: SearchResponse.Item) -> Track {
        Track(provider: .deezer,
              externalID: String(item.id),
              title: item.title,
              artist: item.artist?.name ?? "Неизвестный исполнитель",
              album: item.album?.title,
              duration: TimeInterval(item.duration),
              artworkURL: item.album?.coverMedium.flatMap(URL.init(string:)),
              streamURL: item.preview.flatMap(URL.init(string:)),
              isPreview: true,
              explicit: item.explicitLyrics ?? false)
    }

    // MARK: - MusicProvider

    func search(_ query: String, limit: Int) async throws -> SearchResults {
        guard let url = URL(string: "\(baseURL)/search?q=\(query.urlEncoded)&limit=\(limit)") else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        let response = try await client.getJSON(url, as: SearchResponse.self)
        if let error = response.error {
            throw ProviderError.unavailable("Deezer: \(error.message ?? "ошибка API")")
        }
        let tracks = (response.data ?? []).map(track)
        var results = SearchResults(tracks: tracks)
        results.byProvider[.deezer] = results
        return results
    }

    func chartTracks(limit: Int) async throws -> [Track] {
        guard let url = URL(string: "\(baseURL)/chart/0/tracks?limit=\(limit)") else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        let response = try await client.getJSON(url, as: SearchResponse.self)
        return (response.data ?? []).map(track)
    }

    /// Похожие треки: топ каталога того же исполнителя.
    func relatedTracks(for track: Track, limit: Int) async throws -> [Track] {
        guard !track.artist.isEmpty else { return [] }
        let response = try await search(track.artist, limit: limit + 2)
        return response.tracks.filter { $0.id != track.id }.prefix(limit).map { $0 }
    }

    /// Импорт плейлиста по ссылке вида deezer.com/playlist/12345 или deezer.page.link.
    func playlistTracks(from url: URL) async throws -> [Track] {
        guard let id = Self.playlistID(from: url) else {
            throw ProviderError.unavailable("Это не похоже на ссылку плейлиста Deezer (ожидается /playlist/<id>).")
        }
        guard let apiURL = URL(string: "\(baseURL)/playlist/\(id)?limit=200") else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        let response = try await client.getJSON(apiURL, as: PlaylistResponse.self)
        let tracks = (response.tracks?.data ?? []).map(track)
        guard !tracks.isEmpty else {
            throw ProviderError.unavailable("Плейлист Deezer пуст или недоступен.")
        }
        return tracks
    }

    struct PlaylistResponse: Decodable {
        struct Container: Decodable { let data: [SearchResponse.Item]? }
        let title: String?
        let tracks: Container?
    }

    static func playlistID(from url: URL) -> String? {
        if let last = url.pathComponents.last, last != "playlist", url.path.contains("playlist") {
            return last
        }
        return nil
    }

    func handoffURL(for track: Track) -> URL? {
        URL(string: "https://www.deezer.com/track/\(track.externalID)")
    }
}

extension String {
    var urlEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
