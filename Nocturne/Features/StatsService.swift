import Foundation

/// Расширенная статистика прослушивания: топы, время, динамика по дням.
final class StatsService {
    enum Period {
        case week, month, all

        var title: String {
            switch self {
            case .week: return "Неделя"
            case .month: return "Месяц"
            case .all: return "Всё время"
            }
        }

        var startDate: Date? {
            switch self {
            case .week: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            case .all: return nil
            }
        }
    }

    struct Snapshot {
        var topTracks: [(Track, Int)]
        var topArtists: [(String, Int)]
        var totalSeconds: TimeInterval
        var perDay: [(Date, TimeInterval)]
        var playCount: Int
    }

    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
    }

    func snapshot(period: Period) -> Snapshot {
        let from = period.startDate ?? Date(timeIntervalSince1970: 0)
        let to = Date()
        let trackIDs = store.topTrackIDs(from: from, to: to, limit: 20)
        var topTracks: [(Track, Int)] = []

        var counts: [String: Int] = [:]
        for event in store.playsBetween(from: from, to: to) where event.secondsPlayed >= LibraryStore.meaningfulPlaySeconds {
            counts[event.trackID, default: 0] += 1
        }
        for id in trackIDs {
            if let track = store.track(id: id) {
                topTracks.append((track, counts[id] ?? 1))
            }
        }

        let topArtists = store.topArtists(from: from, to: to, limit: 10)
        let total = store.totalListeningSeconds(from: from, to: to)
        let perDay = store.playsPerDay(days: 14)
        let playCount = store.playsBetween(from: from, to: to).count

        return Snapshot(topTracks: topTracks,
                        topArtists: topArtists,
                        totalSeconds: total,
                        perDay: perDay,
                        playCount: playCount)
    }
}
