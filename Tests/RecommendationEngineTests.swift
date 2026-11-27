import XCTest
@testable import Nocturne

final class RecommendationEngineTests: XCTestCase {

    private func makeTrack(_ title: String, _ artist: String, stream: Bool = true) -> Track {
        Track(provider: .deezer,
              externalID: title,
              title: title,
              artist: artist,
              duration: 200,
              streamURL: stream ? URL(string: "https://example.com/\(title).mp3") : nil)
    }

    private func makeProfile() -> RecommendationEngine.Profile {
        var profile = RecommendationEngine.Profile()
        profile.artistAffinity["likes"] = 3.0
        profile.likedArtists = ["likes"]
        profile.dislikedIDs = ["deezer:bad"]
        profile.recentPlayCounts["deezer:overplayed"] = 2
        return profile
    }

    func testScorePrefersLikedArtistAndPlayable() {
        let profile = makeProfile()
        let liked = RecommendationEngine.score(track: makeTrack("good", "Likes"),
                                               profile: profile, exploration: 0, random: 0)
        let plain = RecommendationEngine.score(track: makeTrack("plain", "Unknown"),
                                               profile: profile, exploration: 0, random: 0)
        XCTAssertGreaterThan(liked, plain)
    }

    func testDislikedTrackGetsHeavyPenalty() {
        let profile = makeProfile()
        var bad = makeTrack("bad", "Nobody")
        bad.id = "deezer:bad"
        let disliked = RecommendationEngine.score(track: bad, profile: profile,
                                                  exploration: 0, random: 0)
        let plain = RecommendationEngine.score(track: makeTrack("plain", "Unknown"),
                                               profile: profile, exploration: 0, random: 0)
        XCTAssertLessThan(disliked, plain)
    }

    func testRecentlyPlayedPenalty() {
        let profile = makeProfile()
        var played = makeTrack("overplayed", "Likes")
        played.id = "deezer:overplayed"
        let fresh = RecommendationEngine.score(track: makeTrack("fresh", "Likes"),
                                               profile: profile, exploration: 0, random: 0)
        let stale = RecommendationEngine.score(track: played, profile: profile,
                                               exploration: 0, random: 0)
        XCTAssertLessThan(stale, fresh)
    }

    func testSelectWaveExcludesAndDiversifies() {
        let profile = makeProfile()
        var candidates: [Track] = []
        let artists = ["Likes", "Other", "Third", "Fourth"]
        for artist in artists {
            for index in 0..<5 {
                candidates.append(makeTrack("\(artist.prefix(2))\(index)", artist))
            }
        }

        let wave = RecommendationEngine.selectWave(candidates: candidates,
                                                   profile: profile,
                                                   count: 8,
                                                   exploration: 0.1,
                                                   excluded: ["deezer:Li0"],
                                                   seed: 42)
        XCTAssertEqual(wave.count, 8)
        XCTAssertFalse(wave.contains { $0.id == "deezer:Li0" })

        // Не более 2 подряд одного артиста
        for (index, track) in wave.enumerated() where index >= 2 {
            let same = track.artist == wave[index - 1].artist && track.artist == wave[index - 2].artist
            XCTAssertFalse(same, "Три подряд трека одного артиста в волне")
        }
    }

    func testSeededGeneratorIsDeterministic() {
        var gen1 = SeededGenerator(seed: 7)
        var gen2 = SeededGenerator(seed: 7)
        let a = (0..<10).map { _ in gen1.next() }
        let b = (0..<10).map { _ in gen2.next() }
        XCTAssertEqual(a, b)
    }
}
