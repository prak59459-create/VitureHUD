import Foundation
import AVFoundation
import Speech
import Observation

/// 音声入力（Speech フレームワーク、日本語）。押して話す方式。
@MainActor
@Observable
final class SpeechInputService {
    enum State: Equatable {
        case idle, requestingPermission, listening, processing
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var isOnDevice = false
    private(set) var level: Float = 0

    /// 認識が終わったときに呼ばれる
    @ObservationIgnored var onFinalText: ((String) -> Void)?
    /// 端末内認識だけを使う（音声を外部に送らない）
    @ObservationIgnored var requireOnDevice = true

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?

    var isListening: Bool { state == .listening }
    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func toggle() {
        if isListening { stop() } else { Task { await start() } }
    }

    func start() async {
        guard state != .listening else { return }
        state = .requestingPermission
        let speechOK = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
        guard speechOK else {
            state = .unavailable("音声認識が許可されていません（設定アプリで許可してください）")
            return
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else {
            state = .unavailable("マイクが許可されていません（設定アプリで許可してください）")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("日本語の音声認識が利用できません")
            return
        }
        if requireOnDevice && !recognizer.supportsOnDeviceRecognition {
            state = .unavailable("この端末では端末内の音声認識が使えません。設定で「端末内認識のみ」をオフにすると Apple のサーバーで認識します。")
            return
        }
        do {
            try beginRecognition(recognizer)
        } catch {
            state = .unavailable("音声入力を開始できません: \(error.localizedDescription)")
            cleanup()
        }
    }

    private func beginRecognition(_ recognizer: SFSpeechRecognizer) throws {
        cleanup()
        transcript = ""
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition && requireOnDevice
        request.taskHint = .search
        isOnDevice = request.requiresOnDeviceRecognition
        self.request = request

        Self.installTap(on: audioEngine.inputNode, request: request) { [weak self] level in
            Task { @MainActor in self?.level = level }
        }
        audioEngine.prepare()
        try audioEngine.start()
        state = .listening

        task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text; self.resetSilenceTimer() }
                if isFinal || failed { self.finish() }
            }
        }
        resetSilenceTimer()
    }

    // 音声スレッドで呼ばれるクロージャは MainActor から切り離して作る
    nonisolated private static func installTap(on input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest, onLevel: @escaping @Sendable (Float) -> Void) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            onLevel(rms(buffer))
        }
    }

    nonisolated private static func startTask(recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest, handler: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    /// 話し終わって 1.6 秒たったら自動で止める
    private func resetSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        guard state == .listening else { return }
        state = .processing
        request?.endAudio()
        // 最終結果が来なくても少し待って終える
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self?.finish()
        }
    }

    private func finish() {
        guard state == .listening || state == .processing else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanup()
        state = .idle
        if !text.isEmpty { onFinalText?(text) }
    }

    private func cleanup() {
        silenceTask?.cancel()
        silenceTask = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func resetError() {
        if case .unavailable = state { state = .idle }
    }

    nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(n)) * 8)
    }
}
