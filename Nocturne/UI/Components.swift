import SwiftUI
import AVFoundation

// MARK: - Track row (универсальная строка трека)

struct TrackRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager

    let track: Track
    var contextQueue: [Track] = []
    var showArtwork: Bool = true
    var subtitle: String? = nil

    @State private var showAddToPlaylist = false
    @State private var showArtistSheet = false
    @State private var isFavorite = false

    var onPlay: (() -> Void)? = nil

    var body: some View {
        Button {
            Haptics.light()
            if let onPlay {
                onPlay()
            } else {
                player.play(track, in: contextQueue.isEmpty ? [track] : contextQueue,
                            startIndex: contextQueue.isEmpty ? 0 : max(0, contextQueue.firstIndex(where: { $0.id == track.id }) ?? 0))
            }
        } label: {
            HStack(spacing: 12) {
                if showArtwork {
                    CoverImage(url: track.artworkURL, size: Metrics.coverRow)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(rowTitleColor)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(subtitle ?? track.artist)
                            .font(.secondary())
                            .foregroundColor(Palette.textSecondary)
                            .lineLimit(1)
                        if track.isPreview {
                            Text("30 сек")
                                .font(.caption())
                                .foregroundColor(Palette.textSecondary.opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Palette.surfaceElevated)
                                .cornerRadius(4)
                        }
                        if track.explicit {
                            Text("E")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Palette.textSecondary)
                                .frame(width: 13, height: 13)
                                .background(Palette.textSecondary.opacity(0.2))
                                .cornerRadius(3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if downloads.activeDownloads.contains(track.id) {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Menu {
                        trackMenu
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Palette.textSecondary)
                            .frame(width: 34, height: 40)
                    }
                }
            }
            .padding(.horizontal, Metrics.hPadding - 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: track.id) {
            isFavorite = environment.library.isFavorite(track.id)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(track: track)
        }
        .sheet(isPresented: $showArtistSheet) {
            ArtistSheet(artistName: track.artist)
        }
    }

    private var rowTitleColor: Color {
        if player.currentTrack?.id == track.id { return Palette.accent }
        if environment.library.isDisliked(track.id) { return Palette.textSecondary }
        return Palette.textPrimary
    }

    @ViewBuilder
    private var trackMenu: some View {
        Button {
            let newValue = !isFavorite
            environment.library.setFavorite(track.id, newValue)
            isFavorite = newValue
            environment.library.bumpArtist(track.artist, delta: newValue ? 0.5 : -0.3)
            Haptics.success()
        } label: {
            Label(isFavorite ? "Убрать из любимых" : "В любимые",
                  systemImage: isFavorite ? "heart.slash" : "heart")
        }

        Button {
            environment.library.setDislike(track.id, true)
            Haptics.medium()
        } label: {
            Label("Не рекомендовать (дизлайк)", systemImage: "hand.thumbsdown")
        }

        Button {
            showAddToPlaylist = true
        } label: {
            Label("Добавить в плейлист", systemImage: "music.note.badge.plus")
        }

        Button {
            Task {
                let radio = await environment.wave.radio(for: track, count: 15)
                if let first = radio.first {
                    player.play(first, in: radio, startIndex: 0)
                }
            }
        } label: {
            Label("Радио по треку", systemImage: "dot.radiowaves.left.and.right")
        }

        Button {
            showArtistSheet = true
        } label: {
            Label("Об исполнителе", systemImage: "person.crop.circle")
        }

        if downloads.canDownload(track) {
            Button {
                Task { await downloads.download(track) }
            } label: {
                Label(downloads.isDownloaded(track) ? "Перекачать" : "Скачать",
                      systemImage: "arrow.down.circle")
            }
        } else if downloads.isDownloaded(track) {
            Button {
                downloads.removeDownload(track.id)
            } label: {
                Label("Удалить загрузку", systemImage: "trash")
            }
        }

        if let handoff = environment.providers.handoffURL(for: track) {
            Button {
                UIApplication.shared.open(handoff)
            } label: {
                Label("Открыть в \(track.provider.displayName)", systemImage: "arrow.up.right.square")
            }
        }
    }
}

// MARK: - Add to playlist sheet

struct AddToPlaylistSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let track: Track
    @State private var playlists: [Playlist] = []
    @State private var newPlaylistName = ""
    @State private var addedTo: Set<String> = []

    var body: some View {
        NavigationView {
            List {
                Section("Создать") {
                    HStack {
                        TextField("Название плейлиста", text: $newPlaylistName)
                            .foregroundColor(Palette.textPrimary)
                        Button("Создать и добавить") {
                            let playlist = environment.library.createPlaylist(name: newPlaylistName.trimmed)
                            environment.library.upsertTracks([track])
                            environment.library.addTrack(playlistID: playlist.id, trackID: track.id)
                            addedTo.insert(playlist.id)
                            newPlaylistName = ""
                            Haptics.success()
                        }
                        .disabled(newPlaylistName.trimmed.isEmpty)
                        .font(.secondary())
                        .foregroundColor(Palette.accent)
                    }
                }
                Section("Мои плейлисты") {
                    if playlists.isEmpty {
                        Text("Пока нет плейлистов")
                            .foregroundColor(Palette.textSecondary)
                    }
                    ForEach(playlists) { playlist in
                        Button {
                            environment.library.upsertTracks([track])
                            environment.library.addTrack(playlistID: playlist.id, trackID: track.id)
                            addedTo.insert(playlist.id)
                            Haptics.success()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(playlist.name)
                                        .foregroundColor(Palette.textPrimary)
                                    Text("\(playlist.trackCount) треков")
                                        .font(.secondary())
                                        .foregroundColor(Palette.textSecondary)
                                }
                                Spacer()
                                if addedTo.contains(playlist.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Palette.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("В плейлист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .onAppear { playlists = environment.library.playlists() }
    }
}

// MARK: - Inline progress bar

struct ProgressBar: View {
    var value: Double // 0...1
    var color: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.textSecondary.opacity(0.25))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .frame(height: 3)
    }
}
