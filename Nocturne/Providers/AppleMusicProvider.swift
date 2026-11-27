import Foundation
import MusicKit

/// Apple Music через MusicKit (iOS 15+).
/// Поиск и метаданные каталога доступны всем; воспроизведение полного трека —
/// только подписчикам Apple Music внутри ApplicationMusicPlayer (мы играем 30-сек
/// preview своим движком, полный трек — handoff в Apple Music).
final class AppleMusicProvider: MusicProvider {
    let id: ProviderID = .appleMusic
    let capabilities: ProviderCapabilities = [.search, .previewPlayback, .relatedTracks, .handoff]
    var isConfigured: Bool {
        MusicAuthorization.currentStatus == .authorized
    }
    var setupHint: String { "Нажмите «Разрешить доступ», чтобы искать каталог Apple Music. Полное прослушивание требует подписки Apple Music (handoff)." }

    func search(_ query: String, limit: Int) async throws -> SearchResults {
        var request = MusicCatalogSearchRequest(term: query,
                                                types: [Song.self, Artist.self, Album.self])
        request.limit = limit
        let response = try await request.response()

        let songs = response.songs.compactMap(mapSong)
        let artists = response.artists.compactMap { artist -> ArtistRef? in
            ArtistRef(id: "apple_music:\(artist.id)", name: artist.name,
                      artworkURL: artist.artwork?.url(width: 160, height: 160))
        }
        let albums = response.albums.compactMap { album -> AlbumRef? in
            AlbumRef(id: "apple_music:\(album.id)", title: album.title,
                     artist: album.artistName ?? "",
                     artworkURL: album.artwork?.url(width: 160, height: 160),
                     trackCount: album.trackCount)
        }
        var results = SearchResults(tracks: songs, artists: artists, albums: albums)
        results.byProvider[.appleMusic] = SearchResults(tracks: songs)
        return results
    }

    private func mapSong(_ song: Song) -> Track? {
        Track(provider: .appleMusic,
              externalID: song.id.rawValue,
              title: song.title,
              artist: song.artistName ?? "",
              album: song.albumTitle,
              duration: song.duration ?? 0,
              artworkURL: song.artwork?.url(width: 320, height: 320),
              streamURL: song.previewAssets?.first?.url,
              isPreview: true,
              year: song.releaseDate.map { Calendar.current.component(.year, from: $0) },
              explicit: song.contentRating == .explicit)
    }

    func relatedTracks(for track: Track, limit: Int) async throws -> [Track] {
        // Поиск по исполнителю — простой законный аналог «похожих».
        var request = MusicCatalogSearchRequest(term: track.artist, types: [Song.self])
        request.limit = limit + 2
        let response = try await request.response()
        return response.songs.compactMap(mapSong).filter { $0.id != track.id }.prefix(limit).map { $0 }
    }

    func handoffURL(for track: Track) -> URL? {
        URL(string: "https://music.apple.com/lookup?isSong=\(track.externalID)")
    }
}
