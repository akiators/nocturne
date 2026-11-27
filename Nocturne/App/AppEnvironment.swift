import Foundation
import AVFoundation
import SwiftUI

/// Состав приложения: хранилище, провайдеры, плеер, сервисы. Один объект, всё локальное.
@MainActor
final class AppEnvironment: ObservableObject {
    let library: LibraryStore
    let settings: SettingsStore
    let providers: ProviderRegistry
    let player: PlayerController
    let search: SearchService
    let wave: WaveFeedService
    let lyrics: LyricsService
    let genius: GeniusService
    let assistant: AssistantEngine
    let downloads: DownloadManager
    let stats: StatsService
    let backup: BackupService
    let importer: PlaylistImporter

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let dbURL = appSupport.appendingPathComponent("nocturne.sqlite")

        let db: SQLiteDatabase
        let store: LibraryStore
        do {
            db = try SQLiteDatabase(url: dbURL)
            store = try LibraryStore(db: db)
        } catch {
            // Крайне маловероятно (диск недоступен); резервный in-memory путь невозможен
            // для sqlite3_open_v2 — фатальная ошибка конфигурации устройства.
            fatalError("Не удалось открыть локальное хранилище: \(error)")
        }

        let settings = SettingsStore()
        let registry = ProviderRegistry(store: store, settings: settings)

        self.library = store
        self.settings = settings
        self.providers = registry
        self.downloads = DownloadManager(store: store)
        self.player = PlayerController(store: store, settings: settings, providers: registry, downloads: downloads)
        self.search = SearchService(registry: registry, store: store)
        self.wave = WaveFeedService(store: store, registry: registry, settings: settings)
        self.lyrics = LyricsService(store: store, settings: settings, search: search)
        self.genius = GeniusService(store: store, settings: settings)
        self.stats = StatsService(store: store)
        self.importer = PlaylistImporter(store: store, registry: registry, search: search)
        self.backup = BackupService(store: store, settings: settings)
        self.assistant = AssistantEngine(player: player, search: search, wave: wave,
                                         store: store, lyrics: lyrics, genius: genius)

        configureAudioSession()
        player.restoreStateIfNeeded()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Аудио может быть занято другим приложением — плеер всё равно стартует
            // при первом воспроизведении.
        }
    }
}

// MARK: - Haptics

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
