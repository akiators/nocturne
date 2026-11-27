import ActivityKit
import Foundation

/// Атрибуты Live Activity плеера: экран блокировки + Dynamic Island.
/// Файл общий для основного таргета и виджет-расширения.
@available(iOS 16.1, *)
struct PlayerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var elapsed: TimeInterval
        var duration: TimeInterval
        var artworkData: Data?
    }

    var trackKey: String
}
