import XCTest
@testable import Nocturne

final class LibraryStoreTests: XCTestCase {

    private var store: LibraryStore!
    private var dbURL: URL!

    override func setUpWithError() throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).sqlite")
        let db = try SQLiteDatabase(url: dbURL)
        store = try LibraryStore(db: db)
    }

    override func tearDownWithError() throws {
        store = nil
        if let dbURL {
            try? FileManager.default.removeItem(at: dbURL)
        }
    }

    private func track(_ title: String, artist: String = "Artist", provider: ProviderID = .deezer) -> Track {
        Track(provider: provider, externalID: title, title: title, artist: artist, duration: 180)
    }

    func testUpsertAndSearch() throws {
        let t1 = track("Ночь на улице", artist: "Кино")
        let t2 = track("Пачка сигарет", artist: "Кино")
        let t3 = track("Dream On", artist: "Aerosmith")
        store.upsertTracks([t1, t2, t3])

        XCTAssertEqual(store.trackCount(), 3)
        XCTAssertEqual(store.searchTracks("кино").count, 2)
        XCTAssertEqual(store.track(id: t1.id)?.title, "Ночь на улице")

        // Upsert обновляет, не дублирует
        let updated = Track(provider: .deezer, externalID: "Ночь на улице",
                            title: "Ночь на улице (remaster)", artist: "Кино")
        store.upsertTracks([updated])
        XCTAssertEqual(store.trackCount(), 3)
        XCTAssertEqual(store.track(id: t1.id)?.title, "Ночь на улице (remaster)")
    }

    func testFavoritesAndDislikes() throws {
        let t = track("Fav")
        store.upsertTracks([t])
        XCTAssertFalse(store.isFavorite(t.id))
        store.setFavorite(t.id, true)
        XCTAssertTrue(store.isFavorite(t.id))
        XCTAssertEqual(store.favoriteTracks().count, 1)
        store.setFavorite(t.id, false)
        XCTAssertFalse(store.isFavorite(t.id))

        store.setDislike(t.id, true)
        XCTAssertTrue(store.isDisliked(t.id))
        XCTAssertEqual(store.dislikedTracks().count, 1)
    }

    func testPlaylistsCRUD() throws {
        let a = track("A"), b = track("B"), c = track("C")
        store.upsertTracks([a, b, c])
        let playlist = store.createPlaylist(name: "Тест")

        store.addTrack(playlistID: playlist.id, trackID: a.id)
        store.addTrack(playlistID: playlist.id, trackID: b.id)
        store.addTrack(playlistID: playlist.id, trackID: c.id)
        XCTAssertEqual(store.playlistTracks(id: playlist.id).map(\.id), [a.id, b.id, c.id])

        // Удаление середины не ломает порядок
        store.removeTrack(playlistID: playlist.id, trackID: b.id)
        XCTAssertEqual(store.playlistTracks(id: playlist.id).map(\.id), [a.id, c.id])

        // Reorder
        store.reorderPlaylist(id: playlist.id, orderedTrackIDs: [c.id, a.id])
        XCTAssertEqual(store.playlistTracks(id: playlist.id).map(\.id), [c.id, a.id])

        store.renamePlaylist(id: playlist.id, name: "Новое имя")
        XCTAssertEqual(store.playlists().first?.name, "Новое имя")

        store.deletePlaylist(id: playlist.id)
        XCTAssertTrue(store.playlists().isEmpty)
        XCTAssertTrue(store.playlistTracks(id: playlist.id).isEmpty)
    }

    func testPlaysAndAggregates() throws {
        let t1 = track("Top", artist: "Alpha")
        let t2 = track("Rare", artist: "Beta")
        store.upsertTracks([t1, t2])

        for _ in 0..<5 {
            _ = store.addPlay(trackID: t1.id, seconds: 60, completed: true)
        }
        _ = store.addPlay(trackID: t2.id, seconds: 20, completed: false)

        XCTAssertEqual(store.topTrackIDs(from: Date(timeIntervalSince1970: 0), to: Date(), limit: 5).first, t1.id)
        XCTAssertEqual(store.topArtists(from: Date(timeIntervalSince1970: 0), to: Date(), limit: 5).first?.0, "Alpha")
        XCTAssertEqual(store.totalListeningSeconds(from: Date(timeIntervalSince1970: 0), to: Date()), 320, accuracy: 0.5)
        XCTAssertEqual(store.recentPlays(limit: 10).count, 6)
    }

    func testKvAndRecentSearches() throws {
        store.kvSet("key", "value")
        XCTAssertEqual(store.kvString("key"), "value")
        store.kvSet("key", nil)
        XCTAssertNil(store.kvString("key"))

        store.pushRecentSearch("кино")
        store.pushRecentSearch("depeche mode")
        store.pushRecentSearch("кино")
        XCTAssertEqual(store.recentSearches(), ["кино", "depeche mode"])
        store.clearRecentSearches()
        XCTAssertTrue(store.recentSearches().isEmpty)
    }

    func testEQPresets() throws {
        let preset = EQPreset(id: "p1", name: "Мой", gains: [1, 2, 3, 4, 5, 4, 3, 2, 1, 0], trackKey: nil)
        store.saveEQPreset(preset)
        let loaded = store.eqPresets(trackKey: nil)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].gains, preset.gains)
        store.deleteEQPreset(id: "p1")
        XCTAssertTrue(store.eqPresets(trackKey: nil).isEmpty)
    }

    func testArtistAffinityClamped() throws {
        store.bumpArtist("Кино", delta: 2)
        store.bumpArtist("Кино", delta: 20)
        XCTAssertEqual(store.artistAffinity()["кино"] ?? 0, 10, accuracy: 0.01)
        store.bumpArtist("Кино", delta: -100)
        XCTAssertEqual(store.artistAffinity()["кино"] ?? 0, -5, accuracy: 0.01)
    }
}
