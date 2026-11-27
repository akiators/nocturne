import SwiftUI

/// Экран распознавания музыки: микрофон с пульсацией, результат,
/// история последних находок (персистентная, в kv основного хранилища).
struct RecognitionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    @StateObject private var service = RecognitionService()

    @State private var pulse = false
    @State private var history: [RecognitionService.RecognitionResult] = []
    private static let historyKey = "recognition_history"

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                micButton
                statusText

                if let match = service.match {
                    resultCard(match)
                }

                if !history.isEmpty {
                    historySection
                }
                Spacer()
            }
            .padding(.top, 24)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Распознать музыку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        service.stop()
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { loadHistory() }
        .onReceive(service.$match) { newValue in
            guard let newValue else { return }
            history.insert(newValue, at: 0)
            if history.count > 10 { history = Array(history.prefix(10)) }
            saveHistory()
        }
        .onDisappear { service.stop() }
    }

    private var micButton: some View {
        Button {
            Haptics.medium()
            if service.isListening {
                service.stop()
            } else {
                service.start()
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        } label: {
            ZStack {
                if service.isListening {
                    Circle()
                        .stroke(Palette.accent.opacity(0.35), lineWidth: 2)
                        .frame(width: pulse ? 150 : 110, height: pulse ? 150 : 110)
                    Circle()
                        .stroke(Palette.accent.opacity(0.2), lineWidth: 2)
                        .frame(width: pulse ? 180 : 120, height: pulse ? 180 : 120)
                }
                Circle()
                    .fill(Palette.waveGradient)
                    .frame(width: 96, height: 96)
                Image(systemName: service.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var statusText: some View {
        VStack(spacing: 6) {
            Text(service.isListening ? "Слушаем музыку рядом…" : "Нажмите и поднесите телефон к источнику")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Palette.textPrimary)
            if let error = service.errorText {
                Text(error)
                    .font(.secondary())
                    .foregroundColor(Palette.accentSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
    }

    private func resultCard(_ match: RecognitionService.RecognitionResult) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                CoverImage(url: match.artworkURL, size: 88, radius: Metrics.cornerM)
                VStack(alignment: .leading, spacing: 4) {
                    Text(match.title)
                        .font(.title(17))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(2)
                    Text(match.artist)
                        .font(.secondary())
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(14)
            .glassCard(radius: Metrics.cornerL)
            .padding(.horizontal, Metrics.hPadding)

            PrimaryButton(title: "Найти и играть", systemImage: "play.fill") {
                Task { await play(match) }
            }
            .padding(.horizontal, Metrics.hPadding)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Последние находки")
            ForEach(history.prefix(5)) { item in
                TrackRow(track: Track(provider: .appleMusic,
                                      externalID: item.appleMusicID ?? item.title,
                                      title: item.title,
                                      artist: item.artist,
                                      artworkURL: item.artworkURL),
                         subtitle: "Распознано",
                         onPlay: { Task { await play(item) } })
            }
        }
    }

    // MARK: - Actions

    private func play(_ match: RecognitionService.RecognitionResult) async {
        let (results, _) = await environment.search.unifiedSearch("\(match.artist) \(match.title)", limit: 10)
        guard let track = results.tracks.first else {
            if let appleID = match.appleMusicID,
               let url = URL(string: "https://music.apple.com/lookup?isSong=\(appleID)") {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            }
            return
        }
        player.play(track, in: results.tracks,
                    startIndex: results.tracks.firstIndex(where: { $0.id == track.id }) ?? 0)
        dismiss()
    }

    private func loadHistory() {
        guard let json = environment.library.kvString(Self.historyKey),
              let data = json.data(using: .utf8),
              let items = try? JSONDecoder.standard.decode([RecognitionService.RecognitionResult].self, from: data) else { return }
        history = items
    }

    private func saveHistory() {
        if let data = try? JSONEncoder.pretty.encode(history),
           let json = String(data: data, encoding: .utf8) {
            environment.library.kvSet(Self.historyKey, json)
        }
    }
}
