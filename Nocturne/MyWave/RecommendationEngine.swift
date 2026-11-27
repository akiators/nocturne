import Foundation

/// Детерминированный генератор (для тестов и воспроизводимых подборок).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Локальный алгоритм My Wave: скоринг кандидатов на профиле пользователя.
/// Работает полностью офлайн: аффинити к исполнителям, лайки/дизлайки,
/// свежесть прослушиваний, диверсификация, исследовательская доля.
enum RecommendationEngine {

    struct Profile {
        var artistAffinity: [String: Double] = [:]
        var favoriteIDs: Set<String> = []
        var dislikedIDs: Set<String> = []
        var likedArtists: Set<String> = []
        var recentPlayCounts: [String: Int] = [:]      // trackID → число запусков за окно
        var lastPlayed: [String: Date] = [:]
        var explorationRate: Double = 0.25             // доля «новинок» в волне
    }

    enum Weights {
        static let artistAffinity: Double = 2.0
        static let likedArtist: Double = 1.5
        static let favorite: Double = 0.5
        static let recentlyPlayedPenalty: Double = 3.0
        static let dislikedPenalty: Double = 50
        static let playableBonus: Double = 1.0
        static let familiarity: Double = 0.4
    }

    /// Скоринг одного трека. exploration ∈ [0, 1] — текущая доля исследований.
    static func score(track: Track, profile: Profile, exploration: Double, random: Double) -> Double {
        var score = 0.0

        let affinity = profile.artistAffinity[track.artist.lowercased()] ?? 0
        score += affinity * Weights.artistAffinity

        if profile.likedArtists.contains(track.artist.lowercased()) {
            score += Weights.likedArtist
        }

        if profile.favoriteIDs.contains(track.id) {
            score += Weights.favorite
        }

        if profile.dislikedIDs.contains(track.id) {
            score -= Weights.dislikedPenalty
        }

        if let plays = profile.recentPlayCounts[track.id], plays > 0 {
            score -= Weights.recentlyPlayedPenalty * Double(plays)
        }

        if let lastPlayed = profile.lastPlayed[track.id] {
            let days = Date().timeIntervalSince(lastPlayed) / 86_400
            if days < 2 { score -= 4 }
            else if days < 5 { score -= 1.5 }
        }

        // Знакомость: часто слышанные исполнители удерживают в потоке.
        score += min(affinity, 3) * Weights.familiarity

        // Можно ли реально воспроизвести (preview/local) — приоритет.
        if track.streamURL != nil || profile.favoriteIDs.contains(track.id) {
            score += Weights.playableBonus
        }

        // Исследовательская компонента: чем выше exploration, тем больше веса новизне.
        score += exploration * (1.5 + random * 2.0)

        return score
    }

    /// Отбор волны из пула кандидатов: жадный скоринг + диверсификация исполнителей.
    /// - Parameters:
    ///   - maxSameArtistConsecutive: не более N подряд треков одного артиста.
    ///   - excluded: треки, которых не должно быть (текущая очередь).
    static func selectWave(candidates: [Track],
                           profile: Profile,
                           count: Int,
                           exploration: Double,
                           excluded: Set<String> = [],
                           maxSameArtistConsecutive: Int = 2,
                           seed: UInt64 = UInt64(Date().timeIntervalSince1970)) -> [Track] {
        var generator = SeededGenerator(seed: seed)
        let scored = candidates
            .filter { !excluded.contains($0.id) && !profile.dislikedIDs.contains($0.id) }
            .map { track -> (Track, Double) in
                (track, score(track: track,
                              profile: profile,
                              exploration: exploration,
                              random: Double.random(in: 0...1, using: &generator)))
            }
            .sorted { $0.1 > $1.1 }

        var result: [Track] = []
        var usedArtists: [String: Int] = [:]

        for (track, _) in scored {
            guard result.count < count else { break }

            let artistKey = track.artist.lowercased()
            // Лимит на артиста в целом.
            if (usedArtists[artistKey, default: 0]) >= 4 {
                continue
            }
            // Диверсификация: не допускать N подряд треков одного артиста
            // (окно по уже выбранным, а не по позиции в сортировке — иначе
            // отклонённый трек блокировал бы всех следующих «своих»).
            if result.count >= maxSameArtistConsecutive,
               (0..<maxSameArtistConsecutive).allSatisfy({ offset in
                   result[result.count - 1 - offset].artist.lowercased() == artistKey
               }) {
                continue
            }
            usedArtists[artistKey, default: 0] += 1
            result.append(track)
        }
        return result
    }

    /// Профиль из локальных данных хранилища.
    static func buildProfile(store: LibraryStore, explorationRate: Double = 0.25) -> Profile {
        var profile = Profile()
        profile.explorationRate = explorationRate
        profile.favoriteIDs = store.favoriteIDs()
        profile.dislikedIDs = store.dislikedIDs()

        let windowStart = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        for event in store.playsBetween(from: windowStart, to: Date().addingTimeInterval(60)) {
            profile.recentPlayCounts[event.trackID, default: 0] += 1
            if let existing = profile.lastPlayed[event.trackID], existing > event.playedAt {
                continue
            }
            profile.lastPlayed[event.trackID] = event.playedAt
        }

        for (artist, score) in store.artistAffinity() {
            profile.artistAffinity[artist.lowercased()] = score
        }

        // Артисты из лайков считаем любимыми.
        for track in store.favoriteTracks() {
            profile.likedArtists.insert(track.artist.lowercased())
        }
        return profile
    }
}
