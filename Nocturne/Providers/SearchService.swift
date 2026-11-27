import Foundation

/// Объединённый поиск по всем активным источникам.
@MainActor
final class SearchService {
    private let registry: ProviderRegistry
    private let store: LibraryStore

    init(registry: ProviderRegistry, store: LibraryStore) {
        self.registry = registry
        self.store = store
    }

    struct ProviderOutcome {
        let providerID: ProviderID
        let result: Result<SearchResults, Error>
    }

    /// Параллельный поиск; ошибки отдельных провайдеров не прерывают общий результат.
    func search(_ query: String, limit: Int = 30) async -> [ProviderOutcome] {
        let providers = registry.activeSearchProviders()
        let q = query.trimmed
        guard !q.isEmpty else { return [] }

        await withTaskGroup(of: ProviderOutcome.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let result = try await provider.search(q, limit: limit)
                        return ProviderOutcome(providerID: provider.id, result: .success(result))
                    } catch {
                        return ProviderOutcome(providerID: provider.id, result: .failure(error))
                    }
                }
            }
            return await group.reduce(into: []) { acc, outcome in acc.append(outcome) }
        }
    }

    /// Объединённый результат с локальной библиотекой в приоритете.
    func unifiedSearch(_ query: String, limit: Int = 30) async -> (results: SearchResults, outcomes: [ProviderOutcome]) {
        let localTracks = store.searchTracks(query).filter { $0.provider == .local }
        var local = SearchResults(tracks: Array(localTracks.prefix(limit)))
        local.byProvider[.local] = local

        let outcomes = await search(query, limit: limit)
        var combined = local
        for outcome in outcomes {
            if case .success(let result) = outcome.result {
                combined = combined + result
            }
        }
        return (combined, outcomes)
    }

    /// Найти конкретный трек («исполнитель название») в активных источниках —
    /// используется My Wave и поиском по тексту.
    func findTrack(artist: String, title: String) async -> Track? {
        let query = "\(artist) \(title)"
        let outcomes = await search(query, limit: 10)
        let normalized = title.lowercased().trimmed
        for outcome in outcomes {
            if case .success(let result) = outcome.result {
                if let exact = result.tracks.first(where: { $0.title.lowercased().trimmed == normalized }) {
                    return exact
                }
            }
        }
        for outcome in outcomes {
            if case .success(let result) = outcome.result, let first = result.tracks.first {
                return first
            }
        }
        return nil
    }

    /// Пул кандидатов для рекомендаций: чарты + каталог по любимым исполнителям.
    func candidatePool(seedArtists: [String], limit: Int = 60) async -> [Track] {
        var pool: [Track] = []
        var seen = Set<String>()

        if let deezer = registry.provider(.deezer) {
            if let chart = try? await deezer.chartTracks(limit: 50) {
                for track in chart where seen.insert(track.searchKey).inserted {
                    pool.append(track)
                }
            }
        }
        for artist in seedArtists.prefix(8) {
            let outcomes = await search(artist, limit: 10)
            for outcome in outcomes {
                if case .success(let result) = outcome.result {
                    for track in result.tracks where seen.insert(track.searchKey).inserted {
                        pool.append(track)
                    }
                }
            }
            if pool.count >= limit { break }
        }
        return pool
    }
}
