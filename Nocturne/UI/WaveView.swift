import SwiftUI

/// Главный экран: My Wave, миксы по настроению, популярное, недавние, ассистент.
struct WaveView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var wave: WaveFeedService
    @EnvironmentObject private var assistant: AssistantEngine

    @State private var mixes: [WaveFeedService.Mix] = []
    @State private var chartTracks: [Track] = []
    @State private var recentTracks: [Track] = []
    @State private var buildingWave = false
    @State private var showAssistant = false
    @State private var selectedMix: WaveFeedService.Mix?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greeting
                    waveHero
                    assistantCard
                    if !mixes.isEmpty { mixesSection }
                    if !recentTracks.isEmpty { recentSection }
                    if !chartTracks.isEmpty { chartSection }
                }
                .padding(.vertical, 16)
            }
            .background(WaveBackground(intensity: 0.5))
            .navigationBarHidden(true)
            .task { await load() }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $selectedMix) { mix in
            MixDetailSheet(mix: mix)
        }
        .sheet(isPresented: $showAssistant) {
            AssistantView()
        }
    }

    private var greeting: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.greetingText)
                    .font(.display(28))
                    .foregroundColor(Palette.textPrimary)
                Text("Тёмное пространство вашей музыки")
                    .font(.secondary())
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Button {
                Haptics.light()
                showAssistant = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.thinMaterial))
            }
        }
        .padding(.horizontal, Metrics.hPadding)
    }

    static var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }

    private var waveHero: some View {
        Button {
            Task { await startWave() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.cornerL, style: .continuous)
                    .fill(Palette.waveGradient)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "water.waves")
                            .font(.system(size: 22, weight: .bold))
                        Text("My Wave")
                            .font(.title(22))
                        Spacer()
                        if buildingWave || wave.isBuilding {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    Text("Персональный поток по вашему вкусу: лайки, история, открытия")
                        .font(.secondary())
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Metrics.hPadding)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(buildingWave || wave.isBuilding)
    }

    private var assistantCard: some View {
        Button {
            showAssistant = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 22))
                    .foregroundColor(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ассистент")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                    Text("«Включи…», плейлист по описанию, поиск по тексту — бесплатно и без лимитов")
                        .font(.secondary())
                        .foregroundColor(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(16)
            .glassCard(radius: Metrics.cornerL)
            .padding(.horizontal, Metrics.hPadding)
        }
        .buttonStyle(.plain)
    }

    private var mixesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Миксы")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(mixes) { mix in
                        Button {
                            selectedMix = mix
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: Metrics.cornerM, style: .continuous)
                                    .fill(Self.mixGradient(id: mix.id))
                                    .frame(width: 150, height: 150)
                                    .overlay(
                                        VStack(alignment: .leading) {
                                            Image(systemName: Self.mixIcon(id: mix.id))
                                                .font(.system(size: 26, weight: .bold))
                                                .foregroundColor(.white.opacity(0.9))
                                            Spacer()
                                            Text(mix.title)
                                                .font(.title(16))
                                                .foregroundColor(.white)
                                        }
                                        .padding(12), alignment: .topLeading
                                    )
                                Text(mix.subtitle)
                                    .font(.caption())
                                    .foregroundColor(Palette.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Metrics.hPadding)
            }
        }
    }

    static func mixGradient(id: String) -> LinearGradient {
        let colors: [Color]
        switch id {
        case "morning": colors = [Color(hex: "#FFB347"), Color(hex: "#FF6B9D")]
        case "focus": colors = [Color(hex: "#4DD8FF"), Color(hex: "#5A7BFF")]
        case "workout": colors = [Color(hex: "#FF4D6D"), Color(hex: "#B66DFF")]
        case "evening": colors = [Color(hex: "#8E5AFF"), Color(hex: "#FF7AC6")]
        case "night": colors = [Color(hex: "#2E3A8C"), Color(hex: "#6D5BD0")]
        default: colors = [Palette.accent, Palette.accentTertiary]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func mixIcon(id: String) -> String {
        switch id {
        case "morning": return "sun.max.fill"
        case "focus": return "scope"
        case "workout": return "bolt.fill"
        case "evening": return "moon.haze.fill"
        case "night": return "moon.stars.fill"
        default: return "sparkles"
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Недавно слушали")
            ForEach(recentTracks.prefix(6)) { track in
                TrackRow(track: track)
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Популярное сейчас")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(chartTracks.prefix(14)) { track in
                        Button {
                            player.play(track, in: chartTracks,
                                        startIndex: chartTracks.firstIndex(where: { $0.id == track.id }) ?? 0)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverImage(url: track.artworkURL, size: 140, radius: Metrics.cornerM)
                                Text(track.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Palette.textPrimary)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption())
                                    .foregroundColor(Palette.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Metrics.hPadding)
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        recentTracks = environment.library.recentPlays(limit: 12)
            .compactMap { environment.library.track(id: $0.trackID) }
            .uniqued()
        if environment.providers.isActive(.deezer) {
            if let deezer = environment.providers.provider(.deezer) {
                chartTracks = (try? await deezer.chartTracks(limit: 20)) ?? []
            }
        }
        let loadedMixes = await wave.dailyMixes()
        withAnimation(.easeOut(duration: 0.3)) {
            mixes = loadedMixes
        }
    }

    private func startWave() async {
        buildingWave = true
        defer { buildingWave = false }
        let tracks = await wave.buildWave(count: 20)
        guard let first = tracks.first else { return }
        player.play(first, in: tracks, startIndex: 0)
    }
}

// MARK: - Mix detail

struct MixDetailSheet: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    let mix: WaveFeedService.Mix

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        RoundedRectangle(cornerRadius: Metrics.cornerM, style: .continuous)
                            .fill(WaveView.mixGradient(id: mix.id))
                            .frame(width: 84, height: 84)
                            .overlay(
                                Image(systemName: WaveView.mixIcon(id: mix.id))
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                            )
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mix.title).font(.title(20)).foregroundColor(Palette.textPrimary)
                            Text(mix.subtitle).font(.secondary()).foregroundColor(Palette.textSecondary)
                            PrimaryButton(title: "Слушать", systemImage: "play.fill") {
                                if let first = mix.tracks.first {
                                    player.play(first, in: mix.tracks, startIndex: 0)
                                }
                                dismiss()
                            }
                            .padding(.top, 4)
                        }
                        .padding(.leading, 4)
                    }
                    .padding(.vertical, 8)
                }
                Section {
                    ForEach(mix.tracks) { track in
                        TrackRow(track: track, contextQueue: mix.tracks)
                    }
                }
            }
            .navigationTitle(mix.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Helpers

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
