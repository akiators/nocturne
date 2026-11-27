import Foundation
import ShazamKit
import AVFoundation

/// Распознавание музыки через ShazamKit (бесплатно, локально по звуку вокруг).
/// Использует SHManagedSession (iOS 17+): микрофон и буферизация под его контролем.
/// На более старых версиях функция честно сообщает о недоступности.
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

    /// SHManagedSession доступен с iOS 17 — храним type-erased, работаем под #available.
    private var session: AnyObject?
    private var timeoutTask: Task<Void, Never>?

    var isSupported: Bool {
        if #available(iOS 17.0, *) { return true }
        return false
    }

    override init() {
        super.init()
    }

    // MARK: - Control

    func start() {
        guard !isListening else { return }
        guard isSupported else {
            errorText = "Распознавание музыки доступно на iOS 17 и новее."
            return
        }
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

    private func beginListening() {
        guard #available(iOS 17.0, *) else { return }
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "Аудио недоступно: \(error.localizedDescription)"
            return
        }

        let session = SHManagedSession()
        session.delegate = self
        self.session = session
        session.start()
        isListening = true

        // Страховочный таймаут: если совпадения нет — сообщаем и останавливаемся.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, self.isListening else { return }
            self.errorText = "Записали 20 секунд, но трек не узнали. Попробуйте ближе к источнику звука."
            self.stop()
        }
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if #available(iOS 17.0, *) {
            (session as? SHManagedSession)?.stop()
        }
        session = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
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
