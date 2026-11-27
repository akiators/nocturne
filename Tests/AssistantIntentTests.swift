import XCTest
@testable import Nocturne

final class AssistantIntentTests: XCTestCase {

    func testPlayIntentRU() {
        if case .play(let query) = AssistantEngine.parse("включи пачку сигарет") {
            XCTAssertEqual(query, "пачку сигарет")
        } else {
            XCTFail("Ожидался play")
        }
    }

    func testPlayIntentEN() {
        if case .play(let query) = AssistantEngine.parse("play bohemian rhapsody") {
            XCTAssertEqual(query, "bohemian rhapsody")
        } else {
            XCTFail("Ожидался play")
        }
    }

    func testPauseAndNext() {
        if case .pause = AssistantEngine.parse("поставь на паузу") {} else { XCTFail("pause") }
        if case .pause = AssistantEngine.parse("стоп") {} else { XCTFail("pause стоп") }
        if case .next = AssistantEngine.parse("следующий трек") {} else { XCTFail("next") }
        if case .previous = AssistantEngine.parse("предыдущий") {} else { XCTFail("previous") }
    }

    func testRepeatModes() {
        if case .toggleRepeat(.one) = AssistantEngine.parse("включи повтор одного трека") {} else { XCTFail("repeat one") }
        if case .toggleRepeat(.all) = AssistantEngine.parse("повтор всей очереди") {} else { XCTFail("repeat all") }
        if case .toggleRepeat(.off) = AssistantEngine.parse("выключи повтор") {} else { XCTFail("repeat off") }
    }

    func testShuffleAndWaveAndStats() {
        if case .toggleShuffle = AssistantEngine.parse("перемешай очередь") {} else { XCTFail("shuffle") }
        if case .playWave = AssistantEngine.parse("включи мою волну") {} else { XCTFail("wave") }
        if case .showStats = AssistantEngine.parse("покажи мою статистику") {} else { XCTFail("stats") }
    }

    func testPlaylistByDescription() {
        if case .createPlaylist(let description) = AssistantEngine.parse("собери плейлист под вечер пятницы") {
            XCTAssertEqual(description, "под вечер пятницы")
        } else {
            XCTFail("createPlaylist")
        }
    }

    func testLyricsSearch() {
        if case .findLyrics(let query) = AssistantEngine.parse("найди трек по тексту я свободен") {
            XCTAssertTrue(query.contains("свободен"))
        } else {
            XCTFail("findLyrics")
        }
    }

    func testFallbackSearch() {
        if case .fallbackSearch(let query) = AssistantEngine.parse("деепеш мод") {
            XCTAssertEqual(query, "деепеш мод")
        } else {
            XCTFail("fallback")
        }
    }
}
