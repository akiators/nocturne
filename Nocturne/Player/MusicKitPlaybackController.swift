import Foundation
import MusicKit

/// Полное воспроизведение Apple Music для подписчиков через ApplicationMusicPlayer.
/// Стриминг ведёт системный плеер: EQ, скорость и crossfade на этот режим
/// не действуют — UI честно показывает это. Деградация: без подписки играем
/// 30-сек preview через наш движок (см. PlayerController.start).
@MainActor
final class MusicKitPlaybackController: ObservableObject {
    private let player = ApplicationMusicPlayer.shared
    private var songCache: [String: Song] = [:]

    var isAuthorized: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    /// Есть ли право играть полный каталог (действующая подписка Apple Music).
    func canPlayCatalog() async -> Bool {
        guard isAuthorized else { return false }
        do {
            let subscription = try await MusicSubscription.current
            return subscription?.canPlayCatalogContent ?? false
        } catch {
            return false
        }
    }

    /// Резолв Song из каталога: сначала кэш, затем поиск «артист название».
    func resolveSong(for track: Track) async -> Song? {
        if let cached = songCache[track.externalID] { return cached }
        do {
            var request = MusicCatalogSearchRequest(term: "\(track.artist) \(track.title)",
                                                    types: [Song.self])
            request.limit = 5
            let response = try await request.response()
            guard let song = response.songs.first else { return nil }
            songCache[track.externalID] = song
            return song
        } catch {
            return nil
        }
    }

    var playbackTime: TimeInterval {
        player.playbackTime
    }

    func play(song: Song) async {
        player.queue = MusicPlayer.Queue(for: [song])
        player.playbackTime = 0
        do {
            try await player.play()
        } catch {
            // Ошибка воспроизведения (регион/подписка) — UI останется в состоянии паузы.
        }
    }

    func pause() {
        player.pause()
    }

    func resume() {
        Task { try? await player.play() }
    }

    func seek(to time: TimeInterval) {
        player.playbackTime = time
    }
}
