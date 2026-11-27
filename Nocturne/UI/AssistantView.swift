import SwiftUI

/// Чат-ассистент (аналог Beyond): локальный интент-движок, без квот и без сервера.
struct AssistantView: View {
    @EnvironmentObject private var assistant: AssistantEngine
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if assistant.messages.isEmpty {
                                EmptyStateView(icon: "sparkles",
                                               title: "Чем помочь с музыкой?",
                                               subtitle: "Управляйте плеером голосом текста: включать треки, собирать плейлисты по описанию, искать по строчке текста, показывать статистику")
                            }
                            ForEach(assistant.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            if assistant.isProcessing {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Ассистент думает…")
                                        .font(.secondary())
                                        .foregroundColor(Palette.textSecondary)
                                }
                                .padding(.horizontal, Metrics.hPadding)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .onChange(of: assistant.messages.count) { _ in
                        if let last = assistant.messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                quickChips

                inputBar
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Ассистент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Очистить") { assistant.messages.removeAll() }
                        .font(.secondary())
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickActions, id: \.self) { action in
                    Button {
                        Task { await assistant.send(action) }
                    } label: {
                        Text(action)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Palette.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Metrics.hPadding)
        }
        .padding(.vertical, 8)
    }

    static let quickActions = [
        "Включи волну",
        "Собери плейлист под вечер пятницы",
        "Включи похожие треки",
        "Расскажи о Земфире",
        "Покажи мою статистику",
        "Поставь на паузу",
        "Включи повтор этой очереди"
    ]

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Спроси ассистента о музыке…", text: $input, onCommit: send)
                .foregroundColor(Palette.textPrimary)
                .autocorrectionDisabled(true)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(input.trimmed.isEmpty ? Palette.textSecondary : Palette.accent)
            }
            .disabled(input.trimmed.isEmpty || assistant.isProcessing)
        }
        .padding(12)
        .background(Palette.surface)
        .cornerRadius(Metrics.cornerM)
        .padding(.horizontal, Metrics.hPadding)
        .padding(.bottom, 10)
    }

    private func send() {
        let text = input.trimmed
        guard !text.isEmpty else { return }
        input = ""
        Task { await assistant.send(text) }
    }
}

struct MessageBubble: View {
    let message: AssistantEngine.Message

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            Text(message.text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(message.role == .user ? .white : Palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cornerM, style: .continuous)
                        .fill(message.role == .user ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.surface))
                )
                .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)
                .padding(.horizontal, Metrics.hPadding)

            if let draft = message.draft {
                DraftCard(draft: draft)
            } else if !message.tracks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(message.tracks.prefix(10)) { track in
                            TrackRow(track: track, contextQueue: message.tracks,
                                     subtitle: track.provider.displayName)
                                .frame(width: 300)
                        }
                    }
                    .padding(.horizontal, Metrics.hPadding)
                }
            }
        }
    }
}

struct DraftCard: View {
    @EnvironmentObject private var assistant: AssistantEngine
    let draft: AssistantEngine.PlaylistDraft
    @State private var saved = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Плейлист «\(draft.name)»")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text("\(draft.tracks.count) треков")
                    .font(.secondary())
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            if saved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Сохранить") {
                    _ = assistant.saveDraft(draft)
                    saved = true
                    Haptics.success()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Palette.accent)
            }
        }
        .padding(14)
        .glassCard()
        .padding(.horizontal, Metrics.hPadding)
    }
}
