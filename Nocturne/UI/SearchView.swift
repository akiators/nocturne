import SwiftUI

/// Единый поиск по всем источникам + поиск трека по строке текста (бесплатный аналог Plus-функции Mimose).
struct SearchView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController

    enum Mode: String, CaseIterable {
        case tracks = "Треки"
        case lyrics = "По тексту"
    }

    @State private var query = ""
    @State private var results: SearchResults?
    @State private var searching = false
    @State private var mode: Mode = .tracks
    @State private var recentSearches: [String] = []
    @State private var lyricHits: [LyricsService.LyricsSearchHit] = []
    @State private var providerErrors: [ProviderID: String] = [:]
    @State private var providerFilter: ProviderID?
    @State private var showRecognition = false

    private let debouncer = Debouncer(delay: 0.4)

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                header
                modePicker
                if query.trimmed.isEmpty {
                    recentList
                } else if mode == .tracks {
                    resultsList
                } else {
                    lyricsResultsList
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showRecognition) {
                RecognitionView()
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            recentSearches = environment.library.recentSearches()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Palette.textSecondary)
                TextField(mode == .lyrics ? "Строчка из песни…" : "Треки, исполнители, альбомы…",
                          text: $query)
                    .foregroundColor(Palette.textPrimary)
                    .autocorrectionDisabled(true)
                    .onChange(of: query) { newValue in
                        debouncer.run { Task { await runSearch(query: newValue) } }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = nil
                        lyricHits = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Palette.textSecondary)
                    }
                } else {
                    Button {
                        Haptics.light()
                        showRecognition = true
                    } label: {
                        Image(systemName: "mic.fill")
                            .foregroundColor(Palette.accent)
                    }
                }
            }
            .padding(12)
            .background(Palette.surface)
            .cornerRadius(Metrics.cornerM)
            .padding(.horizontal, Metrics.hPadding)
            .padding(.top, 8)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { item in
                Button {
                    Haptics.selection()
                    withAnimation(.easeOut(duration: 0.15)) { mode = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(mode == item ? Palette.background : Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(mode == item ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.surface)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.hPadding)
        .padding(.vertical, 10)
    }

    // MARK: - Results (tracks)

    private var resultsList: some View {
        ScrollView {
            if searching {
                skeletonList
            } else if let results, results.tracks.isEmpty {
                EmptyStateView(icon: "music.note", title: "Треки не найдены",
                               subtitle: "Проверьте подключённые источники в настройках")
            } else if let results {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !results.tracks.isEmpty {
                        SectionHeader(title: "Треки", actionTitle: "\(results.tracks.count)") {}
                            .padding(.bottom, 6)
                    }
                    ForEach(filteredTracks(results)) { track in
                        TrackRow(track: track,
                                 contextQueue: filteredTracks(results),
                                 subtitle: track.provider.displayName)
                    }
                    if let errorList = errorSummary {
                        Text(errorList)
                            .font(.caption())
                            .foregroundColor(Palette.textSecondary.opacity(0.7))
                            .padding(.horizontal, Metrics.hPadding)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.bottom, 120)
            }
        }
    }

    private func filteredTracks(_ results: SearchResults) -> [Track] {
        let base = providerFilter == nil ? results.tracks : results.tracks.filter { $0.provider == providerFilter }
        return Array(base.prefix(100))
    }

    private var errorSummary: String? {
        guard !providerErrors.isEmpty else { return nil }
        return providerErrors
            .map { "\($0.key.displayName): \($0.value)" }
            .joined(separator: " · ")
    }

    private var skeletonList: some View {
        VStack(spacing: 14) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: Metrics.cornerS)
                        .fill(Palette.surface)
                        .frame(width: Metrics.coverRow, height: Metrics.coverRow)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Palette.surface)
                            .frame(height: 12)
                            .frame(maxWidth: 220)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Palette.surface)
                            .frame(height: 10)
                            .frame(maxWidth: 140)
                    }
                    Spacer()
                }
                .padding(.horizontal, Metrics.hPadding)
                .shimmer()
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Lyrics search results

    private var lyricsResultsList: some View {
        ScrollView {
            if searching {
                skeletonList
            } else if lyricHits.isEmpty {
                EmptyStateView(icon: "text.magnifyingglass",
                               title: query.trimmed.isEmpty ? "Введите строчку из песни" : "Ничего не нашлось",
                               subtitle: "Поиск через открытую базу LRCLIB — без лимитов")
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(lyricHits) { hit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(hit.artist) — \(hit.title)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Palette.textPrimary)
                            if let track = hit.track {
                                TrackRow(track: track, contextQueue: hit.track.map { [$0] } ?? [],
                                         showArtwork: true, subtitle: "Найдено по тексту · \(track.provider.displayName)")
                            } else {
                                Text("Трек не найден в подключённых источниках")
                                    .font(.caption())
                                    .foregroundColor(Palette.textSecondary)
                            }
                        }
                        .padding(.horizontal, Metrics.hPadding)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
    }

    private var recentList: some View {
        ScrollView {
            if recentSearches.isEmpty {
                EmptyStateView(icon: "magnifyingglass",
                               title: "Ищи как думаешь",
                               subtitle: "Каждый поиск открывает новую волну")
                    .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Недавние запросы",
                                  actionTitle: "Очистить") {
                        environment.library.clearRecentSearches()
                        recentSearches = []
                    }
                    ForEach(recentSearches, id: \.self) { item in
                        Button {
                            query = item
                            Task { await runSearch(query: item) }
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(Palette.textSecondary)
                                Text(item)
                                    .foregroundColor(Palette.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, Metrics.hPadding)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Search execution

    private func runSearch(query: String) async {
        let q = query.trimmed
        guard !q.isEmpty else {
            results = nil
            lyricHits = []
            return
        }
        searching = true
        defer { searching = false }

        if mode == .tracks {
            let (combined, outcomes) = await environment.search.unifiedSearch(q, limit: 30)
            var errors: [ProviderID: String] = [:]
            for outcome in outcomes {
                if case .failure(let error) = outcome.result {
                    errors[outcome.providerID] = error.localizedDescription
                }
            }
            providerErrors = errors
            results = combined
            environment.library.pushRecentSearch(q)
        } else {
            lyricHits = await environment.lyrics.searchByLyrics(q)
        }
        recentSearches = environment.library.recentSearches()
    }
}
