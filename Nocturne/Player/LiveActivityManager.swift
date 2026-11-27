import Foundation
import ActivityKit
import UIKit

/// Управление Live Activity плеера со стороны приложения.
/// Класс без @available, чтобы PlayerController (iOS 15) мог держать его:
/// все обращения к ActivityKit внутри #available(iOS 16.1, *).
@MainActor
final class LiveActivityManager {
    private var activity: AnyObject?
    private var lastUpdateAt: Date = .distantPast

    func start(track: Track) {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        stop()

        let attributes = PlayerActivityAttributes(trackKey: track.id)
        let state = PlayerActivityAttributes.ContentState(
            title: track.title,
            artist: track.artist,
            isPlaying: true,
            elapsed: 0,
            duration: max(track.duration, 1),
            artworkData: nil)
        do {
            activity = try Activity<PlayerActivityAttributes>.request(
                attributes: attributes,
                state: state,
                pushType: nil)
        } catch {
            activity = nil
        }

        // Обложка подтянется асинхронно.
        guard let artworkURL = track.artworkURL else { return }
        Task { [weak self] in
            await ImageLoader.shared.prefetch(url: artworkURL)
            let key = artworkURL.absoluteString as NSString
            let data = ImageCache.shared.object(forKey: key)?.jpegData(compressionQuality: 0.85)
            self?.applyArtwork(data: data)
        }
    }

    func update(track: Track, isPlaying: Bool, elapsed: TimeInterval, force: Bool = false) {
        guard #available(iOS 16.1, *) else { return }
        guard let current = activity as? Activity<PlayerActivityAttributes> else { return }
        if current.attributes.trackKey != track.id {
            start(track: track)
            return
        }
        // Троттлинг: прогресс обновляем не чаще раза в 4 секунды.
        if !force, Date().timeIntervalSince(lastUpdateAt) < 4,
           current.contentState.isPlaying == isPlaying {
            return
        }
        lastUpdateAt = Date()
        let state = PlayerActivityAttributes.ContentState(
            title: track.title,
            artist: track.artist,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: max(track.duration, 1),
            artworkData: current.contentState.artworkData)
        Task {
            await current.update(using: state)
        }
    }

    func stop() {
        guard #available(iOS 16.1, *) else { return }
        guard let current = activity as? Activity<PlayerActivityAttributes> else { return }
        activity = nil
        Task {
            await current.end(dismissalPolicy: .immediate)
        }
    }

    private func applyArtwork(data: Data?) {
        guard #available(iOS 16.1, *) else { return }
        guard let current = activity as? Activity<PlayerActivityAttributes>, let data else { return }
        let state = current.contentState
        let updated = PlayerActivityAttributes.ContentState(
            title: state.title,
            artist: state.artist,
            isPlaying: state.isPlaying,
            elapsed: state.elapsed,
            duration: state.duration,
            artworkData: data)
        Task {
            await current.update(using: updated)
        }
    }
}
