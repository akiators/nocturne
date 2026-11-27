import SwiftUI
import UniformTypeIdentifiers

/// Библиотека: любимые, загрузки, история, плейлисты (создание, импорт файлов и ссылок).
struct LibraryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager

    @State private var playlists: [Playlist] = []
    @State private var favorites: [Track] = []
    @State private var downloadedTracks: [Track] = []
    @State private var recentTracks: [Track] = []
    @State private var showCreate = false
    @State private var newPlaylistName = ""
    @State private var showFileImporter = false
    @State private var showAudioImporter = false
    @State private var showURLImport = false
    @State private var importURLText = ""
    @State private var importStatus: String?
    @State private var importError: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    quickLinks
                    playlistsSection
                }
                .padding(.vertical, 12)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Моя музыка")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showCreate = true
                        } label: {
                            Label("Создать плейлист", systemImage: "plus")
                        }
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Импорт M3U/CSV/JSON", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showURLImport = true
                        } label: {
                            Label("Импорт по ссылке (Deezer/Spotify)", systemImage: "link")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .nocturneImportFiles)) { _ in
                showAudioImporter = true
            }
            .sheet(isPresented: $showCreate) { createPlaylistSheet }
            .sheet(isPresented: $showURLImport) { urlImportSheet }
            .fileImporter(isPresented: $showAudioImporter,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { result in
                let urls = (try? result.get()) ?? []
                do {
                    let imported = try (environment.providers.provider(.local) as? LocalFilesProvider)?
                        .importFiles(at: urls) ?? []
                    importStatus = imported.isEmpty ? "Файлы не импортированы." : "Добавлено треков: \(imported.count)."
                    reload()
                    Haptics.success()
                } catch {
                    importError = "Ошибка импорта файлов: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.plainText, .text, .json, .data],
                          allowsMultipleSelection: false) { result in
                guard let url = (try? result.get())?.first else { return }
                do {
                    let playlist = try environment.importer.importFromFile(url: url)
                    importStatus = "Импорт начат: \(playlist.name). Треки подбираются в источниках."
                    reload()
                } catch {
                    importError = error.localizedDescription
                }
            }
            .overlay(alignment: .bottom) { importToast }
        }
        .navigationViewStyle(.stack)
    }

    private var importToast: some View {
        VStack(spacing: 0) {
            if let importStatus {
                toastView(text: importStatus, color: Palette.accent)
            }
            if let importError {
                toastView(text: importError, color: Palette.accentSecondary)
            }
        }
        .animation(.easeOut(duration: 0.2), value: importStatus)
        .animation(.easeOut(duration: 0.2), value: importError)
    }

    private func toastView(text: String, color: Color) -> some View {
        Text(text)
            .font(.secondary())
            .foregroundColor(Palette.textPrimary)
            .padding(12)
            .glassCard()
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .onAppear {
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    importStatus = nil
                    importError = nil
                }
            }
    }

    private var quickLinks: some View {
        VStack(spacing: 10) {
            quickLink(icon: "heart.fill", title: "Любимые треки", count: favorites.count) {
                TrackListSection(title: "Любимые треки", tracks: favorites, emptyIcon: "heart",
                                 emptyText: "Здесь пока нет любимых треков",
                                 emptySubtitle: "Слушайте музыку и сохраняйте треки сердечком")
            }
            quickLink(icon: "arrow.down.circle.fill", title: "Загрузки", count: downloadedTracks.count) {
                TrackListSection(title: "Загрузки", tracks: downloadedTracks, emptyIcon: "arrow.down.circle",
                                 emptyText: "Нет скачанных треков",
                                 emptySubtitle: "Нажмите «Скачать» в меню трека (фрагменты и локальные файлы)")
            }
            quickLink(icon: "clock.fill", title: "История", count: recentTracks.count) {
                TrackListSection(title: "История", tracks: recentTracks, emptyIcon: "clock",
                                 emptyText: "Вы ещё ничего не слушали")
            }
            NavigationLink {
                StatsView()
            } label: {
                quickLinkRow(icon: "chart.bar.fill", title: "Статистика", systemCount: nil)
            }
            NavigationLink {
                DislikedView()
            } label: {
                quickLinkRow(icon: "hand.thumbsdown.fill", title: "Исключённые из рекомендаций", systemCount: nil)
            }
        }
        .padding(.horizontal, Metrics.hPadding)
    }

    private func quickLink(icon: String, title: String, count: Int,
                           @ViewBuilder destination: () -> some View) -> some View {
        NavigationLink {
            destination()
        } label: {
            quickLinkRow(icon: icon, title: title, systemCount: count > 0 ? "\(count)" : nil)
        }
    }

    private func quickLinkRow(icon: String, title: String, systemCount: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(Palette.accent)
                .frame(width: 30)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            if let systemCount {
                Text(systemCount)
                    .font(.numeric())
                    .foregroundColor(Palette.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Palette.textSecondary)
        }
        .padding(14)
        .glassCard()
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Плейлисты", actionTitle: "Создать") { showCreate = true }
            if playlists.isEmpty {
                EmptyStateView(icon: "music.note.list",
                               title: "Нет созданных плейлистов",
                               subtitle: "Создайте первый кнопкой +")
                    .frame(maxWidth: .infinity)
            }
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistID: playlist.id)
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: Metrics.cornerS, style: .continuous)
                            .fill(Palette.waveGradient)
                            .frame(width: Metrics.coverRow, height: Metrics.coverRow)
                            .overlay(Image(systemName: "music.note")
                                .foregroundColor(.white.opacity(0.8)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Palette.textPrimary)
                            Text("\(playlist.trackCount) треков")
                                .font(.secondary())
                                .foregroundColor(Palette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(Palette.textSecondary)
                    }
                    .padding(.horizontal, Metrics.hPadding - 4)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var createPlaylistSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Название вашего плейлиста", text: $newPlaylistName)
                    .styledField()
                    .padding(.horizontal, Metrics.hPadding)
                PrimaryButton(title: "Создать") {
                    let name = newPlaylistName.trimmed
                    guard !name.isEmpty else { return }
                    _ = environment.library.createPlaylist(name: name)
                    newPlaylistName = ""
                    showCreate = false
                    reload()
                    Haptics.success()
                }
                .padding(.horizontal, Metrics.hPadding)
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Новый плейлист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showCreate = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var urlImportSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Вставьте ссылку на плейлист…", text: $importURLText)
                    .styledField()
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                Text("Поддерживаются плейлисты Deezer (без аккаунта) и Spotify (нужен настроенный Client ID).")
                    .font(.caption())
                    .foregroundColor(Palette.textSecondary)
                PrimaryButton(title: "Импортировать", systemImage: "tray.and.arrow.down") {
                    Task { await importFromText() }
                }
                Spacer()
            }
            .padding(Metrics.hPadding)
            .navigationTitle("Импорт плейлиста")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showURLImport = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func importFromText() async {
        let raw = importURLText.trimmed
        guard let url = URL(string: raw), let scheme = url.scheme, scheme.hasPrefix("http") else {
            importError = "Это не похоже на ссылку плейлиста."
            return
        }
        do {
            let playlist = try await environment.importer.importFromURL(url)
            importStatus = "Плейлист «\(playlist.name)» импортирован: \(playlist.trackCount) треков."
            showURLImport = false
            reload()
            Haptics.success()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func reload() {
        playlists = environment.library.playlists()
        favorites = environment.library.favoriteTracks()
        recentTracks = environment.library.recentPlays(limit: 100)
            .compactMap { environment.library.track(id: $0.trackID) }
            .uniqued()
        downloadedTracks = downloads.downloadedKeys
            .compactMap { environment.library.track(id: $0) }
    }
}

// MARK: - Generic track list section

struct TrackListSection: View {
    @EnvironmentObject private var player: PlayerController
    let title: String
    let tracks: [Track]
    let emptyIcon: String
    let emptyText: String
    var emptySubtitle: String? = nil

    var body: some View {
        ScrollView {
            if tracks.isEmpty {
                EmptyStateView(icon: emptyIcon, title: emptyText, subtitle: emptySubtitle)
                    .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    PrimaryButton(title: "Слушать всё", systemImage: "play.fill") {
                        if let first = tracks.first {
                            player.play(first, in: tracks, startIndex: 0)
                        }
                    }
                    .padding(.horizontal, Metrics.hPadding)
                    .padding(.bottom, 10)
                    ForEach(tracks) { track in
                        TrackRow(track: track, contextQueue: tracks)
                    }
                }
                .padding(.vertical, 12)
                .padding(.bottom, 120)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Disliked

struct DislikedView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var disliked: [Track] = []

    var body: some View {
        TrackListSection(title: "Исключённые из рекомендаций",
                         tracks: disliked,
                         emptyIcon: "hand.thumbsdown",
                         emptyText: "Нет треков с дизлайком",
                         emptySubtitle: "Дизлайк убирает трек из My Wave")
            .onAppear {
                disliked = environment.library.dislikedTracks()
            }
    }
}

// MARK: - Playlist detail

struct PlaylistDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController

    let playlistID: String
    @State private var playlistName = ""
    @State private var tracks: [Track] = []
    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                PrimaryButton(title: "Слушать плейлист", systemImage: "play.fill") {
                    if let first = tracks.first {
                        player.play(first, in: tracks, startIndex: 0)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                if tracks.isEmpty {
                    Text("В плейлисте пока нет треков")
                        .foregroundColor(Palette.textSecondary)
                }
                ForEach(tracks) { track in
                    TrackRow(track: track, contextQueue: tracks)
                }
                .onDelete { offsets in
                    for index in offsets {
                        environment.library.removeTrack(playlistID: playlistID, trackID: tracks[index].id)
                    }
                    reload()
                }
                .onMove { source, destination in
                    var ids = tracks.map(\.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    environment.library.reorderPlaylist(id: playlistID, orderedTrackIDs: ids)
                    reload()
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .scrollContentBackgroundCompat()
        .navigationTitle(playlistName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        renameText = playlistName
                        showRename = true
                    } label: {
                        Label("Переименовать", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        environment.library.deletePlaylist(id: playlistID)
                        // Возврат назад произойдёт автоматически, список обновится onAppear.
                    } label: {
                        Label("Удалить плейлист", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .alert("Переименовать плейлист", isPresented: $showRename) {
            TextField("Название", text: $renameText)
            Button("Сохранить") {
                let name = renameText.trimmed
                guard !name.isEmpty else { return }
                environment.library.renamePlaylist(id: playlistID, name: name)
                playlistName = name
            }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear { reload() }
    }

    private func reload() {
        tracks = environment.library.playlistTracks(id: playlistID)
        playlistName = environment.library.playlists().first { $0.id == playlistID }?.name ?? "Плейлист"
    }
}

// iOS 15: .scrollContentBackground(.hidden) появился в iOS 16 — компат-модификатор.
extension View {
    @ViewBuilder
    func scrollContentBackgroundCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
