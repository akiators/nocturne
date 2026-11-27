import SwiftUI

/// Тексты песен: синхронизированный karaoke-режим, автоперевод,
/// аннотации к строкам (локальные заметки), факты трека из Genius (бесплатный токен).
struct LyricsSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController

    @State private var payload: LyricsPayload?
    @State private var translatedText: String?
    @State private var showTranslated = false
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var annotationEditingLine: LyricLine?
    @State private var annotationText = ""
    @State private var annotations: [Int: String] = [:]
    @State private var geniusFacts: String?

    var body: some View {
        NavigationView {
            Group {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload {
                    content(payload)
                } else {
                    EmptyStateView(icon: "text.quote",
                                   title: "Текст для этого трека не найден",
                                   subtitle: errorMessage ?? "Попробуйте другой трек — база LRCLIB обширная")
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Текст")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismissCompat() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if translatedText != nil {
                        Button(showTranslated ? "Оригинал" : "Перевод") {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showTranslated.toggle()
                            }
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await load() }
        .onAppear {
            annotations = environment.library.annotations(trackKey: player.currentTrack?.id ?? "")
        }
        .sheet(item: $annotationEditingLine) { line in
            annotationEditor(line)
        }
    }

    @Environment(\.dismiss) private var dismissEnv
    private func dismissCompat() { dismissEnv() }

    private func content(_ payload: LyricsPayload) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let facts = geniusFacts {
                        factsCard(facts)
                    }
                    if let synced = payload.synced {
                        syncedLyrics(synced, proxy: proxy)
                    } else if showTranslated, let translated = translatedText {
                        Text(translated)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .lineSpacing(10)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                    } else if let plain = payload.plain {
                        Text(plain)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .lineSpacing(10)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                    }
                    if payload.synced != nil, let translated = translatedText {
                        // Полный перевод ниже оригинала
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Перевод")
                                .font(.title(15))
                                .foregroundColor(Palette.textSecondary)
                            Text(translated)
                                .font(.secondary())
                                .foregroundColor(Palette.textSecondary)
                                .lineSpacing(8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 80)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func syncedLyrics(_ lines: [LyricLine], proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(lines) { line in
                let isActive = LRCParser.activeLineIndex(in: lines, at: player.currentTime) == line.id
                Button {
                    Haptics.selection()
                    player.seek(to: line.time)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(showTranslated && translatedText != nil ? line.text : line.text)
                            .font(.system(size: isActive ? 19 : 17, weight: isActive ? .bold : .regular))
                            .foregroundColor(isActive ? Palette.textPrimary : Palette.textSecondary.opacity(0.75))
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let note = annotations[line.id] {
                            Image(systemName: "note.text")
                                .font(.caption())
                                .foregroundColor(Palette.accent)
                        }
                    }
                    .id(line.id)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        annotationEditingLine = line
                        annotationText = annotations[line.id] ?? ""
                    } label: {
                        Label(annotations[line.id] == nil ? "Добавить заметку" : "Изменить заметку",
                              systemImage: "note.text.badge.plus")
                    }
                    if annotations[line.id] != nil {
                        Button(role: .destructive) {
                            environment.library.setAnnotation(trackKey: player.currentTrack?.id ?? "",
                                                              lineIndex: line.id, note: nil)
                            annotations[line.id] = nil
                        } label: {
                            Label("Удалить заметку", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .onChange(of: player.currentTime) { time in
            if let index = LRCParser.activeLineIndex(in: lines, at: time), lines.indices.contains(index) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(lines[index].id, anchor: .center)
                }
            }
        }
    }

    private func factsCard(_ facts: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "g.circle")
                Text("Genius · о треке")
                    .font(.title(14))
            }
            .foregroundColor(Palette.accent)
            Text(facts)
                .font(.secondary())
                .foregroundColor(Palette.textSecondary)
                .lineSpacing(5)
        }
        .padding(14)
        .glassCard()
        .padding(.horizontal, 24)
    }

    private func annotationEditor(_ line: LyricLine) -> some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("«\(line.text)»")
                    .font(.secondary())
                    .foregroundColor(Palette.textSecondary)
                TextEditor(text: $annotationText)
                    .frame(minHeight: 120)
                    .foregroundColor(Palette.textPrimary)
                    .background(Palette.surface)
                    .cornerRadius(Metrics.cornerM)
                Spacer()
            }
            .padding(Metrics.hPadding)
            .navigationTitle("Заметка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { annotationEditingLine = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        environment.library.setAnnotation(trackKey: player.currentTrack?.id ?? "",
                                                          lineIndex: line.id,
                                                          note: annotationText.trimmed)
                        annotations[line.id] = annotationText.trimmed
                        annotationEditingLine = nil
                        Haptics.success()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Load

    private func load() async {
        guard let track = player.currentTrack else {
            loading = false
            errorMessage = "Ничего не играет."
            return
        }
        loading = true
        defer { loading = false }
        do {
            let result = try await environment.lyrics.lyrics(for: track)
            payload = result
            if let plain = result.plain ?? result.synced?.map(\.text).joined(separator: "\n") {
                if let translated = try? await environment.lyrics.translatedLyrics(for: track, plainText: plain) {
                    translatedText = translated
                }
            }
        } catch {
            payload = nil
            errorMessage = error.localizedDescription
        }
        await loadGenius(track: track)
    }

    private func loadGenius(track: Track) async {
        let genius = GeniusService(store: environment.library, settings: environment.settings)
        guard genius.isConfigured else { return }
        if let hit = try? await genius.search(query: "\(track.artist) \(track.title)").first,
           let facts = try? await genius.songFacts(id: hit.id),
           let description = facts.description, !description.isEmpty {
            geniusFacts = description
        }
    }
}
