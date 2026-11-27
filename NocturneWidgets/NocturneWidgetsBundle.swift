import WidgetKit
import SwiftUI
import ActivityKit

@main
struct NocturneWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlayerLiveActivity()
    }
}

/// Live Activity текущего трека: экран блокировки + Dynamic Island
/// (компактный, расширенный, минимальный режимы).
struct PlayerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlayerActivityAttributes.self) { context in
            lockScreenView(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    artworkView(context, size: 42)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .center, spacing: 2) {
                        Text(context.state.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.elapsed,
                                 total: max(context.state.duration, 1))
                        .tint(.purple)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.purple)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(.purple)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(.purple)
            }
        }
    }

    // MARK: - Lock screen

    private func lockScreenView(_ context: ActivityViewContext<PlayerActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            artworkView(context, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(context.state.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                ProgressView(value: context.state.elapsed,
                             total: max(context.state.duration, 1))
                    .tint(.purple)
            }
            Spacer()
            Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.purple)
        }
        .padding(14)
        .activityBackgroundTint(Color.black.opacity(0.55))
    }

    private func artworkView(_ context: ActivityViewContext<PlayerActivityAttributes>,
                             size: CGFloat) -> some View {
        ZStack {
            if let data = context.state.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color.purple, Color.pink],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.35))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(8)
    }
}
