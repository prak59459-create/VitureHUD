import Foundation
import EventKit
import Observation

/// HUD・ワーク画面に出す予定 1 件
struct AgendaEvent: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var calendarName: String

    func isNow(_ now: Date) -> Bool { !isAllDay && start <= now && now < end }

    /// 「10:00–11:00」「終日」
    var timeText: String {
        isAllDay ? "終日" : "\(HUDFormat.clock(start))–\(HUDFormat.clock(end))"
    }
}

/// カレンダー（iOS の「カレンダー」に入っている予定）を読む。端末内だけで使い、どこにも送らない。
@MainActor
@Observable
final class CalendarService {
    enum Access: Equatable {
        case unknown, unavailable, denied, granted

        var displayName: String {
            switch self {
            case .unknown: return "まだ許可していません"
            case .unavailable: return "この版では使えません"
            case .denied: return "許可されていません（設定アプリで変更できます）"
            case .granted: return "許可済み"
            }
        }
    }

    private(set) var access: Access = .unknown
    /// 今日と明日の予定（始まる順）
    private(set) var events: [AgendaEvent] = []
    private(set) var lastUpdated: Date?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var running = false

    /// 説明文（Info.plist）が入っていない版で許可を求めるとアプリが落ちるため、先に確かめる
    static var isSupported: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    init() {
        refreshAccess()
    }

    private func refreshAccess() {
        guard Self.isSupported else {
            access = .unavailable
            return
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .denied, .restricted, .writeOnly: access = .denied
        default: access = .unknown
        }
    }

    /// 予定ウィジェット・ワーク画面が表示されている間だけ動かす
    func start() {
        guard !running else { return }
        running = true
        refreshAccess()
        if access == .unknown { requestAccess() } else { reload() }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func stop() {
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
    }

    func requestAccess() {
        guard Self.isSupported else {
            access = .unavailable
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let granted = (try? await self.store.requestFullAccessToEvents()) ?? false
            self.access = granted ? .granted : .denied
            self.reload()
        }
    }

    func reload(now: Date = Date()) {
        guard access == .granted else {
            events = []
            return
        }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 2, to: startOfDay) else { return }
        let predicate = store.predicateForEvents(withStart: startOfDay, end: end, calendars: nil)
        let found = store.events(matching: predicate)
        events = found
            .filter { $0.status != .canceled }
            .map { e in
                AgendaEvent(
                    id: "\(e.eventIdentifier ?? UUID().uuidString)-\(e.startDate.timeIntervalSince1970)",
                    title: (e.title ?? "").isEmpty ? "（題名なし）" : e.title,
                    start: e.startDate,
                    end: e.endDate,
                    isAllDay: e.isAllDay,
                    location: (e.location ?? "").isEmpty ? nil : e.location,
                    calendarName: e.calendar?.title ?? ""
                )
            }
            .sorted { $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start }
        lastUpdated = now
    }

    /// これからの予定（終わったものは除く）。終日の予定は今日の分だけ先頭に。
    func upcoming(now: Date = Date(), limit: Int = 6) -> [AgendaEvent] {
        let calendar = Calendar.current
        let todayAllDay = events.filter { $0.isAllDay && calendar.isDate($0.start, inSameDayAs: now) }
        let timed = events.filter { !$0.isAllDay && $0.end > now }
        return Array((todayAllDay + timed).prefix(limit))
    }

    /// 次に始まる（または今やっている）予定
    func next(now: Date = Date()) -> AgendaEvent? {
        events.first { !$0.isAllDay && $0.end > now }
    }
}
