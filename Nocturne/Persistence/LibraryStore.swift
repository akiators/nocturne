import Foundation

/// Единое локальное хранилище: библиотека, плейлисты, история, кэш текстов,
/// пресеты EQ, загрузки, kv-настройки. Всё на устройстве, без сервера.
final class LibraryStore {
    private let db: SQLiteDatabase

    init(db: SQLiteDatabase) throws {
        self.db = db
        try ensureSchema()
    }

    private func ensureSchema() throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS tracks(
            id TEXT PRIMARY KEY, provider TEXT NOT NULL, external_id TEXT NOT NULL,
            title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT,
            duration REAL, artwork TEXT, stream TEXT, is_preview INTEGER DEFAULT 0,
            year INTEGER, genre TEXT, explicit INTEGER DEFAULT 0, added_at REAL
        );
        CREATE TABLE IF NOT EXISTS favorites(track_id TEXT PRIMARY KEY, added_at REAL);
        CREATE TABLE IF NOT EXISTS dislikes(track_id TEXT PRIMARY KEY, added_at REAL);
        CREATE TABLE IF NOT EXISTS playlists(
            id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at REAL, updated_at REAL
        );
        CREATE TABLE IF NOT EXISTS playlist_tracks(
            playlist_id TEXT NOT NULL, position INTEGER NOT NULL, track_id TEXT NOT NULL,
            PRIMARY KEY(playlist_id, position)
        );
        CREATE TABLE IF NOT EXISTS plays(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id TEXT NOT NULL, played_at REAL NOT NULL,
            seconds_played REAL, completed INTEGER
        );
        CREATE TABLE IF NOT EXISTS lyrics_cache(
            track_key TEXT PRIMARY KEY, synced TEXT, plain TEXT, translated TEXT,
            source TEXT, fetched_at REAL
        );
        CREATE TABLE IF NOT EXISTS annotations(
            track_key TEXT NOT NULL, line_index INTEGER NOT NULL, note TEXT NOT NULL,
            created_at REAL, PRIMARY KEY(track_key, line_index)
        );
        CREATE TABLE IF NOT EXISTS eq_presets(
            id TEXT PRIMARY KEY, name TEXT NOT NULL, gains BLOB,
            track_key TEXT, created_at REAL
        );
        CREATE TABLE IF NOT EXISTS downloads(
            track_key TEXT PRIMARY KEY, file_path TEXT NOT NULL, size INTEGER, created_at REAL
        );
        CREATE TABLE IF NOT EXISTS artist_affinity(
            artist TEXT PRIMARY KEY, score REAL NOT NULL, updated_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_plays_time ON plays(played_at);
        CREATE INDEX IF NOT EXISTS idx_playlist_tracks_pid ON playlist_tracks(playlist_id);
        """)
    }

    // MARK: - Tracks

    func upsertTracks(_ tracks: [Track]) {
        for track in tracks {
            try? db.run(
                "INSERT INTO tracks(id, provider, external_id, title, artist, album, duration, artwork, stream, is_preview, year, genre, explicit, added_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) " +
                "ON CONFLICT(id) DO UPDATE SET title=excluded.title, artist=excluded.artist, album=excluded.album, " +
                "duration=excluded.duration, artwork=excluded.artwork, stream=excluded.stream, is_preview=excluded.is_preview, " +
                "year=excluded.year, genre=excluded.genre, explicit=excluded.explicit",
                { s in
                    s.bindText(1, track.id)
                    s.bindText(2, track.provider.rawValue)
                    s.bindText(3, track.externalID)
                    s.bindText(4, track.title)
                    s.bindText(5, track.artist)
                    s.bindText(6, track.album)
                    s.bindDouble(7, track.duration)
                    s.bindText(8, track.artworkURL?.absoluteString)
                    s.bindText(9, track.streamURL?.absoluteString)
                    s.bindInt(10, track.isPreview ? 1 : 0)
                    s.bindInt(11, Int64(track.year ?? 0))
                    s.bindText(12, track.genre)
                    s.bindInt(13, track.explicit ? 1 : 0)
                    s.bindDouble(14, track.addedAt.timeIntervalSince1970)
                })
        }
    }

    private func track(from statement: SQLiteDatabase.Statement) -> Track? {
        guard let id = statement.text(0), let providerRaw = statement.text(1),
              let provider = ProviderID(rawValue: providerRaw),
              let title = statement.text(3), let artist = statement.text(4) else { return nil }
        return Track(
            id: id,
            provider: provider,
            externalID: statement.text(2) ?? "",
            title: title,
            artist: artist,
            album: statement.text(5),
            duration: statement.double(6),
            artworkURL: statement.text(7).flatMap(URL.init(string:)),
            streamURL: statement.text(8).flatMap(URL.init(string:)),
            isPreview: statement.bool(9),
            year: statement.int(10) > 0 ? Int(statement.int(10)) : nil,
            genre: statement.text(11),
            explicit: statement.bool(12),
            addedAt: Date(timeIntervalSince1970: statement.double(13))
        )
    }

    private static let trackColumns = "id, provider, external_id, title, artist, album, duration, artwork, stream, is_preview, year, genre, explicit, added_at"

    func track(id: String) -> Track? {
        var result: Track?
        try? db.query("SELECT \(Self.trackColumns) FROM tracks WHERE id = ?", read: { s in
            if result == nil { result = self.track(from: s) }
        }, bind: { s in s.bindText(1, id) })
        return result
    }

    func tracks(ids: [String]) -> [Track] {
        var byID: [String: Track] = [:]
        for id in ids {
            if let t = track(id: id) { byID[id] = t }
        }
        return ids.compactMap { byID[$0] }
    }

    func allTracks() -> [Track] {
        var result: [Track] = []
        try? db.query("SELECT \(Self.trackColumns) FROM tracks ORDER BY added_at DESC", read: { s in
            if let t = self.track(from: s) { result.append(t) }
        })
        return result
    }

    func searchTracks(_ query: String) -> [Track] {
        // Фильтр на стороне Swift: SQLite lower() не обрабатывает кириллицу.
        let q = query.lowercased().trimmed
        guard !q.isEmpty else { return [] }
        return allTracks().filter { $0.searchKey.contains(q) || ($0.album?.lowercased() ?? "").contains(q) }
    }

    func trackCount() -> Int {
        var count: Int64 = 0
        try? db.query("SELECT COUNT(*) FROM tracks", read: { s in count = s.int(0) })
        return Int(count)
    }

    // MARK: - Favorites / dislikes

    func setFavorite(_ trackID: String, _ on: Bool) {
        if on {
            try? db.run("INSERT OR REPLACE INTO favorites(track_id, added_at) VALUES(?,?)",
                        { s in s.bindText(1, trackID); s.bindDouble(2, Date().timeIntervalSince1970) })
        } else {
            try? db.run("DELETE FROM favorites WHERE track_id = ?", { s in s.bindText(1, trackID) })
        }
    }

    func isFavorite(_ trackID: String) -> Bool {
        var on = false
        try? db.query("SELECT 1 FROM favorites WHERE track_id = ?", read: { _ in on = true },
                      bind: { s in s.bindText(1, trackID) })
        return on
    }

    func setDislike(_ trackID: String, _ on: Bool) {
        if on {
            try? db.run("INSERT OR REPLACE INTO dislikes(track_id, added_at) VALUES(?,?)",
                        { s in s.bindText(1, trackID); s.bindDouble(2, Date().timeIntervalSince1970) })
        } else {
            try? db.run("DELETE FROM dislikes WHERE track_id = ?", { s in s.bindText(1, trackID) })
        }
    }

    func isDisliked(_ trackID: String) -> Bool {
        var on = false
        try? db.query("SELECT 1 FROM dislikes WHERE track_id = ?", read: { _ in on = true },
                      bind: { s in s.bindText(1, trackID) })
        return on
    }

    func favoriteIDs() -> Set<String> {
        var ids = Set<String>()
        try? db.query("SELECT track_id FROM favorites", read: { s in
            if let id = s.text(0) { ids.insert(id) }
        })
        return ids
    }

    func dislikedIDs() -> Set<String> {
        var ids = Set<String>()
        try? db.query("SELECT track_id FROM dislikes", read: { s in
            if let id = s.text(0) { ids.insert(id) }
        })
        return ids
    }

    func favoriteTracks() -> [Track] {
        var result: [Track] = []
        // Колонки квалифицированы: added_at есть в обеих таблицах (иначе SQL-ошибка).
        try? db.query(
            "SELECT t.id, t.provider, t.external_id, t.title, t.artist, t.album, t.duration, t.artwork, t.stream, t.is_preview, t.year, t.genre, t.explicit, t.added_at " +
            "FROM tracks t JOIN favorites f ON f.track_id = t.id ORDER BY f.added_at DESC",
            read: { s in if let t = self.track(from: s) { result.append(t) } })
        return result
    }

    func dislikedTracks() -> [Track] {
        var result: [Track] = []
        try? db.query(
            "SELECT t.id, t.provider, t.external_id, t.title, t.artist, t.album, t.duration, t.artwork, t.stream, t.is_preview, t.year, t.genre, t.explicit, t.added_at " +
            "FROM tracks t JOIN dislikes d ON d.track_id = t.id ORDER BY d.added_at DESC",
            read: { s in if let t = self.track(from: s) { result.append(t) } })
        return result
    }

    // MARK: - Playlists

    func createPlaylist(name: String) -> Playlist {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        try? db.run("INSERT INTO playlists(id, name, created_at, updated_at) VALUES(?,?,?,?)",
                    { s in s.bindText(1, id); s.bindText(2, name); s.bindDouble(3, now); s.bindDouble(4, now) })
        return Playlist(id: id, name: name, createdAt: Date(), updatedAt: Date(), trackCount: 0)
    }

    func deletePlaylist(id: String) {
        try? db.run("DELETE FROM playlists WHERE id = ?", { s in s.bindText(1, id) })
        try? db.run("DELETE FROM playlist_tracks WHERE playlist_id = ?", { s in s.bindText(1, id) })
    }

    func renamePlaylist(id: String, name: String) {
        try? db.run("UPDATE playlists SET name = ?, updated_at = ? WHERE id = ?",
                    { s in s.bindText(1, name); s.bindDouble(2, Date().timeIntervalSince1970); s.bindText(3, id) })
    }

    func playlists() -> [Playlist] {
        var result: [Playlist] = []
        try? db.query("""
            SELECT p.id, p.name, p.created_at, p.updated_at, COUNT(pt.track_id)
            FROM playlists p LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
            GROUP BY p.id ORDER BY p.updated_at DESC
            """, read: { s in
                guard let id = s.text(0), let name = s.text(1) else { return }
                result.append(Playlist(id: id, name: name,
                                       createdAt: Date(timeIntervalSince1970: s.double(2)),
                                       updatedAt: Date(timeIntervalSince1970: s.double(3)),
                                       trackCount: Int(s.int(4))))
            })
        return result
    }

    func addTrack(playlistID: String, trackID: String) {
        var nextPosition: Int64 = 0
        try? db.query("SELECT COALESCE(MAX(position)+1, 0) FROM playlist_tracks WHERE playlist_id = ?",
                      read: { s in nextPosition = s.int(0) },
                      bind: { s in s.bindText(1, playlistID) })
        try? db.run("INSERT OR REPLACE INTO playlist_tracks(playlist_id, position, track_id) VALUES(?,?,?)",
                    { s in s.bindText(1, playlistID); s.bindInt(2, nextPosition); s.bindText(3, trackID) })
        try? db.run("UPDATE playlists SET updated_at = ? WHERE id = ?",
                    { s in s.bindDouble(1, Date().timeIntervalSince1970); s.bindText(2, playlistID) })
    }

    func removeTrack(playlistID: String, trackID: String) {
        var position: Int64 = -1
        try? db.query("SELECT position FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?",
                      read: { s in position = s.int(0) },
                      bind: { s in s.bindText(1, playlistID); s.bindText(2, trackID) })
        guard position >= 0 else { return }
        try? db.run("DELETE FROM playlist_tracks WHERE playlist_id = ? AND position = ?",
                    { s in s.bindText(1, playlistID); s.bindInt(2, position) })
        try? db.run("UPDATE playlist_tracks SET position = position - 1 WHERE playlist_id = ? AND position > ?",
                    { s in s.bindText(1, playlistID); s.bindInt(2, position) })
    }

    func reorderPlaylist(id: String, orderedTrackIDs: [String]) {
        try? db.run("DELETE FROM playlist_tracks WHERE playlist_id = ?", { s in s.bindText(1, id) })
        for (index, trackID) in orderedTrackIDs.enumerated() {
            try? db.run("INSERT INTO playlist_tracks(playlist_id, position, track_id) VALUES(?,?,?)",
                        { s in s.bindText(1, id); s.bindInt(2, Int64(index)); s.bindText(3, trackID) })
        }
    }

    func playlistTracks(id: String) -> [Track] {
        var ids: [String] = []
        try? db.query("SELECT track_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position",
                      read: { s in if let t = s.text(0) { ids.append(t) } },
                      bind: { s in s.bindText(1, id) })
        return tracks(ids: ids)
    }

    func playlistsContaining(trackID: String) -> [String] {
        var ids: [String] = []
        try? db.query("SELECT DISTINCT playlist_id FROM playlist_tracks WHERE track_id = ?",
                      read: { s in if let p = s.text(0) { ids.append(p) } },
                      bind: { s in s.bindText(1, trackID) })
        return ids
    }

    // MARK: - Play history

    @discardableResult
    func addPlay(trackID: String, seconds: TimeInterval, completed: Bool) -> Bool {
        do {
            try db.run("INSERT INTO plays(track_id, played_at, seconds_played, completed) VALUES(?,?,?,?)",
                       { s in
                           s.bindText(1, trackID)
                           s.bindDouble(2, Date().timeIntervalSince1970)
                           s.bindDouble(3, seconds)
                           s.bindInt(4, completed ? 1 : 0)
                       })
            return true
        } catch {
            return false
        }
    }

    func recentPlays(limit: Int) -> [PlayEvent] {
        var result: [PlayEvent] = []
        try? db.query("SELECT id, track_id, played_at, seconds_played, completed FROM plays ORDER BY played_at DESC LIMIT ?",
                      read: { s in
                          result.append(PlayEvent(id: s.int(0), trackID: s.text(1) ?? "",
                                                  playedAt: Date(timeIntervalSince1970: s.double(2)),
                                                  secondsPlayed: s.double(3),
                                                  completed: s.bool(4)))
                      },
                      bind: { s in s.bindInt(1, Int64(limit)) })
        return result
    }

    func playsBetween(from: Date, to: Date) -> [PlayEvent] {
        var result: [PlayEvent] = []
        try? db.query("SELECT id, track_id, played_at, seconds_played, completed FROM plays WHERE played_at >= ? AND played_at < ? ORDER BY played_at DESC",
                      read: { s in
                          result.append(PlayEvent(id: s.int(0), trackID: s.text(1) ?? "",
                                                  playedAt: Date(timeIntervalSince1970: s.double(2)),
                                                  secondsPlayed: s.double(3),
                                                  completed: s.bool(4)))
                      },
                      bind: { s in
                          s.bindDouble(1, from.timeIntervalSince1970)
                          s.bindDouble(2, to.timeIntervalSince1970)
                      })
        return result
    }

    /// Частая единица движения по треку: до 10 секунд считается «коротким проигрыванием».
    static let meaningfulPlaySeconds: TimeInterval = 10

    func topTrackIDs(from: Date, to: Date, limit: Int) -> [String] {
        var ids: [String] = []
        try? db.query("""
            SELECT track_id, COUNT(*) c FROM plays
            WHERE played_at >= ? AND played_at < ? AND seconds_played >= ?
            GROUP BY track_id ORDER BY c DESC LIMIT ?
            """,
            read: { s in if let id = s.text(0) { ids.append(id) } },
            bind: { s in
                s.bindDouble(1, from.timeIntervalSince1970)
                s.bindDouble(2, to.timeIntervalSince1970)
                s.bindDouble(3, Self.meaningfulPlaySeconds)
                s.bindInt(4, Int64(limit))
            })
        return ids
    }

    func topArtists(from: Date, to: Date, limit: Int) -> [(String, Int)] {
        var pairs: [(String, Int)] = []
        try? db.query("""
            SELECT t.artist, COUNT(*) c FROM plays p JOIN tracks t ON t.id = p.track_id
            WHERE p.played_at >= ? AND p.played_at < ? AND p.seconds_played >= ?
            GROUP BY t.artist ORDER BY c DESC LIMIT ?
            """,
            read: { s in if let artist = s.text(0) { pairs.append((artist, Int(s.int(1)))) } },
            bind: { s in
                s.bindDouble(1, from.timeIntervalSince1970)
                s.bindDouble(2, to.timeIntervalSince1970)
                s.bindDouble(3, Self.meaningfulPlaySeconds)
                s.bindInt(4, Int64(limit))
            })
        return pairs
    }

    func totalListeningSeconds(from: Date, to: Date) -> TimeInterval {
        var total: Double = 0
        try? db.query("SELECT SUM(seconds_played) FROM plays WHERE played_at >= ? AND played_at < ?",
                      read: { s in total = s.double(0) },
                      bind: { s in
                          s.bindDouble(1, from.timeIntervalSince1970)
                          s.bindDouble(2, to.timeIntervalSince1970)
                      })
        return total
    }

    func playsPerDay(days: Int) -> [(Date, TimeInterval)] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days, to: Date().dayStart) ?? Date().dayStart
        var buckets: [Date: TimeInterval] = [:]
        try? db.query("SELECT played_at, seconds_played FROM plays WHERE played_at >= ?",
                      read: { s in
                          let date = Date(timeIntervalSince1970: s.double(0))
                          let day = date.dayStart
                          buckets[day, default: 0] += s.double(1)
                      },
                      bind: { s in s.bindDouble(1, start.timeIntervalSince1970) })
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (day, buckets[day] ?? 0)
        }
    }

    // MARK: - Lyrics cache / annotations

    func cachedLyrics(trackKey: String) -> LyricsPayload? {
        var payload: LyricsPayload?
        var syncedText: String?
        var plainText: String?
        var translated: String?
        var source = ""
        try? db.query("SELECT synced, plain, translated, source FROM lyrics_cache WHERE track_key = ?",
                      read: { s in
                          syncedText = s.text(0)
                          plainText = s.text(1)
                          translated = s.text(2)
                          source = s.text(3) ?? ""
                      },
                      bind: { s in s.bindText(1, trackKey) })
        if syncedText != nil || plainText != nil {
            payload = LyricsPayload(synced: syncedText.flatMap(LRCParser.parse),
                                    plain: plainText, source: source, trackKey: trackKey)
        }
        return payload
    }

    func cachedTranslation(trackKey: String) -> String? {
        var text: String?
        try? db.query("SELECT translated FROM lyrics_cache WHERE track_key = ?",
                      read: { s in text = s.text(0) },
                      bind: { s in s.bindText(1, trackKey) })
        return text
    }

    func saveLyrics(trackKey: String, synced: String?, plain: String?, source: String) {
        try? db.run("""
            INSERT INTO lyrics_cache(track_key, synced, plain, translated, source, fetched_at)
            VALUES(?,?,?,?,?,?)
            ON CONFLICT(track_key) DO UPDATE SET synced=excluded.synced, plain=excluded.plain, source=excluded.source, fetched_at=excluded.fetched_at
            """,
            { s in
                s.bindText(1, trackKey)
                s.bindText(2, synced)
                s.bindText(3, plain)
                s.bindNull(4)
                s.bindText(5, source)
                s.bindDouble(6, Date().timeIntervalSince1970)
            })
    }

    func saveTranslation(trackKey: String, text: String) {
        try? db.run("UPDATE lyrics_cache SET translated = ? WHERE track_key = ?",
                    { s in s.bindText(1, text); s.bindText(2, trackKey) })
    }

    func annotations(trackKey: String) -> [Int: String] {
        var map: [Int: String] = [:]
        try? db.query("SELECT line_index, note FROM annotations WHERE track_key = ?",
                      read: { s in map[Int(s.int(0))] = s.text(1) },
                      bind: { s in s.bindText(1, trackKey) })
        return map
    }

    func setAnnotation(trackKey: String, lineIndex: Int, note: String?) {
        if let note, !note.trimmed.isEmpty {
            try? db.run("INSERT OR REPLACE INTO annotations(track_key, line_index, note, created_at) VALUES(?,?,?,?)",
                        { s in
                            s.bindText(1, trackKey)
                            s.bindInt(2, Int64(lineIndex))
                            s.bindText(3, note)
                            s.bindDouble(4, Date().timeIntervalSince1970)
                        })
        } else {
            try? db.run("DELETE FROM annotations WHERE track_key = ? AND line_index = ?",
                        { s in s.bindText(1, trackKey); s.bindInt(2, Int64(lineIndex)) })
        }
    }

    // MARK: - EQ presets

    func eqPresets(trackKey: String?) -> [EQPreset] {
        var result: [EQPreset] = []
        let sql = trackKey == nil
            ? "SELECT id, name, gains, track_key FROM eq_presets WHERE track_key IS NULL ORDER BY created_at"
            : "SELECT id, name, gains, track_key FROM eq_presets WHERE track_key = ? ORDER BY created_at"
        try? db.query(sql,
                      read: { s in
                          guard let id = s.text(0), let name = s.text(1) else { return }
                          let data = s.blob(2) ?? Data()
                          let gains = data.withUnsafeBytes { raw in
                              Array(raw.bindMemory(to: Float.self))
                          }
                          result.append(EQPreset(id: id, name: name, gains: gains, trackKey: s.text(3)))
                      },
                      bind: { s in if let key = trackKey { s.bindText(1, key) } })
        return result
    }

    func saveEQPreset(_ preset: EQPreset) {
        let data = preset.gains.withUnsafeBufferPointer { Data(buffer: $0) }
        try? db.run("INSERT OR REPLACE INTO eq_presets(id, name, gains, track_key, created_at) VALUES(?,?,?,?,?)",
                    { s in
                        s.bindText(1, preset.id)
                        s.bindText(2, preset.name)
                        s.bindBlob(3, data)
                        if let key = preset.trackKey { s.bindText(4, key) } else { s.bindNull(4) }
                        s.bindDouble(5, Date().timeIntervalSince1970)
                    })
    }

    func deleteEQPreset(id: String) {
        try? db.run("DELETE FROM eq_presets WHERE id = ?", { s in s.bindText(1, id) })
    }

    // MARK: - Downloads

    func downloadPath(trackKey: String) -> String? {
        var path: String?
        try? db.query("SELECT file_path FROM downloads WHERE track_key = ?",
                      read: { s in path = s.text(0) },
                      bind: { s in s.bindText(1, trackKey) })
        return path
    }

    func registerDownload(trackKey: String, path: String, size: Int) {
        try? db.run("INSERT OR REPLACE INTO downloads(track_key, file_path, size, created_at) VALUES(?,?,?,?)",
                    { s in
                        s.bindText(1, trackKey)
                        s.bindText(2, path)
                        s.bindInt(3, Int64(size))
                        s.bindDouble(4, Date().timeIntervalSince1970)
                    })
    }

    func removeDownload(trackKey: String) {
        try? db.run("DELETE FROM downloads WHERE track_key = ?", { s in s.bindText(1, trackKey) })
    }

    func downloadedTrackKeys() -> Set<String> {
        var keys = Set<String>()
        try? db.query("SELECT track_key FROM downloads", read: { s in
            if let key = s.text(0) { keys.insert(key) }
        })
        return keys
    }

    func downloadsTotalSize() -> Int {
        var total: Int64 = 0
        try? db.query("SELECT COALESCE(SUM(size),0) FROM downloads", read: { s in total = s.int(0) })
        return Int(total)
    }

    // MARK: - Artist affinity (для My Wave)

    func artistAffinity() -> [String: Double] {
        var map: [String: Double] = [:]
        try? db.query("SELECT artist, score FROM artist_affinity", read: { s in
            if let artist = s.text(0) { map[artist] = s.double(1) }
        })
        return map
    }

    func bumpArtist(_ artist: String, delta: Double) {
        let key = artist.lowercased()
        try? db.run("""
            INSERT INTO artist_affinity(artist, score, updated_at) VALUES(?,?,?)
            ON CONFLICT(artist) DO UPDATE SET score = MAX(-5, MIN(10, score + ?)), updated_at = ?
            """,
            { s in
                s.bindText(1, key)
                s.bindDouble(2, delta)
                s.bindDouble(3, Date().timeIntervalSince1970)
                s.bindDouble(4, delta)
                s.bindDouble(5, Date().timeIntervalSince1970)
            })
    }

    // MARK: - KV store

    func kvString(_ key: String) -> String? {
        var value: String?
        try? db.query("SELECT value FROM kv WHERE key = ?", read: { s in value = s.text(0) },
                      bind: { s in s.bindText(1, key) })
        return value
    }

    func kvSet(_ key: String, _ value: String?) {
        if let value {
            try? db.run("INSERT OR REPLACE INTO kv(key, value) VALUES(?,?)",
                        { s in s.bindText(1, key); s.bindText(2, value) })
        } else {
            try? db.run("DELETE FROM kv WHERE key = ?", { s in s.bindText(1, key) })
        }
    }

    // MARK: - Recent searches

    static let recentSearchesKey = "recent_searches"

    func recentSearches() -> [String] {
        guard let data = kvString(Self.recentSearchesKey)?.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    func pushRecentSearch(_ query: String) {
        let q = query.trimmed
        guard !q.isEmpty else { return }
        var list = recentSearches().filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        list.insert(q, at: 0)
        if list.count > 12 { list = Array(list.prefix(12)) }
        if let data = try? JSONEncoder().encode(list) {
            kvSet(Self.recentSearchesKey, String(data: data, encoding: .utf8))
        }
    }

    func clearRecentSearches() {
        kvSet(Self.recentSearchesKey, nil)
    }
}
