import Foundation
import AVFoundation

/// Аудиодвижок на AVAudioEngine: два независимых голоса (для crossfade),
/// per-voice time/pitch (скорость), общий 10-полосный эквалайзер.
/// Работает с файлами (локальными и скачанными во временный кэш).
final class AudioEngine {
    struct Voice {
        let node: AVAudioPlayerNode
        let timePitch: AVAudioUnitTimePitch
        var file: AVAudioFile?
        var nextReadFrame: AVAudioFramePosition = 0
        var connectedFormat: AVAudioFormat?
        var finishedHandler: (() -> Void)?
        var onNaturalEnd: Bool = false
    }

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: EQPreset.bandFrequencies.count)
    private var voices: [Voice] = []
    private let workQueue = DispatchQueue(label: "app.nocturne.audioengine", qos: .userInitiated)

    /// Индекс голоса, завершил ли трек естественным концом.
    var onVoiceFinished: ((_ voiceIndex: Int, _ natural: Bool) -> Void)?

    private var started = false

    init() {
        let realMixer = engine.mainMixerNode
        engine.attach(eq)
        engine.connect(realMixer, to: eq, format: realMixer.outputFormat(forBus: 0))
        engine.connect(eq, to: engine.outputNode, format: realMixer.outputFormat(forBus: 0))
        for _ in 0..<2 {
            let node = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch()
            engine.attach(node)
            engine.attach(timePitch)
            voices.append(Voice(node: node, timePitch: timePitch))
        }
        configureEQBands(gains: Array(repeating: 0, count: EQPreset.bandFrequencies.count))
    }

    // MARK: - EQ

    func configureEQBands(gains: [Float]) {
        for (index, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = EQPreset.bandFrequencies[index]
            band.bandwidth = 0.9
            band.gain = index < gains.count ? max(-12, min(12, gains[index])) : 0
            band.bypass = false
        }
    }

    func setEQBypassed(_ bypassed: Bool) {
        for band in eq.bands { band.bypass = bypassed }
    }

    func setSpeed(_ speed: Double, voiceIndex: Int) {
        guard voices.indices.contains(voiceIndex) else { return }
        voices[voiceIndex].timePitch.rate = Float(max(0.25, min(2.5, speed)))
    }

    // MARK: - Playback control

    /// Запуск файла на выбранном голосе. `fadeIn` — мягкое нарастание (crossfade).
    func play(fileURL: URL,
              voiceIndex: Int,
              startAt: TimeInterval = 0,
              fadeIn: TimeInterval = 0,
              speed: Double = 1.0,
              onFinished: @escaping () -> Void) throws {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat

        workQueue.sync { [self] in
            guard voices.indices.contains(voiceIndex) else { return }
            var voice = voices[voiceIndex]
            voice.node.stop()
            voice.file = file
            voice.nextReadFrame = AVAudioFramePosition(max(0, startAt) * format.sampleRate)
            voice.finishedHandler = onFinished
            voice.onNaturalEnd = true
            voice.timePitch.rate = Float(speed)

            if voice.connectedFormat !== format {
                engine.connect(voice.node, to: voice.timePitch, format: format)
                engine.connect(voice.timePitch, to: engine.mainMixerNode, format: format)
                voice.connectedFormat = format
            }

            voice.node.volume = 0
            voices[voiceIndex] = voice
        }

        try startEngineIfNeeded()

        workQueue.sync { [self] in
            var voice = voices[voiceIndex]
            voice.node.volume = 0
            voice.node.play()
            if fadeIn > 0 {
                voice.node.setVolume(1.0, fadeTime: fadeIn)
            } else {
                voice.node.volume = 1.0
            }
            voices[voiceIndex] = voice
            scheduleNextSegment(voiceIndex: voiceIndex)
        }
    }

    private func scheduleNextSegment(voiceIndex: Int) {
        workQueue.async { [self] in
            guard voices.indices.contains(voiceIndex) else { return }
            let voice = voices[voiceIndex]
            guard let file = voice.file else { return }
            let format = file.processingFormat
            let totalFrames = file.length

            if voice.nextReadFrame >= totalFrames {
                finish(voiceIndex: voiceIndex, natural: true)
                return
            }

            let chunkFrames: AVAudioFrameCount = 65_536
            let remaining = totalFrames - voice.nextReadFrame
            let toSchedule = min(chunkFrames, AVAudioFrameCount(remaining))

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: toSchedule) else {
                finish(voiceIndex: voiceIndex, natural: false)
                return
            }
            file.framePosition = voice.nextReadFrame
            do {
                try file.read(into: buffer, frameCount: toSchedule)
            } catch {
                finish(voiceIndex: voiceIndex, natural: false)
                return
            }

            voice.node.scheduleBuffer(buffer, at: nil, options: []) { [self] in
                workQueue.async {
                    guard voices.indices.contains(voiceIndex) else { return }
                    var updated = voices[voiceIndex]
                    updated.nextReadFrame += AVAudioFramePosition(toSchedule)
                    voices[voiceIndex] = updated
                    if updated.nextReadFrame >= totalFrames {
                        finish(voiceIndex: voiceIndex, natural: true)
                    } else {
                        scheduleNextSegment(voiceIndex: voiceIndex)
                    }
                }
            }
        }
    }

    private func finish(voiceIndex: Int, natural: Bool) {
        guard voices.indices.contains(voiceIndex) else { return }
        var voice = voices[voiceIndex]
        let handler = voice.finishedHandler
        voice.finishedHandler = nil
        voices[voiceIndex] = voice
        DispatchQueue.main.async { [weak self] in
            self?.onVoiceFinished?(voiceIndex, natural)
            handler?()
        }
    }

    func stop(voiceIndex: Int, fadeOut: TimeInterval = 0) {
        workQueue.sync { [self] in
            guard voices.indices.contains(voiceIndex) else { return }
            var voice = voices[voiceIndex]
            if fadeOut > 0, voice.node.isPlaying {
                voice.node.setVolume(0, fadeTime: fadeOut)
                let node = voice.node
                DispatchQueue.global().asyncAfter(deadline: .now() + fadeOut + 0.05) {
                    node.stop()
                    node.volume = 1
                }
            } else {
                voice.node.stop()
                voice.node.volume = 1
            }
            voice.finishedHandler = nil
            voice.onNaturalEnd = false
            voices[voiceIndex] = voice
        }
    }

    func pause(voiceIndex: Int) {
        workQueue.sync { [self] in
            guard voices.indices.contains(voiceIndex) else { return }
            voices[voiceIndex].node.pause()
        }
    }

    func resume(voiceIndex: Int) {
        workQueue.sync { [self] in
            guard voices.indices.contains(voiceIndex) else { return }
            voices[voiceIndex].node.play()
        }
    }

    func setVoiceVolume(_ volume: Float, voiceIndex: Int, fade: TimeInterval = 0) {
        workQueue.sync { [self] in
            guard voices.indices.contains(voiceIndex) else { return }
            voices[voiceIndex].node.setVolume(volume, fadeTime: fade)
        }
    }

    /// Громкость мастера (UI-слайдер).
    func setMasterVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }

    var activeVoiceIndex: Int? {
        voices.firstIndex { $0.node.isPlaying }
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            try engine.start()
            started = true
        }
    }

    func suspendEngine() {
        if engine.isRunning {
            engine.pause()
        }
    }

    /// Обработка прерывания (звонок, Siri): короткая пауза движка.
    func handleInterruptionBegan() {
        for voice in voices where voice.node.isPlaying {
            voice.node.pause()
        }
    }

    var sampleRateOfActiveVoice: Double {
        guard let index = activeVoiceIndex, let file = voices[index].file else { return 44_100 }
        return file.processingFormat.sampleRate
    }
}
