import Foundation
import AudioToolbox
import UIKit
import UserNotifications
import Observation

/// HUD 上の通知・警告。種類ごとに表示・読み上げ・警告音を設定できる。
@MainActor
@Observable
final class AlertCenter {
    private(set) var active: [HUDAlert] = []
    private(set) var history: [HUDAlert] = []
    /// 危険警告の点滅（HUD の縁を赤く光らせる）
    private(set) var hazardFlash: HazardLevel = .none

    @ObservationIgnored private var policy = AlertPolicy(settings: NotificationSettings())
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored var speak: ((String, SpeechPriority) -> Void)?
    @ObservationIgnored var isMoving: (() -> Bool)?
    @ObservationIgnored var isInBackground: (() -> Bool)?

    func update(settings: NotificationSettings) {
        policy.settings = settings
    }

    var visible: [HUDAlert] { AlertPolicy.displayQueue(active, now: Date()) }

    /// - Parameter allowSpeech: false にすると読み上げない（ナビの案内のように別の場所で読み上げる場合）
    func post(_ alert: HUDAlert, allowSpeech: Bool = true) {
        var decision = policy.decide(alert, now: Date(), isMoving: isMoving?() ?? false)
        if !allowSpeech { decision.speak = false }
        guard !decision.isSuppressed else { return }
        history.insert(alert, at: 0)
        if history.count > 100 { history.removeLast(history.count - 100) }
        if decision.showBanner {
            active.removeAll { $0.dedupeKey == alert.dedupeKey }
            active.append(alert)
            scheduleCleanup()
        }
        if decision.speak {
            speak?(alert.textToSpeak, alert.priority >= .critical ? .high : .normal)
        }
        if decision.playSound {
            AudioServicesPlaySystemSound(alert.priority >= .critical ? 1005 : 1007)
            if alert.priority >= .important {
                UINotificationFeedbackGenerator().notificationOccurred(alert.priority >= .critical ? .error : .warning)
            }
        }
        if alert.category == .hazard {
            flash(alert.priority >= .critical ? .high : .medium)
        }
        if (isInBackground?() ?? false) && alert.priority >= .important {
            scheduleLocalNotification(alert)
        }
    }

    func dismiss(_ id: UUID) {
        active.removeAll { $0.id == id }
    }

    func clearHistory() { history.removeAll() }

    private func flash(_ level: HazardLevel) {
        hazardFlash = level
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.hazardFlash = .none
        }
    }

    private func scheduleCleanup() {
        guard cleanupTask == nil else { return }
        cleanupTask = Task { [weak self] in
            while let self, !self.active.isEmpty {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let now = Date()
                self.active.removeAll { $0.isExpired(at: now) }
            }
            self?.cleanupTask = nil
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleLocalNotification(_ alert: HUDAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = .default
        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
