import SwiftUI

/// Полноэкранный плеер в духе Mimose: крупная обложка на волновом фоне,
/// компактные контролы, вторичные панели (тексты, очередь, EQ, скорость, таймер сна).
struct PlayerFullView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    @State private var activeSheet: Sheet? = nil

    enum Sheet: String, Identifiable {
        case queue, lyrics, equalizer, settings
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            WaveBackground(intensity: 0.9)

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)

                Spacer(minLength: 8)

                cover
                    .padding(.horizontal, 34)

                Spacer(minLength: 8)

                titleBlock
                    .padding(.horizontal, 30)

                progressBlock
                    .padding(.horizontal, 30)
                    .padding(.top, 6)

                controlsBlock
                    .padding(.horizontal, 30)
                    .padding(.top, 14)

                secondaryControls
                    .padding(.top, 16)

                Spacer(minLength: 12)
            }
            .padding(.bottom, 20)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .queue: QueueSheet()
            case .lyrics: LyricsSheet()
            case .equalizer: EqualizerSheet()
            case .settings: PlayerSettingsSheet()
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("Играет")
                    .font(.caption())
                    .foregroundColor(Palette.textSecondary)
                if player.currentTrack != nil {
                    Text(player.currentTrack?.provider.displayName ?? "")
                        .font(.caption())
                        .foregroundColor(Palette.textPrimary.opacity(0.8))
                }
            }
            Spacer()
            Button {
                Task {
                    guard let track = player.currentTrack else { return }
                    let isFav = environment.library.isFavorite(track.id)
                    environment.library.setFavorite(track.id, !isFav)
                    Haptics.success()
                }
            } label: {
                Image(systemName: heartIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(heartIcon.contains("fill") ? Palette.accentSecondary : Palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
    }

    private var heartIcon: String {
        guard let track = player.currentTrack else { return "heart" }
        return environment.library.isFavorite(track.id) ? "heart.fill" : "heart"
    }

    private var cover: some View {
        ZStack {
            if let track = player.currentTrack {
                CoverImage(url: track.artworkURL,
                           size: UIScreen.main.bounds.width - 68,
                           radius: Metrics.cornerL)
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            } else {
                RoundedRectangle(cornerRadius: Metrics.cornerL)
                    .fill(Palette.surface)
                    .frame(width: UIScreen.main.bounds.width - 68,
                           height: UIScreen.main.bounds.width - 68)
            }
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.title ?? "Ничего не играет")
                    .font(.title(21))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                Text(player.currentTrack?.artist ?? "Выберите трек в волне или поиске")
                    .font(.body())
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let handoff = player.currentTrack.flatMap({ environment.providers.handoffURL(for: $0) }),
               player.currentTrack?.streamURL == nil || player.currentTrack?.isPreview == true {
                Button {
                    UIApplication.shared.open(handoff)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 17))
                        .foregroundColor(Palette.textSecondary)
                }
            }
        }
    }

    private var progressBlock: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.textSecondary.opacity(0.25))
                        .frame(height: 4)
                    Capsule().fill(Palette.textPrimary)
                        .frame(width: geo.size.width * progressFraction, height: 4)
                    Circle()
                        .fill(Palette.textPrimary)
                        .frame(width: 12, height: 12)
                        .offset(x: geo.size.width * progressFraction - 6)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            if let duration = player.currentTrack?.duration, duration > 0 {
                                player.currentTime = fraction * duration
                            }
                        }
                        .onEnded { value in
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            if let duration = player.currentTrack?.duration, duration > 0 {
                                player.seek(to: fraction * duration)
                            }
                        }
                )
            }
            .frame(height: 14)
            HStack {
                Text(player.currentTime.clockString)
                Spacer()
                Text((player.currentTrack?.duration ?? 0).clockString)
            }
            .font(.numeric())
            .foregroundColor(Palette.textSecondary)
        }
    }

    private var progressFraction: CGFloat {
        guard let duration = player.currentTrack?.duration, duration > 0 else { return 0 }
        return CGFloat(min(1, player.currentTime / duration))
    }

    private var controlsBlock: some View {
        HStack(spacing: 0) {
            controlButton(player.shuffleOn ? "shuffle" : "shuffle",
                          filled: player.shuffleOn, size: 19) {
                player.shuffleOn.toggle()
                Haptics.selection()
            }
            .frame(maxWidth: .infinity)

            controlButton("backward.fill", filled: true, size: 26) {
                player.previous()
                Haptics.light()
            }
            .frame(maxWidth: .infinity)

            playPauseButton
                .frame(maxWidth: .infinity)

            controlButton("forward.fill", filled: true, size: 26) {
                player.next()
                Haptics.light()
            }
            .frame(maxWidth: .infinity)

            controlButton(repeatIcon, filled: player.repeatMode != .off, size: 19) {
                switch player.repeatMode {
                case .off: player.repeatMode = .all
                case .all: player.repeatMode = .one
                case .one: player.repeatMode = .off
                }
                Haptics.selection()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var playPauseButton: some View {
        Button {
            Haptics.medium()
            player.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(Palette.textPrimary)
                    .frame(width: 68, height: 68)
                if player.isLoadingTrack {
                    ProgressView().tint(Palette.background)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Palette.background)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(player.currentTrack == nil)
    }

    private func controlButton(_ icon: String, filled: Bool, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(filled ? Palette.textPrimary : Palette.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var secondaryControls: some View {
        HStack(spacing: 8) {
            secondaryButton(icon: "text.bubble", label: "Текст") { activeSheet = .lyrics }
            secondaryButton(icon: "list.number", label: "Очередь") { activeSheet = .queue }
            secondaryButton(icon: "slider.horizontal.3", label: "Эквалайзер") { activeSheet = .equalizer }
            secondaryButton(icon: "timer", label: "Скорость") { activeSheet = .settings }
        }
        .padding(.horizontal, 24)
    }

    private func secondaryButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(label)
                    .font(.caption())
            }
            .foregroundColor(Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerM, style: .continuous)
                    .fill(.thinMaterial)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Queue sheet

struct QueueSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if let current = player.currentTrack, player.queue.indices.contains(player.queueIndex) {
                    Section("Текущий трек") {
                        TrackRow(track: current, contextQueue: player.queue, showArtwork: false)
                            .listRowBackground(Color.clear)
                    }
                }
                Section("Далее") {
                    let upcoming = Array(player.queue.indices).compactMap { index -> Track? in
                        guard index > player.queueIndex else { return nil }
                        return player.queue[index]
                    }
                    if upcoming.isEmpty {
                        Text("Очередь пуста — My Wave доберёт треки автоматически")
                            .foregroundColor(Palette.textSecondary)
                            .font(.secondary())
                    }
                    ForEach(Array(upcoming.enumerated()), id: \.element.id) { pairIndex, track in
                        TrackRow(track: track, contextQueue: player.queue,
                                 showArtwork: true,
                                 subtitle: "\(player.queueIndex + pairIndex + 1) · \(track.provider.displayName)")
                            .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        // Смещаем: удаляем реальные индексы из очереди.
                        let realIndices = offsets.map { player.queueIndex + 1 + $0 }.reversed()
                        for index in realIndices where player.queue.indices.contains(index) {
                            player.removeQueuedTrack(at: index)
                        }
                    }
                }
            }
            .scrollContentBackgroundCompat()
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Player settings sheet (speed / crossfade / sleep timer)

struct PlayerSettingsSheet: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Скорость воспроизведения") {
                    HStack {
                        Text("0.5×").font(.numeric())
                        Slider(value: $player.speed, in: 0.5...2.0, step: 0.05)
                            .tint(Palette.accent)
                        Text("2×").font(.numeric())
                    }
                    Text(String(format: "Темп: %.2f×", player.speed))
                        .font(.secondary())
                        .foregroundColor(Palette.textSecondary)
                }
                Section("Плавный переход (crossfade)") {
                    HStack {
                        Text("Выкл").font(.numeric())
                        Slider(value: $settings.crossfadeSeconds, in: 0...12, step: 1)
                            .tint(Palette.accent)
                        Text("12 с").font(.numeric())
                    }
                    Text(settings.crossfadeSeconds < 1 ? "Переходы отключены" :
                            "Переход \(Int(settings.crossfadeSeconds)) сек")
                        .font(.secondary())
                        .foregroundColor(Palette.textSecondary)
                }
                Section("Таймер сна") {
                    Button {
                        player.startSleepTimerEndOfTrack()
                        dismiss()
                    } label: {
                        Label("До конца текущего трека", systemImage: "music.quarternote.3")
                    }
                    Button {
                        player.startSleepTimer(minutes: settings.sleepTimerMinutes)
                        dismiss()
                    } label: {
                        Label("\(settings.sleepTimerMinutes) минут", systemImage: "timer")
                    }
                    if player.isSleepTimerOn {
                        Button(role: .destructive) {
                            player.stopSleepTimer()
                        } label: {
                            Label("Выключить таймер", systemImage: "xmark.circle")
                        }
                    }
                    HStack {
                        Text("Минут").font(.secondary())
                        Slider(value: Binding(
                            get: { Double(settings.sleepTimerMinutes) },
                            set: { settings.sleepTimerMinutes = Int($0) }
                        ), in: 5...120, step: 5)
                            .tint(Palette.accent)
                    }
                }
            }
            .navigationTitle("Плеер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
