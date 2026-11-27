import XCTest
@testable import Nocturne

final class LRCParserTests: XCTestCase {

    func testParseSimpleSyncedLyrics() {
        let lrc = """
        [00:12.00]Первая строка
        [00:15.50]Вторая строка
        [01:02.999]Третья строка
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertNotNil(lines)
        XCTAssertEqual(lines?.count, 3)
        XCTAssertEqual(lines?[0].time ?? 0, 12.0, accuracy: 0.01)
        XCTAssertEqual(lines?[1].time ?? 0, 15.5, accuracy: 0.01)
        XCTAssertEqual(lines?[2].time ?? 0, 62.999, accuracy: 0.01)
        XCTAssertEqual(lines?[0].text, "Первая строка")
    }

    func testParseMetadataAndOffsetIgnored() {
        let lrc = """
        [ar:Artist]
        [ti:Title]
        [offset:0]
        [00:05.00]Текст
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines?.count, 1)
        XCTAssertEqual(lines?[0].text, "Текст")
    }

    func testParseMultipleTimestampsPerLine() {
        let lrc = "[00:01.00][00:11.00]Повтор"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines?.count, 2)
        XCTAssertEqual(lines?[0].time ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(lines?[1].time ?? 0, 11.0, accuracy: 0.01)
    }

    func testParseRejectsPlain() {
        XCTAssertNil(LRCParser.parse("просто текст без тегов"))
    }

    func testActiveLineIndex() {
        let lines = [
            LyricLine(id: 0, time: 0, text: "a"),
            LyricLine(id: 1, time: 10, text: "b"),
            LyricLine(id: 2, time: 20, text: "c")
        ]
        XCTAssertEqual(LRCParser.activeLineIndex(in: lines, at: 5), 0)
        XCTAssertEqual(LRCParser.activeLineIndex(in: lines, at: 10), 1)
        XCTAssertEqual(LRCParser.activeLineIndex(in: lines, at: 25), 2)
    }
}
