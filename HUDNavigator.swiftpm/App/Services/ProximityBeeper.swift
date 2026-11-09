import Foundation
import AVFoundation

/// 駐車センサーのような警告音。近いほど速く・高く鳴り、物のある側（左右）から聞こえる。
final class ProximityBeeper {
    private final class Tone: @unchecked Sendable {
        var on = false
        var phase = 0.0
        var frequency = 880.0
    }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var timer: Timer?
    private let tone = Tone()
    private var interval: TimeInterval = 1
    private var lastBeep = Date.distantPast
    private var running = false

    /// 距離（m）と横の位置（0＝左〜1＝右）
    func update(distance: Double, x: Double, threshold: Double) {
        guard distance < threshold else { silence(); return }
        startIfNeeded()
        let ratio = max(0, min(1, distance / max(0.1, threshold)))
        interval = 0.08 + ratio * 0.6
        tone.frequency = distance < threshold * 0.4 ? 1320 : 880
        source?.pan = Float(max(-1, min(1, (x - 0.5) * 2)))
    }

    func silence() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        tone.on = false
        engine.stop()
        if let source {
            engine.detach(source)
            self.source = nil
        }
    }

    private func startIfNeeded() {
        guard !running else { return }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0, let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let tone = self.tone
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let step = 2 * Double.pi * tone.frequency / sampleRate
            for frame in 0..<Int(frameCount) {
                let v: Float = tone.on ? Float(sin(tone.phase)) * 0.25 : 0
                tone.phase += step
                if tone.phase > 2 * Double.pi { tone.phase -= 2 * Double.pi }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = v
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        do {
            try engine.start()
        } catch {
            engine.detach(node)
            return
        }
        source = node
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let now = Date()
        if tone.on {
            if now.timeIntervalSince(lastBeep) >= 0.06 { tone.on = false }
        } else if now.timeIntervalSince(lastBeep) >= interval {
            tone.on = true
            lastBeep = now
        }
    }
}
