import Foundation

/// Genius: официальный бесплатный API (пользователь вставляет свой бесплатный токен
/// из https://genius.com/api-clients в настройках; токен хранится в Keychain).
/// Даёт «смысл трека»: описание песни из карточки Genius — легальная замена
/// scraping-аннотациям Mimose Plus. Плюс локальные заметки пользователя (LibraryStore).
final class GeniusService {
    private let settings: SettingsStore
    private let client = HTTPClient.shared

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isConfigured: Bool { settings.secret("genius_token") != nil }

    struct SearchResponse: Decodable {
        struct Hit: Decodable {
            struct Result: Decodable {
                struct PrimaryArtist: Decodable { let name: String? }
                let id: Int
                let fullTitle: String?
                let url: String?
                let primaryArtist: PrimaryArtist?
                enum CodingKeys: String, CodingKey {
                    case id, url, result
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
                    case description, song
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
