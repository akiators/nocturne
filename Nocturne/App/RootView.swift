import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case wave, search, library, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wave: return "Волна"
        case .search: return "Поиск"
        case .library: return "Музыка"
        case .settings: return "Настройки"
        }
    }

    var icon: String {
        switch self {
        case .wave: return "water.waves"
        case .search: return "magnifyingglass"
        case .library: return "music.note.list"
        case .settings: return "gearshape"
        }
    }
}

/// Корневой экран: кастомный компактный таббар (как у Mimose), мини-плеер,
/// полноэкранный плеер поверх.
struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController

    @State private var selectedTab: MainTab = .wave
    @State private var showFullPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.bottom, bottomInset)

            VStack(spacing: 0) {
                if player.currentTrack != nil {
                    MiniPlayerView(showFullPlayer: $showFullPlayer)
                }
                tabBar
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showFullPlayer) {
            PlayerFullView()
        }
    }

    private var bottomInset: CGFloat {
        let base = Metrics.tabBarHeight + (player.currentTrack != nil ? Metrics.miniPlayerHeight + 8 : 0)
        return base + 8
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .wave: WaveView()
        case .search: SearchView()
        case .library: LibraryView()
        case .settings: SettingsView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.stroke).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: MainTab) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.title)
                    .font(.caption())
            }
            .foregroundColor(selectedTab == tab ? Palette.accent : Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini player

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlayerController
    @Binding var showFullPlayer: Bool

    var body: some View {
        Button {
            Haptics.light()
            showFullPlayer = true
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: player.currentTrack?.artworkURL, size: Metrics.coverSmall, radius: Metrics.cornerS)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.title ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    Text(player.currentTrack?.artist ?? "")
                        .font(.secondary())
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Haptics.light()
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Palette.textPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.light()
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Palette.textSecondary)
                        .frame(width: 36, height: 40)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerM, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: Metrics.cornerM, style: .continuous)
                        .stroke(Palette.stroke, lineWidth: 0.5))
            )
            .padding(.horizontal, 10)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
