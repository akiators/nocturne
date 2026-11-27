import Foundation

/// Импорт плейлистов: файлы M3U/CSV/JSON и ссылки (Deezer — без ключей,
/// Spotify — при настроенном Client ID). VK/Яндекс импорт Blocked (закрытые API).
final class PlaylistImporter {
    private let store: LibraryStore
    private let registry: ProviderRegistry
    private let search: SearchService

    init(store: LibraryStore, registry: ProviderRegistry, search: SearchService) {
        self.store = store
        self.registry = registry
        self.search = search
    }

    enum ImportError: LocalizedError {
        case unknownFormat
        case emptyFile
        case unsupportedLink(String)

        var errorDescription: String? {
            switch self {
            case .unknownFormat: return "Не удалось определить формат плейлиста (M3U, CSV, JSON или ссылка)."
            case .emptyFile: return "Файл пустой. Выберите другой."
            case .unsupportedLink(let reason): return reason
            }
        }
    }

    // MARK: - From file

    @discardableResult
    func importFromFile(url: URL) throws -> Playlist {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8), !text.trimmed.isEmpty else {
            throw ImportError.emptyFile
        }
        let ext = url.pathExtension.lowercased()
        let entries: [(artist: String, title: String)]
        if ext == "m3u" || ext == "m3u8" || text.hasPrefix("#EXTM3U") {
            entries = Self.parseM3U(text)
        } else if ext == "csv" {
            entries = Self.parseCSV(text)
        } else if ext == "json" {
            entries = Self.parseJSON(text)
        } else {
            throw ImportError.unknownFormat
        }
        guard !entries.isEmpty else { throw ImportError.unknownFormat }
        let name = url.deletingPathExtension().lastPathComponent
        return save(entries: entries, name: name)
    }

    /// M3U: строки #EXTINF:duration,Artist - Title
    static func parseM3U(_ text: String) -> [(String, String)] {
        var result: [(String, String)] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            guard trimmed.hasPrefix("#EXTINF:") else { continue }
            let payload = trimmed.dropFirst("#EXTINF:".count)
            let afterComma = payload.drop(while: { $0 != "," })
            guard afterComma.hasPrefix(",") else { continue }
            let label = String(afterComma.dropFirst()).trimmed
            let parts = label.components(separatedBy: " - ")
            if parts.count >= 2 {
                result.append((parts[0].trimmed, parts.dropFirst().joined(separator: " - ").trimmed))
            } else {
                result.append(("", label))
            }
        }
        return result
    }

    /// CSV: title,artist (порядок или title;artist)
    static func parseCSV(_ text: String) -> [(String, String)] {
        var result: [(String, String)] = []
        for line in text.components(separatedBy: .newlines).dropFirst() {
            let parts = line.components(separatedBy: ",").map(\.trimmed)
            if parts.count >= 2 {
                result.append((parts[1], parts[0]))
            }
        }
        return result
    }

    static func parseJSON(_ text: String) -> [(String, String)] {
        struct ExportEntry: Decodable { let artist: String?; let title: String? }
        struct Export: Decodable { let tracks: [ExportEntry]? }
        guard let data = text.data(using: .utf8),
              let export = try? JSONDecoder().decode(Export.self, from: data) else { return [] }
        return (export.tracks ?? []).compactMap { entry in
            guard let title = entry.title else { return nil }
            return (entry.artist ?? "", title)
        }
    }

    // MARK: - From URL

    @discardableResult
    func importFromURL(_ url: URL) async throws -> Playlist {
        // Deezer: публичный API, работает всегда.
        if url.host?.contains("deezer") == true, let deezer = registry.provider(.deezer) {
            let tracks = try await deezer.playlistTracks(from: url)
            let name = "Плейлист Deezer"
            return save(tracks: tracks, name: name)
        }

        // Spotify: требует настроенного Client ID.
        if url.host?.contains("spotify") == true {
            guard let spotify = registry.provider(.spotify), spotify.isConfigured else {
                throw ImportError.unsupportedLink("Для импорта из Spotify настройте Client ID и войдите в аккаунт в «Настройки → Источники».")
            }
            let tracks = try await spotify.playlistTracks(from: url)
            return save(tracks: tracks, name: "Плейлист Spotify")
        }

        if url.host?.contains("vk.com") == true || url.host?.contains("vk.ru") == true {
            throw ImportError.unsupportedLink("VK закрыл API аудио для сторонних приложений — импорт плейлистов из VK недоступен (документированное ограничение).")
        }
        if url.host?.contains("youtube") == true || url.host?.contains("youtu.be") == true {
            throw ImportError.unsupportedLink("YouTube не предоставляет официального API импорта плейлистов без ключа с квотами — недоступно.")
        }

        throw ImportError.unsupportedLink("Ссылка не распознана. Поддерживаются плейлисты Deezer и Spotify.")
    }

    // MARK: - Save (с резолвом треков в источниках)

    private func save(entries: [(String, String)], name: String) -> Playlist {
        let playlist = store.createPlaylist(name: name.isEmpty ? "Импортированный плейлист" : name)
        Task { [weak self] in
            guard let self else { return }
            await self.resolveAndFill(entries: entries, playlistID: playlist.id)
        }
        return playlist
    }

    private func save(tracks: [Track], name: String) -> Playlist {
        store.upsertTracks(tracks)
        let playlist = store.createPlaylist(name: name)
        for track in tracks {
            store.addTrack(playlistID: playlist.id, trackID: track.id)
        }
        return playlist
    }

    /// Резолв: ищем трек в подключённых источниках (снача­ла точное совпадение).
    private func resolveAndFill(entries: [(String, String)], playlistID: String) async {
        var resolved: [Track] = []
        for entry in entries.prefix(300) {
            if let track = await search.findTrack(artist: entry.artist, title: entry.title) {
                resolved.append(track)
            } else {
                // Заглушка-строка для ручного поиска позже.
                let stub = Track(provider: .local,
                                 externalID: "import-\(UUID().uuidString.prefix(8))",
                                 title: entry.title,
                                 artist: entry.artist.isEmpty ? "Неизвестный исполнитель" : entry.artist)
                resolved.append(stub)
            }
        }
        store.upsertTracks(resolved)
        for track in resolved {
            store.addTrack(playlistID: playlistID, trackID: track.id)
        }
    }
}
