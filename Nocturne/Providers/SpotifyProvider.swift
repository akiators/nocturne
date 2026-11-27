import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// Spotify: OAuth PKCE + Web API.
/// Пользователь один раз создаёт бесплатное приложение на developer.spotify.com,
/// вставляет Client ID в настройках — поиск и библиотека работают без Premium-аккаунта.
/// Воспроизведение: 30-сек preview (если есть в ответе API) + handoff `spotify:track:`.
/// Полный стриминг чужих потоков не предоставляется Spotify сторонним приложениям
/// без App Remote SDK — остаётся handoff, что честно и легально.
@MainActor
final class SpotifyProvider: MusicProvider {
    let id: ProviderID = .spotify
    let capabilities: ProviderCapabilities = [.search, .previewPlayback, .playlistImport, .relatedTracks, .handoff, .auth]
    var isConfigured: Bool { clientID != nil && currentToken != nil }
    var setupHint: String {
        clientID == nil
            ? "Создайте приложение на developer.spotify.com (Redirect URI: nocturne://auth/spotify) и вставьте Client ID."
            : "Нажмите «Войти», чтобы подключить аккаунт Spotify (бесплатный аккаунт подходит)."
    }

    private let client = HTTPClient.shared
    private let settings: SettingsStore
    private var webSession: ASWebAuthenticationSession?

    static let redirectURI = "nocturne://auth/spotify"
    static let tokenExpiresKey = "spotify_token_expires_at"

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var clientID: String? { settings.secret("spotify_client_id") }

    var currentToken: String? {
        guard let token = settings.secret("spotify_token") else { return nil }
        let expires = UserDefaults.standard.double(forKey: Self.tokenExpiresKey)
        if expires > 0, Date().timeIntervalSince1970 > expires - 60 {
            return nil // истёк — попробует обновиться при следующем вызове refresh()
        }
        return token
    }

    // MARK: - OAuth PKCE

    func login() async throws {
        guard let clientID else {
            throw ProviderError.notConfigured("Spotify")
        }
        let verifier = Self.randomURLSafeBase64(count: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        settings.setSecret(verifier, account: "spotify_verifier")

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: "user-read-private user-library-read playlist-read-private")
        ]

        let authorizeURL = components.url!
        let code: String = try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = ASWebAuthenticationSession(url: authorizeURL,
                                                         callbackURLScheme: "nocturne") { callbackURL, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let callbackURL,
                          let item = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
                              .queryItems?.first(where: { $0.name == "code" }),
                          let code = item.value else {
                        continuation.resume(throwing: ProviderError.authRequired("Spotify"))
                        return
                    }
                    continuation.resume(returning: code)
                }
                session.prefersEphemeralWebBrowserSession = false
                session.start()
                self.webSession = session
            }
        }
        try await exchange(code: code, verifier: verifier)
    }

    private func exchange(code: String, verifier: String) async throws {
        guard let clientID else { throw ProviderError.notConfigured("Spotify") }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        let form = "grant_type=authorization_code&code=\(code.urlEncoded)&redirect_uri=\(Self.redirectURI.urlEncoded)&client_id=\(clientID.urlEncoded)&code_verifier=\(verifier.urlEncoded)"
        request.httpBody = form.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await client.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.prefix(200)
            throw ProviderError.unavailable("Spotify: не удалось получить токен \(detail.map(String.init) ?? "")")
        }
        struct TokenResponse: Decodable { let accessToken: String; let refreshToken: String?; let expiresIn: Int
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
            } }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        await MainActor.run {
            settings.setSecret(token.accessToken, account: "spotify_token")
            if let refresh = token.refreshToken {
                settings.setSecret(refresh, account: "spotify_refresh")
            }
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970 + TimeInterval(token.expiresIn),
                                   forKey: Self.tokenExpiresKey)
    }

    /// Обновление токена по refresh-токену.
    func refresh() async {
        guard let clientID, let refreshToken = settings.secret("spotify_refresh") else { return }
        let form = "grant_type=refresh_token&refresh_token=\(refreshToken.urlEncoded)&client_id=\(clientID.urlEncoded)"
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.httpBody = form.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await client.session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            struct TokenResponse: Decodable { let accessToken: String; let expiresIn: Int
                enum CodingKeys: String, CodingKey { case accessToken = "access_token", expiresIn = "expires_in" } }
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            await MainActor.run {
                settings.setSecret(token.accessToken, account: "spotify_token")
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970 + TimeInterval(token.expiresIn),
                                       forKey: Self.tokenExpiresKey)
        } catch {
            // Молча — следующий вызов снова попробует.
        }
    }

    func logout() async {
        await MainActor.run {
            settings.setSecret(nil, account: "spotify_token")
            settings.setSecret(nil, account: "spotify_refresh")
        }
        UserDefaults.standard.set(0, forKey: Self.tokenExpiresKey)
    }

    // MARK: - Web API

    private func authorizedHeaders() async throws -> [String: String] {
        var token = currentToken
        if token == nil {
            await refresh()
            token = currentToken
        }
        guard let token else { throw ProviderError.authRequired("Spotify") }
        return ["Authorization": "Bearer \(token)"]
    }

    struct WebSearchResponse: Decodable {
        struct Container: Decodable { let items: [TrackItem]? }
        struct TrackItem: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable { let name: String; let images: [Image]? }
            struct Image: Decodable { let url: String }
            let id: String
            let name: String
            let artists: [Artist]
            let album: Album?
            let durationMS: Int?
            let previewURL: String?
            let explicit: Bool?
            enum CodingKeys: String, CodingKey {
                case id, name, artists, album, explicit
                case durationMS = "duration_ms"
                case previewURL = "preview_url"
            }
        }
        let tracks: Container?
    }

    private func mapTrack(_ item: WebSearchResponse.TrackItem) -> Track {
        Track(provider: .spotify,
              externalID: item.id,
              title: item.name,
              artist: item.artists.map(\.name).joined(separator: ", "),
              album: item.album?.name,
              duration: TimeInterval(item.durationMS ?? 0) / 1000,
              artworkURL: item.album?.images?.first?.url.flatMap(URL.init(string:)),
              streamURL: item.previewURL.flatMap(URL.init(string:)),
              isPreview: item.previewURL != nil,
              explicit: item.explicit ?? false)
    }

    func search(_ query: String, limit: Int) async throws -> SearchResults {
        let headers = try await authorizedHeaders()
        guard let url = URL(string: "https://api.spotify.com/v1/search?q=\(query.urlEncoded)&type=track&limit=\(limit)") else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        let response = try await client.getJSON(url, as: WebSearchResponse.self, headers: headers)
        let tracks = (response.tracks?.items ?? []).map(mapTrack)
        var results = SearchResults(tracks: tracks)
        results.byProvider[.spotify] = results
        return results
    }

    func relatedTracks(for track: Track, limit: Int) async throws -> [Track] {
        let results = try await search(track.artist, limit: limit + 2)
        return results.tracks.filter { $0.id != track.id }.prefix(limit).map { $0 }
    }

    /// Импорт: open.spotify.com/playlist/<id>
    func playlistTracks(from url: URL) async throws -> [Track] {
        guard let id = url.pathComponents.first(where: { $0 != "playlist" && $0.count == 22 }) else {
            throw ProviderError.unavailable("Это не ссылка на плейлист Spotify (нужен open.spotify.com/playlist/<id>).")
        }
        let headers = try await authorizedHeaders()
        guard let api = URL(string: "https://api.spotify.com/v1/playlists/\(id)/tracks?limit=100") else {
            throw ProviderError.unavailable("Некорректный запрос.")
        }
        let response = try await client.getJSON(api, as: WebSearchResponse.Container.self, headers: headers)
        let tracks = (response.items ?? []).compactMap { $0 }.map(mapTrack)
        guard !tracks.isEmpty else {
            throw ProviderError.unavailable("Плейлист Spotify пуст или приватный.")
        }
        return tracks
    }

    func handoffURL(for track: Track) -> URL? {
        URL(string: "spotify:track:\(track.externalID)")
    }

    // MARK: - PKCE utils

    nonisolated static func randomURLSafeBase64(count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    nonisolated static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
