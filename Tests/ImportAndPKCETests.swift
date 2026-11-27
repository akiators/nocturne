import XCTest
@testable import Nocturne

final class ImportAndPKCETests: XCTestCase {

    func testParseM3U() {
        let m3u = """
        #EXTM3U
        #EXTINF:180,Кино - Пачка сигарет
        /path/a.mp3
        #EXTINF:200,Depeche Mode - Enjoy the Silence
        /path/b.mp3
        """
        let entries = PlaylistImporter.parseM3U(m3u)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].0, "Кино")
        XCTAssertEqual(entries[0].1, "Пачка сигарет")
        XCTAssertEqual(entries[1].1, "Enjoy the Silence")
    }

    func testParseCSV() {
        let csv = """
        title,artist
        Enjoy the Silence,Depeche Mode
        Ночь,Кино
        """
        let entries = PlaylistImporter.parseCSV(csv)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].0, "Depeche Mode")
        XCTAssertEqual(entries[1].1, "Ночь")
    }

    func testParseJSON() {
        let json = """
        {"tracks":[{"artist":"Кино","title":"Группа крови"},{"title":"Без артиста"}]}
        """
        let entries = PlaylistImporter.parseJSON(json)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].0, "Кино")
        XCTAssertEqual(entries[1].0, "")
    }

    func testDeezerPlaylistID() {
        let url = URL(string: "https://www.deezer.com/playlist/123456789")!
        XCTAssertEqual(DeezerProvider.playlistID(from: url), "123456789")
        let trackURL = URL(string: "https://www.deezer.com/track/987")!
        XCTAssertNotEqual(DeezerProvider.playlistID(from: trackURL), "987")
    }

    func testPKCEBase64URL() {
        let verifier = SpotifyProvider.randomURLSafeBase64(count: 64)
        XCTAssertEqual(verifier.count, 86) // 64 байта → 86 символов base64url без паддинга
        XCTAssertFalse(verifier.contains("+"))
        XCTAssertFalse(verifier.contains("/"))
        XCTAssertFalse(verifier.contains("="))

        let data = Data("+/\u{1}".utf8.prefix(0)) // пустая проверка формы
        XCTAssertTrue(SpotifyProvider.base64URL(data).isEmpty)
    }

    func testURLDecoding() {
        let encoded = "Как дела?".urlEncoded
        XCTAssertFalse(encoded.contains(" "))
        XCTAssertFalse(encoded.contains("?"))
        XCTAssertTrue(encoded.hasPrefix("%D0%9A")) // UTF-8 кириллицы
        XCTAssertEqual("hello-world".urlEncoded, "hello-world") // ASCII проходит как есть
    }
}
