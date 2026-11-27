import Foundation
import ShazamKit
import AVFoundation

/// Распознавание музыки через ShazamKit (бесплатно, локально по звуку вокруг).
/// SHManagedSession (iOS 17+) сам пишет звук и генерирует сигнатуры:
/// `await session.result()` возвращает .match/.noMatch/.error, `cancel()` прерывает.
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

        let session = SHManagedSession()
        self.session = session
        isListening = true

        // Один цикл распознавания: сессия сама пишет звук до результата.
        let matchTask = Task { [weak self] in
            let result = await session.result()
            guard let self, self.isListening else { return }
            switch result {
            case .match(let match):
                if let item = match.mediaItems.first {
                    self.finish(result: RecognitionResult(
                        title: item.title ?? "Трек",
                        artist: item.artist ?? "",
                        artworkURL: item.artworkURL,
                        appleMusicID: item.appleMusicID))
                } else {
                    self.errorText = "Трек найден, но данных о нём нет. Попробуйте ещё раз."
                    self.stop()
                }
            case .noMatch:
                self.errorText = "Трек не узнали. Поднесите телефон ближе к источнику звука."
                self.stop()
            case .error(let error, _):
                self.errorText = "Ошибка распознавания: \(error.localizedDescription)"
                self.stop()
            @unknown default:
                self.stop()
            }
        }
        _ = matchTask

        // Страховочный таймаут.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 40_000_000_000)
            guard let self, self.isListening else { return }
            self.errorText = "Не дождались результата. Попробуйте ближе к источнику звука."
            self.stop()
        }
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if #available(iOS 17.0, *) {
            (session as? SHManagedSession)?.cancel()
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
