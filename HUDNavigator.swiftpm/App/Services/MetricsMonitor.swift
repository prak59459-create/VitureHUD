import Foundation
import UIKit
import QuartzCore
import Observation

/// 描画 fps の計測（CADisplayLink）。
@MainActor
@Observable
final class MetricsMonitor {
    private(set) var fps: Double = 0

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private let target = DisplayLinkTarget()
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var windowStart = CACurrentMediaTime()

    func start() {
        guard link == nil else { return }
        target.onTick = { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private func tick() {
        frames += 1
        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        if elapsed >= 1 {
            fps = Double(frames) / elapsed
            frames = 0
            windowStart = now
        }
    }
}

private final class DisplayLinkTarget: NSObject {
    var onTick: (() -> Void)?
    @objc func tick() { onTick?() }
}

/// 実機テストモード：チェックリストの結果と計測値を記録し、JSON で書き出す。
@MainActor
@Observable
final class DeviceTestModel {
    private(set) var entries: [String: ChecklistEntry] = [:]
    private(set) var metrics: [MetricSample] = []
    private(set) var log: [String] = []
    private(set) var isRecordingMetrics = false

    @ObservationIgnored private var store: JSONFileStore?
    @ObservationIgnored private var metricsTask: Task<Void, Never>?
    @ObservationIgnored var sampleProvider: (() -> MetricSample)?

    static var environment: TestEnvironment {
        #if FULL_BUILD
        return .installedApp
        #else
        return .playgrounds
        #endif
    }

    var items: [ChecklistItem] { DeviceChecklist.items(for: Self.environment) }

    func load(from store: JSONFileStore) {
        self.store = store
        let saved = store.load([ChecklistEntry].self, from: "device-test") ?? []
        entries = Dictionary(saved.map { ($0.itemID, $0) }, uniquingKeysWith: { _, b in b })
    }

    func entry(for id: String) -> ChecklistEntry {
        entries[id] ?? ChecklistEntry(itemID: id)
    }

    func set(_ id: String, result: CheckResult) {
        var e = entry(for: id)
        e.result = result
        e.updatedAt = Date()
        entries[id] = e
        record("\(id): \(result.displayName)")
        save()
    }

    func setNote(_ id: String, note: String) {
        var e = entry(for: id)
        e.note = note
        e.updatedAt = Date()
        entries[id] = e
        save()
    }

    func record(_ line: String) {
        log.append("\(HUDFormat.clock(Date(), seconds: true)) \(line)")
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    func reset() {
        entries.removeAll()
        metrics.removeAll()
        log.removeAll()
        save()
    }

    func startMetrics(interval: TimeInterval = 10) {
        guard !isRecordingMetrics else { return }
        isRecordingMetrics = true
        record("計測を開始")
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, let sample = self.sampleProvider?() {
                    self.metrics.append(sample)
                    if self.metrics.count > 2000 { self.metrics.removeFirst() }
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopMetrics() {
        metricsTask?.cancel()
        metricsTask = nil
        isRecordingMetrics = false
        record("計測を停止")
    }

    func report(deviceModel: String, systemVersion: String, externalDisplay: String?) -> DeviceTestReport {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return DeviceTestReport(
            appVersion: version,
            buildNumber: build,
            environment: Self.environment,
            deviceModel: deviceModel,
            systemVersion: systemVersion,
            externalDisplay: externalDisplay,
            createdAt: Date(),
            entries: items.map { entry(for: $0.id) },
            metrics: metrics,
            log: log
        )
    }

    /// 書き出し用ファイルを作る（共有シートで渡す）
    func exportFile(_ report: DeviceTestReport, roundLocations: Bool) -> URL? {
        guard let data = try? report.exportData(roundLocations: roundLocations) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HUDNavigator-実機テスト-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func save() {
        try? store?.save(Array(entries.values), as: "device-test")
    }
}
