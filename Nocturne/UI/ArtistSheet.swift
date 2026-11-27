import SwiftUI

/// Карточка исполнителя: биография (Genius, кэш 30 дней) + популярные треки.
struct ArtistSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    let artistName: String

    @State private var bio: String?
    @State private var topTracks: [Track] = []
    @State private var loading = true

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    bioSection
                    if !topTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Популярное")
                            ForEach(topTracks) { track in
                                TrackRow(track: track, contextQueue: topTracks)
                            }
                        }
                    }
                    if !loading && bio == nil {
                        Text("Биография недоступна: добавьте бесплатный токен Genius в «Настройки → Токен Genius».")
                            .font(.caption())
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, Metrics.hPadding)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(WaveBackground(intensity: 0.4))
            .navigationTitle(artistName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Palette.waveGradient)
                Text(artistName.initials)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("Исполнитель")
                    .font(.caption())
                    .foregroundColor(Palette.textSecondary)
                Text(artistName)
                    .font(.title(20))
                    .foregroundColor(Palette.textPrimary)
                PrimaryButton(title: "Радио по артисту", systemImage: "dot.radiowaves.left.and.right") {
                    Task { await startRadio() }
                }
                .frame(width: 220)
            }
        }
        .padding(.horizontal, Metrics.hPadding)
    }

    @ViewBuilder
    private var bioSection: some View {
        if loading {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.surface)
                        .frame(height: 12)
                        .shimmer()
                }
            }
            .padding(.horizontal, Metrics.hPadding)
        } else if let bio {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "g.circle")
                    Text("Genius · биография")
                        .font(.title(14))
                }
                .foregroundColor(Palette.accent)
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundColor(Palette.textSecondary)
                    .lineSpacing(6)
            }
            .padding(14)
            .glassCard()
            .padding(.horizontal, Metrics.hPadding)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true
        async let bioTask: String? = environment.genius.artistBio(name: artistName)
        let (results, _) = await environment.search.unifiedSearch(artistName, limit: 10)
        topTracks = results.tracks
        bio = await bioTask
        loading = false
    }

    private func startRadio() async {
        let probe = Track(provider: .deezer, externalID: "radio-\(artistName)", title: artistName, artist: artistName)
        let radio = await environment.wave.radio(for: probe, count: 15)
        guard let first = radio.first else { return }
        player.play(first, in: radio, startIndex: 0)
        dismiss()
    }
}
