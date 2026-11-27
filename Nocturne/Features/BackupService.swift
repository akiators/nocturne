import Foundation

/// Экспорт и восстановление всех пользовательских данных одним JSON-файлом:
/// библиотека, лайки/дизлайки, плейлисты, история, пресеты EQ, тексты-кэш.
final class BackupService {
    struct Backup: Codable {
        var version: Int = 1
        var createdAt: Date
        var tracks: [Track]
        var favorites: [String]
        var dislikes: [String]
        var playlists: [PlaylistBackup]
        var plays: [PlayBackup]
        var eqPresets: [EQPreset]
    }

    struct PlaylistBackup: Codable {
        var id: String
        var name: String
        var trackIDs: [String]
        var createdAt: Date
    }

    struct PlayBackup: Codable {
        var trackID: String
        var playedAt: Date
        var seconds: TimeInterval
        var completed: Bool
    }

    private let store: LibraryStore
    private let settings: SettingsStore

    init(store: LibraryStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    // MARK: - Export

    func exportToFile() throws -> URL {
        let backup = buildBackup()
        let data = try JSONEncoder.pretty.encode(backup)
        let dir = Self.exportsDirectory
        let name = "nocturne-backup-\(ISO8601DateFormatter().string(from: backup.createdAt).replacingOccurrences(of: ":", with: "-")).json"
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static var exportsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func buildBackup() -> Backup {
        var playlists: [PlaylistBackup] = []
        for playlist in store.playlists() {
            playlists.append(PlaylistBackup(id: playlist.id,
                                            name: playlist.name,
                                            trackIDs: store.playlistTracks(id: playlist.id).map(\.id),
                                            createdAt: playlist.createdAt))
        }
        let plays = store.recentPlays(limit: 5000).map {
            PlayBackup(trackID: $0.trackID, playedAt: $0.playedAt,
                       seconds: $0.secondsPlayed, completed: $0.completed)
        }
        return Backup(createdAt: Date(),
                      tracks: store.allTracks(),
                      favorites: Array(store.favoriteIDs()),
                      dislikes: Array(store.dislikedIDs()),
                      playlists: playlists,
                      plays: plays,
                      eqPresets: store.eqPresets(trackKey: nil))
    }

    // MARK: - Import (merge)

    func restore(from url: URL) throws -> Int {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let backup = try JSONDecoder.standard.decode(Backup.self, from: data)

        store.upsertTracks(backup.tracks)
        for id in backup.favorites { store.setFavorite(id, true) }
        for id in backup.dislikes { store.setDislike(id, true) }
        for preset in backup.eqPresets { store.saveEQPreset(preset) }
        for playlist in backup.playlists {
            let existing = store.playlists().first { $0.id == playlist.id }
            let targetID: String
            if let existing {
                targetID = existing.id
            } else {
                let created = store.createPlaylist(name: playlist.name)
                targetID = created.id
            }
            for trackID in playlist.trackIDs {
                store.addTrack(playlistID: targetID, trackID: trackID)
            }
        }
        for play in backup.plays {
            _ = store.addPlay(trackID: play.trackID, seconds: play.seconds, completed: play.completed)
        }
        return backup.tracks.count
    }
}
