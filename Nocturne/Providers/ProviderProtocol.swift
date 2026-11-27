import Foundation

/// Общий контракт адаптера музыкального источника.
/// Каждый провайдер реализует только то, что сервис разрешает легально.
protocol MusicProvider: AnyObject {
    var id: ProviderID { get }
    var capabilities: ProviderCapabilities { get }
    var isConfigured: Bool { get }
    var setupHint: String { get }

    func search(_ query: String, limit: Int) async throws -> SearchResults
    func chartTracks(limit: Int) async throws -> [Track]
    func relatedTracks(for track: Track, limit: Int) async throws -> [Track]
    func playlistTracks(from url: URL) async throws -> [Track]
    func handoffURL(for track: Track) -> URL?
}

extension MusicProvider {
    func chartTracks(limit: Int) async throws -> [Track] { [] }
    func relatedTracks(for track: Track, limit: Int) async throws -> [Track] { [] }
    func playlistTracks(from url: URL) async throws -> [Track] {
        throw ProviderError.unavailable("\(id.displayName): импорт плейлистов из ссылок не поддерживается этим источником.")
    }
    func handoffURL(for track: Track) -> URL? { nil }
}

/// Реестр всех адаптеров источников.
@MainActor
final class ProviderRegistry: ObservableObject {
    let store: LibraryStore
    let settings: SettingsStore
    private var providersByID: [ProviderID: MusicProvider] = [:]

    init(store: LibraryStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings

        let local = LocalFilesProvider(store: store)
        let deezer = DeezerProvider()
        let appleMusic = AppleMusicProvider()
        let spotify = SpotifyProvider(settings: settings)
        let youtube = YouTubeMusicProvider(settings: settings)
        let vk = VKMusicProvider()
        let soundcloud = SoundCloudProvider()

        register(local)
        register(deezer)
        register(appleMusic)
        register(spotify)
        register(youtube)
        register(vk)
        register(soundcloud)
    }

    func register(_ provider: MusicProvider) {
        providersByID[provider.id] = provider
    }

    func provider(_ id: ProviderID) -> MusicProvider? {
        providersByID[id]
    }

    var allProviders: [MusicProvider] {
        ProviderID.allCases.compactMap { providersByID[$0] }
    }

    func isActive(_ id: ProviderID) -> Bool {
        settings.enabledProviders.contains(id)
    }

    /// Провайдеры, которые реально примут поисковый запрос.
    func activeSearchProviders() -> [MusicProvider] {
        allProviders.filter {
            isActive($0.id) && $0.isConfigured && $0.capabilities.contains(.search)
        }
    }

    /// Лучший доступный поток для трека: скачивание → прямой streamURL источника.
    func stream(for track: Track) async throws -> TrackStream {
        guard let provider = providersByID[track.provider] else {
            throw ProviderError.unavailable("Неизвестный источник: \(track.provider.rawValue)")
        }
        if let url = track.streamURL, url.isFileURL {
            return TrackStream(url: url, kind: .localFile, startAt: 0)
        }
        if provider.capabilities.contains(.fullPlayback), let url = track.streamURL {
            return TrackStream(url: url, kind: .remoteFull, startAt: 0)
        }
        if provider.capabilities.contains(.previewPlayback), let url = track.streamURL {
            return TrackStream(url: url, kind: .remotePreview, startAt: 0)
        }
        throw ProviderError.noStream(track)
    }

    func handoffURL(for track: Track) -> URL? {
        providersByID[track.provider]?.handoffURL(for: track)
    }
}
