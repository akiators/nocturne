import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI

/// Управляющий плеером: очередь, crossfade, now playing, таймер сна,
/// восстановление сессии, учёт истории. UI читает @Published-состояние.
@MainActor
final class PlayerController: ObservableObject {
    // MARK: - Published state

    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var isLoadingTrack = false
    @Published var queue: [Track] = []
    @Published var queueIndex: Int = 0
    @Published var repeatMode: RepeatMode = .off {
        didSet { persistState() }
    }
    @Published var shuffleOn = false {
        didSet { applyShuffleState(); persistState() }
    }
    @Published var volume: Float = 1.0 {
        didSet { engine.setMasterVolume(volume); UserDefaults.standard.set(volume, forKey: "player_volume") }
    }
    @Published var speed: Double = 1.0 {
        didSet { applySpeed(); persistSpeed() }
    }
    @Published private(set) var sleepRemaining: TimeInterval = 0
    @Published var isSleepTimerOn: Bool = false { didSet { persistState() } }

    /// Замыкание добирает продолжение очереди (My Wave), когда она близка к концу.
    var queueRefill: ((_ currentQueue: [Track]) async -> [Track])?

    // MARK: - Dependencies

    private let engine = AudioEngine()
    private let store: LibraryStore
    private let settings: SettingsStore
    private let registry: ProviderRegistry
    private let downloads: DownloadManager

    // MARK: - Internal

    /// Режим Apple Music: стрим ведёт системный ApplicationMusicPlayer (подписчики).
    @Published private(set) var isMusicKitPlayback = false
    private let musicKit = MusicKitPlaybackController()
    private let liveActivities = LiveActivityManager()

    private var currentVoice = 0
    private var originalQueue: [Track] = []
    private var playbackStartReference: CFAbsoluteTime = 0
    private var playbackOffset: TimeInterval = 0
    private var progressTimer: Timer?
    private var sleepTimer: Timer?
    private var sleepEndOfTrack = false
    private var loadGeneration = 0
    private var wasPlayingBeforeInterruption = false

    static let stateKey = "player_session_state"

    // MARK: - Init

    init(store: LibraryStore, settings: SettingsStore, providers: ProviderRegistry, downloads: DownloadManager) {
        self.store = store
        self.settings = settings
        self.registry = providers
        self.downloads = downloads

        engine.onVoiceFinished = { [weak self] _, natural in
            Task { @MainActor [weak self] in
                self?.handleVoiceFinished(natural: natural)
            }
        }
        speed = settings.playbackSpeed
        volume = UserDefaults.standard.object(forKey: "player_volume") as? Float ?? 1.0
        engine.setMasterVolume(volume)
        engine.setSpeed(speed, voiceIndex: 0)
        engine.setSpeed(speed, voiceIndex: 1)

        setupRemoteCommands()
        observeInterruptions()
        applySavedEQ()
    }

    // MARK: - Public playback API

    func play(_ track: Track, in contextQueue: [Track]? = nil, startIndex: Int = 0) {
        if let contextQueue {
            queue = contextQueue
            originalQueue = contextQueue
            queueIndex = startIndex
        } else if queue.firstIndex(where: { $0.id == track.id }) == nil {
            queue = [track]
            originalQueue = [track]
            queueIndex = 0
        }
        Task { await start(track: track, crossfade: shouldCrossfade) }
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        guard isPlaying else { return }
        if isMusicKitPlayback {
            musicKit.pause()
        } else {
            engine.pause(voiceIndex: currentVoice)
        }
        freezeProgress()
        isPlaying = false
        updateNowPlaying()
        persistState()
        if let track = currentTrack {
            liveActivities.update(track: track, isPlaying: false, elapsed: currentTime, force: true)
        }
    }

    func resume() {
        guard currentTrack != nil, !isPlaying else { return }
        if isMusicKitPlayback {
            musicKit.resume()
        } else {
            engine.resume(voiceIndex: currentVoice)
        }
        playbackStartReference = CFAbsoluteTimeGetCurrent()
        isPlaying = true
        updateNowPlaying()
        startProgressTimer()
        if let track = currentTrack {
            liveActivities.update(track: track, isPlaying: true, elapsed: currentTime, force: true)
        }
    }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }

        if sleepEndOfTrack && auto {
            stopSleepTimer()
            pause()
            sleepEndOfTrack = false
            return
        }

        if repeatMode == .one && auto {
            Task { await start(track: queue[queueIndex], crossfade: false) }
            return
        }

        let nextIndex = queueIndex + 1
        if nextIndex < queue.count {
            queueIndex = nextIndex
            Task { await start(track: queue[nextIndex], crossfade: shouldCrossfade) }
        } else if repeatMode == .all && auto {
            queueIndex = 0
            Task { await start(track: queue[0], crossfade: shouldCrossfade) }
        } else if !auto {
            // Ручной next в конце очереди: замкнуть на первый трек.
            queueIndex = 0
            Task { await start(track: queue[0], crossfade: shouldCrossfade) }
        } else {
            // Очередь кончилась: оставляем последний трек выбранным.
            pause()
            currentTime = 0
            playbackOffset = 0
        }
        Task { await refillQueueIfNeeded() }
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        let prevIndex = queueIndex - 1
        if prevIndex >= 0 {
            queueIndex = prevIndex
            Task { await start(track: queue[prevIndex], crossfade: shouldCrossfade) }
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let track = currentTrack else { return }
        let target = max(0, min(seconds, track.duration > 0 ? track.duration : seconds))
        playbackOffset = target
        playbackStartReference = CFAbsoluteTimeGetCurrent()
        currentTime = target

        if isMusicKitPlayback {
            musicKit.seek(to: target)
            updateNowPlaying()
            persistState()
            return
        }

        if let fileURL = activeFileURL {
            do {
                try engine.play(fileURL: fileURL,
                                voiceIndex: currentVoice,
                                startAt: target,
                                fadeIn: 0,
                                speed: speed) { [weak self] in
                    Task { @MainActor [weak self] in self?.handleVoiceFinished(natural: true) }
                }
                if !isPlaying { engine.pause(voiceIndex: currentVoice) }
            } catch {
                isPlaying = false
            }
        }
        updateNowPlaying()
        persistState()
    }

    func playFromQueue(index: Int) {
        guard queue.indices.contains(index) else { return }
        queueIndex = index
        Task { await start(track: queue[index], crossfade: shouldCrossfade) }
    }

    func removeQueuedTrack(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let removedID = queue[index].id
        queue.remove(at: index)
        originalQueue.removeAll { $0.id == removedID }
        if index < queueIndex {
            queueIndex -= 1
        } else if index == queueIndex {
            // Удалили текущий: переходим к следующему.
            if queue.indices.contains(queueIndex) {
                let nextTrack = queue[queueIndex]
                Task { await start(track: nextTrack, crossfade: shouldCrossfade) }
            } else {
                stopEverything()
            }
        }
        persistState()
    }

    func moveQueuedTrack(from: IndexSet, to: Int) {
        queue.move(fromOffsets: from, toOffset: to)
        persistState()
    }

    func enqueue(_ track: Track) {
        queue.append(track)
        if originalQueue.isEmpty { originalQueue = queue }
        persistState()
    }

    func enqueueNext(_ track: Track) {
        let insertAt = min(queueIndex + 1, queue.count)
        queue.insert(track, at: insertAt)
        persistState()
    }

    func stopEverything() {
        if isMusicKitPlayback {
            musicKit.pause()
            isMusicKitPlayback = false
        }
        engine.stop(voiceIndex: 0)
        engine.stop(voiceIndex: 1)
        isPlaying = false
        currentTrack = nil
        currentTime = 0
        stopProgressTimer()
        liveActivities.stop()
        updateNowPlaying(clear: true)
        persistState()
    }

    // MARK: - Sleep timer

    func startSleepTimer(minutes: Int) {
        stopSleepTimer()
        sleepEndOfTrack = false
        sleepRemaining = TimeInterval(minutes * 60)
        isSleepTimerOn = true
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sleepRemaining -= 1
                if self.sleepRemaining <= 0 {
                    self.fadeOutAndPause()
                    self.stopSleepTimer()
                }
            }
        }
    }

    func startSleepTimerEndOfTrack() {
        stopSleepTimer()
        sleepEndOfTrack = true
        isSleepTimerOn = true
    }

    func stopSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepRemaining = 0
        isSleepTimerOn = false
        sleepEndOfTrack = false
    }

    private func fadeOutAndPause() {
        engine.setVoiceVolume(0, voiceIndex: currentVoice, fade: 2)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            self?.engine.setVoiceVolume(1, voiceIndex: self?.currentVoice ?? 0, fade: 0)
            self?.pause()
        }
    }

    // MARK: - EQ

    func applyEQPreset(_ preset: EQPreset) {
        engine.configureEQBands(gains: preset.gains)
        engine.setEQBypassed(!settings.eqEnabled)
        settings.selectedPresetID = preset.id
        persistState()
    }

    func setEQEnabled(_ enabled: Bool) {
        settings.eqEnabled = enabled
        engine.setEQBypassed(!enabled)
    }

    func setEQGains(_ gains: [Float]) {
        engine.configureEQBands(gains: gains)
    }

    private func applySavedEQ() {
        if settings.eqEnabled {
            let presets = store.eqPresets(trackKey: nil)
            let builtin = BuiltInEQPresets.all
            let selected = settings.selectedPresetID
            let preset = presets.first { $0.id == selected } ?? builtin.first { $0.id == selected }
            if let preset {
                engine.configureEQBands(gains: preset.gains)
            }
            engine.setEQBypassed(false)
        } else {
            engine.setEQBypassed(true)
        }
    }

    func applyTrackEQIfAny(for track: Track) {
        guard settings.useTrackEQPresets else { return }
        let perTrack = store.eqPresets(trackKey: track.id)
        if let preset = perTrack.first {
            engine.configureEQBands(gains: preset.gains)
        }
    }

    // MARK: - Speed

    func applySpeed() {
        engine.setSpeed(speed, voiceIndex: 0)
        engine.setSpeed(speed, voiceIndex: 1)
        settings.playbackSpeed = speed
        updateNowPlaying()
    }

    private func persistSpeed() {
        // settings.playbackSpeed уже обновлён в applySpeed; здесь — точка для истории.
    }

    // MARK: - Internals

    private var shouldCrossfade: Bool {
        settings.crossfadeSeconds > 0.5 && isPlaying
    }

    private var activeFileURL: URL? {
        guard let track = currentTrack else { return nil }
        if let savedPath = store.downloadPath(trackKey: track.id) {
            return URL(fileURLWithPath: savedPath)
        }
        if let stream = track.streamURL, stream.isFileURL {
            return stream
        }
        return tempCacheURL(for: track)
    }

    private func tempCacheURL(for track: Track) -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("stream-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeKey = track.id.replacingOccurrences(of: ":", with: "_")
        let url = dir.appendingPathComponent(safeKey)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func start(track: Track, crossfade: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoadingTrack = true

        // Учёт прослушивания предыдущего трека.
        logPlayForCurrentTrack()

        // Apple Music: полное воспроизведение для подписчиков через ApplicationMusicPlayer.
        if track.provider == .appleMusic, musicKit.isAuthorized,
           let song = await musicKit.resolveSong(for: track),
           await musicKit.canPlayCatalog() {
            guard generation == loadGeneration else { return }
            isMusicKitPlayback = true
            engine.stop(voiceIndex: 0)
            engine.stop(voiceIndex: 1)
            currentTrack = track
            currentTime = 0
            playbackOffset = 0
            playbackStartReference = CFAbsoluteTimeGetCurrent()
            isPlaying = true
            isLoadingTrack = false
            store.bumpArtist(track.artist, delta: 0.05)
            startProgressTimer()
            persistState()
            liveActivities.start(track: track)
            await musicKit.play(song: song)
            return
        }
        isMusicKitPlayback = false

        // Резолв источника: офлайн-загрузка → локальный файл → кэш → сеть.
        var fileURL: URL?
        if let saved = store.downloadPath(trackKey: track.id) {
            fileURL = URL(fileURLWithPath: saved)
        } else if let stream = track.streamURL, stream.isFileURL {
            fileURL = stream
        } else if let cached = tempCacheURL(for: track) {
            fileURL = cached
        } else if let stream = track.streamURL {
            fileURL = await downloadToCache(url: stream, track: track)
        }

        guard generation == loadGeneration else { return }
        isLoadingTrack = false

        guard let fileURL else {
            currentTrack = track
            isPlaying = false
            currentTime = 0
            playbackOffset = 0
            updateNowPlaying()
            return
        }

        currentTrack = track
        currentTime = 0
        playbackOffset = 0
        playbackStartReference = CFAbsoluteTimeGetCurrent()
        store.bumpArtist(track.artist, delta: 0.05)

        let fade = crossfade ? settings.crossfadeSeconds : 0
        do {
            if crossfade && isPlaying {
                let newVoice = 1 - currentVoice
                engine.stop(voiceIndex: currentVoice, fadeOut: fade)
                currentVoice = newVoice
            } else {
                engine.stop(voiceIndex: 0)
                engine.stop(voiceIndex: 1)
                currentVoice = 0
            }
            try engine.play(fileURL: fileURL,
                            voiceIndex: currentVoice,
                            startAt: 0,
                            fadeIn: fade,
                            speed: speed) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleVoiceFinished(natural: true)
                }
            }
            isPlaying = true
            applyTrackEQIfAny(for: track)
        } catch {
            isPlaying = false
        }

        updateNowPlaying()
        startProgressTimer()
        persistState()
        liveActivities.start(track: track)
    }

    private func downloadToCache(url: URL, track: Track) async -> URL? {
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            let http = response as? HTTPURLResponse
            guard http == nil || (200..<300).contains(http!.statusCode) else { return nil }
            let target = tempCacheDestination(for: track)
            let fm = FileManager.default
            if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
            try fm.moveItem(at: tempURL, to: target)
            return target
        } catch {
            return nil
        }
    }

    private func tempCacheDestination(for track: Track) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("stream-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeKey = track.id.replacingOccurrences(of: ":", with: "_")
        return dir.appendingPathComponent(safeKey)
    }

    private func handleVoiceFinished(natural: Bool) {
        guard isPlaying || natural else { return }
        logPlayForCurrentTrack(completed: natural)
        if natural {
            next(auto: true)
        } else {
            isPlaying = false
        }
    }

    private func logPlayForCurrentTrack(completed: Bool = false) {
        guard let track = currentTrack else { return }
        let elapsed = playbackOffset + (isPlaying ? CFAbsoluteTimeGetCurrent() - playbackStartReference : 0)
        guard elapsed >= LibraryStore.meaningfulPlaySeconds else { return }
        _ = store.addPlay(trackID: track.id, seconds: elapsed, completed: completed)
        store.bumpArtist(track.artist, delta: completed ? 1.0 : 0.3)
    }

    private func refillQueueIfNeeded() async {
        guard let refill = queueRefill else { return }
        guard queueIndex >= queue.count - 2 else { return }
        let additions = await refill(queue)
        let existingIDs = Set(queue.map(\.id))
        let fresh = additions.filter { !existingIDs.contains($0.id) }
        guard !fresh.isEmpty else { return }
        queue.append(contentsOf: fresh)
        persistState()
    }

    // MARK: - Shuffle

    private func applyShuffleState() {
        if shuffleOn {
            guard let current = queue.indices.contains(queueIndex) ? queue[queueIndex] : nil else { return }
            var upcoming = Array(queue[(queueIndex + 1)...])
            upcoming.shuffle()
            queue = [current] + upcoming
            queueIndex = 0
        } else if !originalQueue.isEmpty {
            if let current = queue.indices.contains(queueIndex) ? queue[queueIndex] : nil,
               let restoredIndex = originalQueue.firstIndex(where: { $0.id == current.id }) {
                queue = originalQueue
                queueIndex = restoredIndex
            }
        }
    }

    // MARK: - Progress

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickProgress() }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func tickProgress() {
        guard isPlaying, currentTrack != nil else { return }

        if isMusicKitPlayback {
            // Стрим ведёт системный плеер — читаем его позицию.
            let musicKitTime = musicKit.playbackTime
            if musicKitTime > 0 { currentTime = musicKitTime }
            let limit = currentTrack?.duration ?? 0
            if limit > 0, currentTime >= limit - 0.7, currentTime > 3 {
                handleVoiceFinished(natural: true)
                return
            }
            if let track = currentTrack {
                liveActivities.update(track: track, isPlaying: true, elapsed: currentTime)
            }
            return
        }

        let elapsed = playbackOffset + (CFAbsoluteTimeGetCurrent() - playbackStartReference)
        let limit = currentTrack?.duration ?? 0
        if limit > 0 && elapsed > limit + 3 {
            // Защита от зависшего расписания: принудительное завершение.
            handleVoiceFinished(natural: true)
            return
        }
        currentTime = elapsed
        updateNowPlayingLight()
        if let track = currentTrack {
            liveActivities.update(track: track, isPlaying: true, elapsed: elapsed)
        }
    }

    private func freezeProgress() {
        if isPlaying {
            playbackOffset += CFAbsoluteTimeGetCurrent() - playbackStartReference
        }
        stopProgressTimer()
    }

    var progressClamped: TimeInterval {
        guard let track = currentTrack else { return 0 }
        return min(currentTime, max(track.duration, 0.1))
    }

    // MARK: - Now playing / remote

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: positionEvent.positionTime) }
            return .success
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch type {
                case .began:
                    self.wasPlayingBeforeInterruption = self.isPlaying
                    self.pause()
                case .ended:
                    let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                    if options.contains(.shouldResume), self.wasPlayingBeforeInterruption {
                        self.resume()
                    }
                    self.wasPlayingBeforeInterruption = false
                default:
                    break
                }
            }
        }
    }

    private func updateNowPlaying(clear: Bool = false) {
        // В режиме Apple Music Now Playing ведёт ApplicationMusicPlayer — не мешаем.
        if isMusicKitPlayback && !clear {
            return
        }
        let center = MPNowPlayingInfoCenter.default()
        if clear || currentTrack == nil {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack?.title ?? "",
            MPMediaItemPropertyArtist: currentTrack?.artist ?? "",
            MPMediaItemPropertyAlbumTitle: currentTrack?.album ?? "",
            MPMediaItemPropertyPlaybackDuration: currentTrack?.duration ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queueIndex
        ]
        if let artworkURL = currentTrack?.artworkURL {
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 320, height: 320)) { _ in
                ImageCache.shared.object(forKey: artworkURL.absoluteString as NSString) ?? UIImage()
            }
            info[MPMediaItemPropertyArtwork] = artwork
            // Подгрузим обложку, если она ещё не в кэше, и обновим инфо заново.
            Task {
                await ImageLoader.shared.prefetch(url: artworkURL)
                await MainActor.run { self.updateNowPlaying() }
            }
        }
        center.nowPlayingInfo = info
    }

    private func updateNowPlayingLight() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? speed : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Session persistence

    struct PersistedState: Codable {
        var queueIDs: [String]
        var index: Int
        var position: TimeInterval
        var repeatMode: RepeatMode
        var shuffleOn: Bool
        var speed: Double
    }

    func persistState() {
        let state = PersistedState(queueIDs: queue.map(\.id),
                                   index: queueIndex,
                                   position: currentTime,
                                   repeatMode: repeatMode,
                                   shuffleOn: shuffleOn,
                                   speed: speed)
        if let data = try? JSONEncoder().encode(state), let json = String(data: data, encoding: .utf8) {
            store.kvSet(Self.stateKey, json)
        }
    }

    func restoreStateIfNeeded() {
        restoreState()
    }

    /// Восстановление очереди после перезапуска приложения (без автозапуска).
    func restoreState() {
        guard let json = store.kvString(Self.stateKey),
              let data = json.data(using: .utf8),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        let tracks = store.tracks(ids: state.queueIDs)
        guard !tracks.isEmpty else { return }
        queue = tracks
        originalQueue = tracks
        queueIndex = min(state.index, tracks.count - 1)
        repeatMode = state.repeatMode
        shuffleOn = state.shuffleOn
        speed = state.speed
        currentTime = state.position
        playbackOffset = state.position
        currentTrack = queue.indices.contains(queueIndex) ? queue[queueIndex] : nil
        isPlaying = false
        updateNowPlaying()
    }
}
