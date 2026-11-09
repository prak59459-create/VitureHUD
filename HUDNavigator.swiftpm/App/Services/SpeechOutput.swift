import Foundation
import AVFoundation
import Observation

enum SpeechPriority: Int, Comparable {
    case low = 0, normal, high

    static func < (lhs: SpeechPriority, rhs: SpeechPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 音声案内・読み上げ（AVSpeechSynthesizer、無料・オフライン）。
@MainActor
@Observable
final class SpeechOutput {
    private(set) var isSpeaking = false
    private(set) var lastSpokenText: String?
    private(set) var availableVoices: [(id: String, name: String, quality: String)] = []

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate = SpeechDelegate()
    @ObservationIgnored private var currentPriority: SpeechPriority = .low
    @ObservationIgnored var settingsProvider: (() -> VoiceSettings)?

    init() {
        synthesizer.delegate = delegate
        delegate.owner = self
        loadVoices()
    }

    func loadVoices() {
        availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ja") }
            .map { voice in
                let quality: String
                switch voice.quality {
                case .premium: quality = "プレミアム"
                case .enhanced: quality = "拡張"
                default: quality = "標準"
                }
                return (voice.identifier, voice.name, quality)
            }
            .sorted { $0.quality > $1.quality }
    }

    /// 読み上げる。優先度が高い場合は今の読み上げを止める。
    func speak(_ text: String, priority: SpeechPriority = .normal, force: Bool = false) {
        let settings = settingsProvider?() ?? VoiceSettings()
        guard force || settings.guidanceEnabled || priority == .high else { return }
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            if priority >= currentPriority && priority != .low {
                synthesizer.stopSpeaking(at: .immediate)
            } else if priority == .low {
                return
            }
        }
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        if let id = settings.voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        }
        utterance.rate = Float(settings.rate.clamped(to: 0.3...0.65))
        utterance.pitchMultiplier = Float(settings.pitch.clamped(to: 0.5...2.0))
        utterance.volume = Float(settings.volume.clamped(to: 0...1))
        currentPriority = priority
        lastSpokenText = text
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func repeatLast() {
        guard let text = lastSpokenText else { return }
        speak(text, priority: .normal, force: true)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // 音楽などの音量を一時的に下げて読み上げる
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    fileprivate func didFinish() {
        isSpeaking = false
        currentPriority = .low
        // 他のアプリの音量を元に戻す（音声入力中は触らない）
        if !synthesizer.isSpeaking {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var owner: SpeechOutput?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.owner?.didFinish() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.owner?.didFinish() }
    }
}
