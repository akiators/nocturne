import Foundation
import ShazamKit
import AVFoundation

/// Распознавание музыки через ShazamKit (бесплатно, локально по звуку вокруг).
/// Требует право доступа к микрофону; право ShazamKit в entitlements.
/// История хранится снаружи (UI пишет её в kv основного хранилища).
@MainActor
final class RecognitionService: NSObject, ObservableObject {
    struct RecognitionResult: Identifiable, Codable {
        var id: UUID = UUID()
        var title: String
        var artist: String
        var artworkURL: URL?
        var appleMusicID: String?
    }

    @Published var isListening = false
    @Published var match: RecognitionResult?
    @Published var errorText: String?

    private var session: SHSession?
    private let audioEngine = AVAudioEngine()
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
    }

    // MARK: - Control

    func start() {
        guard !isListening else { return }
        match = nil
        errorText = nil
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if granted {
                    self.beginListening()
                } else {
                    self.errorText = "Разрешите доступ к микрофону в настройках устройства для распознавания."
                }
            }
        }
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        cleanupAudio()
        isListening = false
    }

    private func beginListening() {
        let session = SHSession()
        session.delegate = self
        self.session = session

        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "Аудио недоступно: \(error.localizedDescription)"
            return
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak session] buffer, _ in
            session?.append(buffer)
        }
        do {
            try audioEngine.start()
        } catch {
            errorText = "Микрофон недоступен: \(error.localizedDescription)"
            cleanupAudio()
            return
        }
        isListening = true

        // Автостоп: ShazamKit сам не завершит прослушивание.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, self.isListening else { return }
            self.errorText = "Записали 10 секунд, но трек не узнали. Попробуйте ближе к источнику звука."
            self.stop()
        }
    }

    private func cleanupAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        session = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finish(result: RecognitionResult) {
        match = result
        stop()
    }
}

// MARK: - SHSessionDelegate

extension RecognitionService: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        Task { @MainActor [weak self] in
            guard let self, let item = match.mediaItems.first else { return }
            let result = RecognitionResult(
                title: item.title ?? "Трек",
                artist: item.artist ?? "",
                artworkURL: item.artworkURL,
                appleMusicID: item.appleMusicID)
            self.finish(result: result)
        }
    }

    nonisolated func session(_ session: SHSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.isListening else { return }
            self.errorText = "Ошибка распознавания: \(error.localizedDescription)"
            self.stop()
        }
    }
}
