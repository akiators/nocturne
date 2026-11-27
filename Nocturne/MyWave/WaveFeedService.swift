import Foundation

/// Сервис My Wave: собирает очередь из профиля пользователя, миксы по настроению,
/// автоматически дополняет очередь во время воспроизведения. Всё локально.
@MainActor
final class WaveFeedService: ObservableObject {
    private let store: LibraryStore
    private let registry: ProviderRegistry
    private let search: SearchService

    @Published var isBuilding = false
    @Published var lastError: String?

    init(store: LibraryStore, registry: ProviderRegistry, settings: SettingsStore) {
        self.store = store
        self.registry = registry
        self.search = SearchService(registry: registry, store: store)
        self.explorationRate = 0.25
        self._settings = settings
    }

    private let _settings: SettingsStore
    private var explorationRate: Double

    struct Mix: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let tracks: [Track]
    }

    // MARK: - Пул кандидатов

    private func baseCandidates(seedArtists: [String]) async -> [Track] {
        var pool: [Track] = []
        var seen = Set<String>()
        func add(_ tracks: [Track]) {
            for track in tracks where seen.insert(track.searchKey).inserted {
                pool.append(track)
            }
        }
        add(store.favoriteTracks())
        add(store.allTracks().filter { $0.provider == .local })
        let recent = store.recentPlays(limit: 60).compactMap { store.track(id: $0.trackID) }
        add(recent)

        let fromProviders = await search.candidatePool(seedArtists: seedArtists, limit: 60)
        add(fromProviders)
        return pool
    }

    private func seedArtistsFromProfile() -> [String] {
        var counts: [String: Int] = [:]
        for track in store.favoriteTracks() {
            counts[track.artist, default: 0] += 2
        }
        for (artist, _) in store.topArtists(from: Date().addingTimeInterval(-30 * 86_400),
                                            to: Date(), limit: 10) {
            counts[artist, default: 0] += 1
        }
        return Array(counts.sorted { $0.value > $1.value }.prefix(6).map(\.key))
    }

    // MARK: - Волнa

    /// Первичная персональная волна.
    func buildWave(count: Int = 20) async -> [Track] {
        isBuilding = true
        defer { isBuilding = false }
        let profile = RecommendationEngine.buildProfile(store: store, explorationRate: explorationRate)
        let candidates = await baseCandidates(seedArtists: seedArtistsFromProfile())
        guard !candidates.isEmpty else { return [] }
        return RecommendationEngine.selectWave(candidates: candidates,
                                               profile: profile,
                                               count: count,
                                               exploration: explorationRate)
    }

    /// Автодополнение очереди во время воспроизведения.
    func extendQueue(currentQueue: [Track]) async -> [Track] {
        let profile = RecommendationEngine.buildProfile(store: store, explorationRate: explorationRate)
        let candidates = await baseCandidates(seedArtists: seedArtistsFromProfile())
        guard !candidates.isEmpty else { return [] }
        return RecommendationEngine.selectWave(candidates: candidates,
                                               profile: profile,
                                               count: 10,
                                               exploration: explorationRate,
                                               excluded: Set(currentQueue.map(\.id)))
    }

    // MARK: - Миксы

    static let moodMixes: [(id: String, title: String, subtitle: String, keywords: [String])] = [
        ("morning", "Утро", "мягкий старт дня", ["acoustic", "indie", "chill", "lofi", "ambient"]),
        ("focus", "Фокус", "музыка для работы", ["ambient", "instrumental", "lofi", "piano", "minimal"]),
        ("workout", "Тренировка", "энергия и ритм", ["edm", "dance", "electro", "house", "techno"]),
        ("evening", "Вечер", "спокойный вечер", ["jazz", "soul", "rnb", "acoustic", "ballad"]),
        ("night", "Ночь", "глубина и тишина", ["ambient", "sleep", "classical", "piano"]),
        ("discovery", "Открытия", "новая музыка для вас", ["new", "indie", "alternative"])
    ]

    func moodMix(id: String, count: Int = 12) async -> Mix? {
        guard let mix = Self.moodMixes.first(where: { $0.id == id }) else { return nil }
        let profile = RecommendationEngine.buildProfile(store: store, explorationRate: explorationRate)
        let candidates = await baseCandidates(seedArtists: seedArtistsFromProfile())

        var genreMatched: [Track] = []
        if let deezer = registry.provider(.deezer) {
            for keyword in mix.keywords.prefix(2) {
                if let result = try? await deezer.search(keyword, limit: 15) {
                    genreMatched.append(contentsOf: result.tracks)
                }
            }
        }

        let combined = genreMatched + candidates
        let tracks = RecommendationEngine.selectWave(candidates: combined,
                                                     profile: profile,
                                                     count: count,
                                                     exploration: 0.4,
                                                     maxSameArtistConsecutive: 1)
        guard !tracks.isEmpty else { return nil }
        return Mix(id: mix.id, title: mix.title, subtitle: mix.subtitle, tracks: tracks)
    }

    func dailyMixes() async -> [Mix] {
        var mixes: [Mix] = []
        for mood in Self.moodMixes.prefix(3) {
            if let mix = await moodMix(id: mood.id, count: 10) {
                mixes.append(mix)
            }
        }
        return mixes
    }

    /// Радио по треку: похожие через провайдеров + волна от трека.
    func radio(for track: Track, count: Int = 15) async -> [Track] {
        var related: [Track] = []
        if let provider = registry.provider(track.provider),
           provider.capabilities.contains(.relatedTracks) {
            related = (try? await provider.relatedTracks(for: track, limit: count)) ?? []
        }
        let profile = RecommendationEngine.buildProfile(store: store, explorationRate: 0.3)
        let more = await baseCandidates(seedArtists: [track.artist])
        let candidates = related + more
        return RecommendationEngine.selectWave(candidates: candidates,
                                               profile: profile,
                                               count: count,
                                               exploration: 0.35,
                                               excluded: [track.id],
                                               maxSameArtistConsecutive: 1)
    }

    func setExploration(_ value: Double) {
        explorationRate = max(0.0, min(1.0, value))
    }
}
