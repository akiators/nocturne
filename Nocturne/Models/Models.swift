import Foundation

// MARK: - Providers

enum ProviderID: String, Codable, CaseIterable, Identifiable, Hashable {
    case local
    case appleMusic = "apple_music"
    case deezer
    case spotify
    case youTubeMusic = "youtube_music"
    case vk
    case soundCloud = "soundcloud"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "Мои файлы"
        case .appleMusic: return "Apple Music"
        case .deezer: return "Deezer"
        case .spotify: return "Spotify"
        case .youTubeMusic: return "YouTube Music"
        case .vk: return "VK Музыка"
        case .soundCloud: return "SoundCloud"
        }
    }

    var tintHex: String {
        switch self {
        case .local: return "#8E8E93"
        case .appleMusic: return "#FA57C1"
        case .deezer: return "#A238FF"
        case .spotify: return "#1DB954"
        case .youTubeMusic: return "#FF0033"
        case .vk: return "#0077FF"
        case .soundCloud: return "#FF5500"
        }
    }
}

struct ProviderCapabilities: OptionSet {
    let rawValue: Int
    static let search = ProviderCapabilities(rawValue: 1 << 0)
    static let previewPlayback = ProviderCapabilities(rawValue: 1 << 1)
    static let fullPlayback = ProviderCapabilities(rawValue: 1 << 2)
    static let download = ProviderCapabilities(rawValue: 1 << 3)
    static let playlistImport = ProviderCapabilities(rawValue: 1 << 4)
    static let relatedTracks = ProviderCapabilities(rawValue: 1 << 5)
    static let handoff = ProviderCapabilities(rawValue: 1 << 6)
    static let auth = ProviderCapabilities(rawValue: 1 << 7)
}

// MARK: - Core entities

struct Track: Identifiable, Hashable, Codable {
    var id: String              // "<provider>:<externalID>"
    var provider: ProviderID
    var externalID: String
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval
    var artworkURL: URL?
    var streamURL: URL?
    var isPreview: Bool
    var year: Int?
    var genre: String?
    var explicit: Bool
    var addedAt: Date

    init(id: String? = nil,
         provider: ProviderID,
         externalID: String,
         title: String,
         artist: String,
         album: String? = nil,
         duration: TimeInterval = 0,
         artworkURL: URL? = nil,
         streamURL: URL? = nil,
         isPreview: Bool = false,
         year: Int? = nil,
         genre: String? = nil,
         explicit: Bool = false,
         addedAt: Date = Date()) {
        self.id = id ?? Track.makeID(provider: provider, externalID: externalID)
        self.provider = provider
        self.externalID = externalID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.streamURL = streamURL
        self.isPreview = isPreview
        self.year = year
        self.genre = genre
        self.explicit = explicit
        self.addedAt = addedAt
    }

    static func makeID(provider: ProviderID, externalID: String) -> String {
        "\(provider.rawValue):\(externalID)"
    }

    var searchKey: String { "\(artist) \(title)".lowercased() }
}

struct ArtistRef: Identifiable, Hashable {
    var id: String
    var name: String
    var artworkURL: URL?
}

struct AlbumRef: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var artworkURL: URL?
    var trackCount: Int?
}

struct SearchResults {
    var tracks: [Track] = []
    var artists: [ArtistRef] = []
    var albums: [AlbumRef] = []
    var byProvider: [ProviderID: SearchResults] = [:]

    static func + (lhs: SearchResults, rhs: SearchResults) -> SearchResults {
        var tracks = lhs.tracks
        var seen = Set(tracks.map(\.searchKey))
        for t in rhs.tracks where !seen.contains(t.searchKey) {
            seen.insert(t.searchKey)
            tracks.append(t)
        }
        return SearchResults(tracks: tracks,
                             artists: lhs.artists + rhs.artists,
                             albums: lhs.albums + rhs.albums,
                             byProvider: [:])
    }
}

// MARK: - Playlist

struct Playlist: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var trackCount: Int
}

// MARK: - Stream

struct TrackStream {
    enum Kind { case localFile, remotePreview, remoteFull, systemPlayer }
    var url: URL
    var kind: Kind
    var startAt: TimeInterval
}

// MARK: - Lyrics

struct LyricLine: Identifiable, Hashable {
    var id: Int
    var time: TimeInterval
    var text: String
}

struct LyricsPayload {
    var synced: [LyricLine]?
    var plain: String?
    var source: String
    var trackKey: String
}

// MARK: - Equalizer

struct EQPreset: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var gains: [Float]          // 10 bands, dB
    var trackKey: String?       // nil = general preset, else per-track
    static let bandFrequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
}

// MARK: - Play history

struct PlayEvent: Identifiable, Hashable {
    var id: Int64
    var trackID: String
    var playedAt: Date
    var secondsPlayed: TimeInterval
    var completed: Bool
}

// MARK: - Settings models

enum AudioQuality: String, Codable, CaseIterable, Identifiable {
    case auto, normal, high, losslessPreferred
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Авто"
        case .normal: return "Обычное"
        case .high: return "Высокое"
        case .losslessPreferred: return "Максимум (FLAC, где доступен)"
        }
    }
}

enum RepeatMode: String, Codable {
    case off, all, one
}

// MARK: - Provider errors

enum ProviderError: LocalizedError {
    case notConfigured(String)
    case noStream(Track)
    case rateLimited
    case authRequired(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let p): return "\(p): источник не настроен. Заполните данные в настройках."
        case .noStream: return "Для этого трека нет доступного потока — откройте его в оригинальном приложении."
        case .rateLimited: return "Слишком много запросов. Повторите позже."
        case .authRequired(let p): return "\(p): требуется вход в аккаунт."
        case .unavailable(let reason): return reason
        }
    }
}
