import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Локальные файлы пользователя (MP3, FLAC, M4A, AAC, WAV, OGG, Opus — по поддержке iOS).
/// Полное воспроизведение через AVAudioEngine, доступны загрузки и офлайн по определению.
final class LocalFilesProvider: MusicProvider {
    let id: ProviderID = .local
    let capabilities: ProviderCapabilities = [.search, .fullPlayback, .download, .relatedTracks]
    var isConfigured: Bool { true }
    var setupHint: String { "Импортируйте файлы из приложения «Файлы». Воспроизведение полное, без ограничений качества." }

    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
    }

    static var mediaDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Import

    /// Импорт файлов, выбранных в документ-пикере. Возвращает добавленные треки.
    @discardableResult
    func importFiles(at urls: [URL]) throws -> [Track] {
        var imported: [Track] = []
        let fm = FileManager.default
        for url in urls {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            do {
                let ext = url.pathExtension.lowercased()
                let fileURL = Self.mediaDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
                try fm.copyItem(at: url, to: fileURL)
                let track = try makeTrack(for: fileURL, originalName: url.deletingPathExtension().lastPathComponent)
                store.upsertTracks([track])
                imported.append(track)
            } catch {
                continue
            }
        }
        return imported
    }

    private func makeTrack(for fileURL: URL, originalName: String) throws -> Track {
        let file = try AVAudioFile(forReading: fileURL)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let parts = originalName.components(separatedBy: " - ")
        let artist = parts.count >= 2 ? parts[0].trimmed : "Локальный файл"
        let title = parts.count >= 2 ? parts.dropFirst().joined(separator: " - ").trimmed : originalName
        return Track(provider: .local,
                     externalID: fileURL.lastPathComponent,
                     title: title,
                     artist: artist,
                     album: nil,
                     duration: duration,
                     artworkURL: nil,
                     streamURL: fileURL,
                     isPreview: false)
    }

    // MARK: - MusicProvider

    func search(_ query: String, limit: Int) async throws -> SearchResults {
        let local = store.searchTracks(query).filter { $0.provider == .local }
        var results = SearchResults(tracks: Array(local.prefix(limit)))
        results.byProvider[.local] = results
        return results
    }

    func chartTracks(limit: Int) async throws -> [Track] {
        let local = store.allTracks().filter { $0.provider == .local }
        return Array(local.prefix(limit))
    }

    /// Похожие: треки того же исполнителя в локальной библиотеке.
    func relatedTracks(for track: Track, limit: Int) async throws -> [Track] {
        store.searchTracks(track.artist).filter { $0.provider == .local && $0.id != track.id }
            .prefix(limit).map { $0 }
    }

    func handoffURL(for track: Track) -> URL? { nil }
}
