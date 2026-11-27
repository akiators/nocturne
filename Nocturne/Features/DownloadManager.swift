import Foundation

/// Загрузки для офлайн-воспроизведения. Скачивается то, что источник легально
/// отдаёт (preview Deezer, локальные файлы уже на устройстве). Полные треки
/// закрытых сервисов не скачиваются — это документированное ограничение.
@MainActor
final class DownloadManager: ObservableObject {
    private let store: LibraryStore

    @Published var activeDownloads: Set<String> = []          // trackKey в процессе
    @Published var downloadedKeys: Set<String> = []
    @Published var lastError: String?

    init(store: LibraryStore) {
        self.store = store
        downloadedKeys = store.downloadedTrackKeys()
    }

    static var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var canDownload: (Track) -> Bool { track in
        track.provider == .local || (track.streamURL != nil && track.isPreview)
    }

    func download(_ track: Track) async {
        let key = track.id
        guard !activeDownloads.contains(key) else { return }
        guard canDownload(track) else {
            lastError = "Полный трек из \(track.provider.displayName) недоступен для загрузки — источник не отдаёт файл легально. Доступна загрузка фрагмента или локальных файлов."
            return
        }
        guard let url = track.streamURL else {
            lastError = "Нет доступного аудио для загрузки."
            return
        }
        if track.provider == .local {
            if let path = track.streamURL?.path {
                store.registerDownload(trackKey: key, path: path, size: 0)
                downloadedKeys.insert(key)
                Haptics.success()
            }
            return
        }

        activeDownloads.insert(key)
        defer { activeDownloads.remove(key) }
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                lastError = "Сервер ответил HTTP \(http.statusCode)."
                return
            }
            let safeKey = key.replacingOccurrences(of: ":", with: "_")
            let target = Self.downloadsDirectory.appendingPathComponent(safeKey)
            let fm = FileManager.default
            if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
            try fm.moveItem(at: tempURL, to: target)
            let attrs = try? fm.attributesOfItem(atPath: target.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            store.registerDownload(trackKey: key, path: target.path, size: size)
            downloadedKeys.insert(key)
            Haptics.success()
        } catch {
            lastError = "Загрузка не удалась: \(error.localizedDescription)"
        }
    }

    func removeDownload(_ trackKey: String) {
        if let path = store.downloadPath(trackKey: trackKey) {
            try? FileManager.default.removeItem(atPath: path)
        }
        store.removeDownload(trackKey: trackKey)
        downloadedKeys.remove(trackKey)
    }

    func removeAll() {
        for key in downloadedKeys {
            if let path = store.downloadPath(trackKey: key) {
                try? FileManager.default.removeItem(atPath: path)
            }
            store.removeDownload(trackKey: key)
        }
        downloadedKeys.removeAll()
    }

    func isDownloaded(_ track: Track) -> Bool {
        downloadedKeys.contains(track.id)
    }

    var totalSize: Int {
        store.downloadsTotalSize()
    }
}
