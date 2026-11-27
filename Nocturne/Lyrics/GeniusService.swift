import Foundation

/// Genius: официальный бесплатный API (пользователь вставляет свой бесплатный токен
/// из https://genius.com/api-clients в настройках; токен хранится в Keychain).
/// Даёт «смысл трека»: описание песни из карточки Genius — легальная замена
/// scraping-аннотациям Mimose Plus. Плюс локальные заметки пользователя (LibraryStore).
@MainActor
final class GeniusService {
    private let settings: SettingsStore
    private let store: LibraryStore
    private let client = HTTPClient.shared

    init(store: LibraryStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    var isConfigured: Bool { settings.secret("genius_token") != nil }

    struct SearchResponse: Decodable {
        struct Hit: Decodable {
            struct Result: Decodable {
                struct PrimaryArtist: Decodable {
                    let id: Int?
                    let name: String?
                }
                let id: Int
                let fullTitle: String?
                let url: String?
                let primaryArtist: PrimaryArtist?
                enum CodingKeys: String, CodingKey {
                    case id, url
                    case fullTitle = "full_title"
                    case primaryArtist = "primary_artist"
                }
            }
            let result: Result
        }
        struct ResponseBox: Decodable { let hits: [Hit]? }
        let response: ResponseBox?
    }

    struct SongHit: Identifiable {
        let id: Int
        let title: String
        let artist: String
        let artistID: Int?
        let pageURL: String?
    }

    func search(query: String) async throws -> [SongHit] {
        guard let token = settings.secret("genius_token") else {
            throw ProviderError.notConfigured("Genius")
        }
        guard let url = URL(string: "https://api.genius.com/search?q=\(query.urlEncoded)") else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        let response = try await client.getJSON(url, as: SearchResponse.self,
                                                headers: ["Authorization": "Bearer \(token)"])
        return (response.response?.hits ?? []).map { hit in
            SongHit(id: hit.result.id,
                    title: hit.result.fullTitle ?? "",
                    artist: hit.result.primaryArtist?.name ?? "",
                    artistID: hit.result.primaryArtist?.id,
                    pageURL: hit.result.url)
        }
    }

    struct SongResponse: Decodable {
        struct SongBox: Decodable {
            struct Song: Decodable {
                struct DescriptionBox: Decodable { let plain: String? }
                let description: DescriptionBox?
                let releaseDate: String?
                let producerArtists: [ArtistBox]?
                struct ArtistBox: Decodable { let name: String? }
                enum CodingKeys: String, CodingKey {
                    case description
                    case releaseDate = "release_date"
                    case producerArtists = "producer_artists"
                }
            }
            let song: Song?
        }
        let response: SongBox?
    }

    struct SongFacts {
        let description: String?
        let releaseDate: String?
        let producers: [String]
    }

    // MARK: - Artist biography

    struct ArtistResponse: Decodable {
        struct ArtistBox: Decodable {
            struct Artist: Decodable {
                struct DescriptionBox: Decodable { let plain: String? }
                let id: Int?
                let name: String?
                let description: DescriptionBox?
                let imageUrl: String?
                enum CodingKeys: String, CodingKey {
                    case id, name, description
                    case imageUrl = "image_url"
                }
            }
            let artist: Artist?
        }
        let response: ArtistBox?
    }

    private struct ArtistBioCache: Codable {
        var text: String
        var fetchedAt: Date
    }

    private static let bioCacheDays = 30

    /// Биография артиста: Genius /artists/{id} (описание, plain) с кэшем на 30 дней.
    func artistBio(name: String) async -> String? {
        let key = "artist_bio:\(name.lowercased().trimmed)"
        if let json = store.kvString(key),
           let data = json.data(using: .utf8),
           let cached = try? JSONDecoder.standard.decode(ArtistBioCache.self, from: data),
           cached.fetchedAt.isWithin(days: Self.bioCacheDays) {
            return cached.text
        }

        guard isConfigured else { return nil }
        do {
            let hits = try await search(query: name)
            guard let artistID = hits.first(where: { $0.artistID != nil })?.artistID else { return nil }
            guard let token = settings.secret("genius_token"),
                  let url = URL(string: "https://api.genius.com/artists/\(artistID)?text_format=plain") else { return nil }
            let response = try await client.getJSON(url, as: ArtistResponse.self,
                                                    headers: ["Authorization": "Bearer \(token)"])
            guard let text = response.response?.artist?.description?.plain?.trimmed, !text.isEmpty else { return nil }

            let cache = ArtistBioCache(text: text, fetchedAt: Date())
            if let data = try? JSONEncoder.pretty.encode(cache),
               let json = String(data: data, encoding: .utf8) {
                store.kvSet(key, json)
            }
            return text
        } catch {
            return nil
        }
    }

    /// Описание/факты трека по Genius (text_format=plain).
    func songFacts(id: Int) async throws -> SongFacts {
        guard let token = settings.secret("genius_token") else {
            throw ProviderError.notConfigured("Genius")
        }
        guard let url = URL(string: "https://api.genius.com/songs/\(id)?text_format=plain") else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        let response = try await client.getJSON(url, as: SongResponse.self,
                                                headers: ["Authorization": "Bearer \(token)"])
        let song = response.response?.song
        return SongFacts(description: song?.description?.plain?.trimmed,
                         releaseDate: song?.releaseDate,
                         producers: (song?.producerArtists ?? []).compactMap(\.name))
    }
}
