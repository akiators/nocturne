import SwiftUI

/// Эквалайзер: 10 полос, встроенные и пользовательские пресеты,
/// per-track пресеты (в Mimose это Plus — у нас бесплатно), кривая сохраняется.
struct EqualizerSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var gains: [Float] = Array(repeating: 0, count: 10)
    @State private var userPresets: [EQPreset] = []
    @State private var selectedPresetID: String = "builtin_flat"
    @State private var showSave = false
    @State private var presetName = ""
    @State private var perTrack = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if player.isMusicKitPlayback {
                        Text("Текущий трек играет Apple Music — эквалайзер применяется только к нашим источникам (локальные файлы, preview).")
                            .font(.caption())
                            .foregroundColor(Palette.accent)
                            .padding(.horizontal, Metrics.hPadding)
                    }
                    enabledToggle
                    presetPicker
                    bandSliders
                    saveControls
                }
                .padding(.vertical, 12)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Эквалайзер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: load)
        .alert("Сохранить пресет", isPresented: $showSave) {
            TextField("Название", text: $presetName)
            Button("Сохранить") { savePreset() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var enabledToggle: some View {
        Toggle(isOn: Binding(
            get: { settings.eqEnabled },
            set: { player.setEQEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Включить эквалайзер")
                    .foregroundColor(Palette.textPrimary)
                Text("Кривая применяется в реальном времени")
                    .font(.caption())
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .tint(Palette.accent)
        .padding(.horizontal, Metrics.hPadding)
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Пресет")
                .font(.title(16))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, Metrics.hPadding)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BuiltInEQPresets.all, id: \.id) { preset in
                        presetChip(preset)
                    }
                    ForEach(userPresets, id: \.id) { preset in
                        presetChip(preset, removable: true)
                    }
                }
                .padding(.horizontal, Metrics.hPadding)
            }
        }
    }

    private func presetChip(_ preset: EQPreset, removable: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(preset.name)
                .font(.system(size: 13, weight: .semibold))
            if removable {
                Button {
                    environment.library.deleteEQPreset(id: preset.id)
                    userPresets = environment.library.eqPresets(trackKey: nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
            }
        }
        .foregroundColor(selectedPresetID == preset.id ? Palette.background : Palette.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(selectedPresetID == preset.id
                           ? AnyShapeStyle(Palette.accent)
                           : AnyShapeStyle(Palette.surface))
        )
        .onTapGesture {
            Haptics.selection()
            selectedPresetID = preset.id
            gains = preset.gains
            player.applyEQPreset(preset)
        }
    }

    private var bandSliders: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Полосы")
                .font(.title(16))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, Metrics.hPadding)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<10, id: \.self) { index in
                    VStack(spacing: 6) {
                        Text("\(Int(gains[index]))")
                            .font(.numeric(10))
                            .foregroundColor(Palette.textSecondary)
                            .frame(height: 12)
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.accent)
                                    .frame(height: max(4, geo.size.height * normalizedGain(index)))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Palette.textSecondary.opacity(0.2))
                            }
                        }
                        .frame(height: 140)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let normalized = 1 - max(0, min(1, value.location.y / 140))
                                    gains[index] = Float((normalized * 24) - 12)
                                    selectedPresetID = ""
                                    player.setEQGains(gains)
                                }
                        )
                        Text(Self.bandLabel(index))
                            .font(.numeric(9))
                            .foregroundColor(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Metrics.hPadding)
        }
    }

    private func normalizedGain(_ index: Int) -> CGFloat {
        CGFloat((gains[index] + 12) / 24)
    }

    static func bandLabel(_ index: Int) -> String {
        let freq = EQPreset.bandFrequencies[index]
        return freq >= 1000 ? "\(Int(freq / 1000))k" : "\(Int(freq))"
    }

    private var saveControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $perTrack) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Сохранить для этого трека")
                        .foregroundColor(Palette.textPrimary)
                    Text("У других треков останется свой звук (per-track пресеты)")
                        .font(.caption())
                        .foregroundColor(Palette.textSecondary)
                }
            }
            .tint(Palette.accent)

            PrimaryButton(title: "Сохранить пресет", systemImage: "square.and.arrow.down") {
                showSave = true
            }

            if let track = player.currentTrack, !storeTrackPresets(track).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Пресеты трека «\(track.title)»")
                        .font(.title(14))
                        .foregroundColor(Palette.textSecondary)
                    ForEach(storeTrackPresets(track), id: \.id) { preset in
                        Button {
                            gains = preset.gains
                            player.applyEQPreset(preset)
                        } label: {
                            Text(preset.name)
                                .font(.secondary())
                                .foregroundColor(Palette.accent)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.hPadding)
    }

    private func storeTrackPresets(_ track: Track) -> [EQPreset] {
        environment.library.eqPresets(trackKey: track.id)
    }

    // MARK: - Actions

    private func load() {
        userPresets = environment.library.eqPresets(trackKey: nil)
        if let track = player.currentTrack, settings.useTrackEQPresets {
            let perTrackPresets = environment.library.eqPresets(trackKey: track.id)
            if let preset = perTrackPresets.first {
                gains = preset.gains
                selectedPresetID = preset.id
                return
            }
        }
        if let id = settings.selectedPresetID,
           let preset = BuiltInEQPresets.all.first(where: { $0.id == id }) ?? userPresets.first(where: { $0.id == id }) {
            gains = preset.gains
            selectedPresetID = preset.id
        }
    }

    private func savePreset() {
        let name = presetName.trimmed
        guard !name.isEmpty else { return }
        let trackKey = perTrack ? player.currentTrack?.id : nil
        let preset = EQPreset(id: UUID().uuidString, name: name, gains: gains, trackKey: trackKey)
        environment.library.saveEQPreset(preset)
        userPresets = environment.library.eqPresets(trackKey: nil)
        selectedPresetID = preset.id
        presetName = ""
        perTrack = false
        Haptics.success()
    }
}
