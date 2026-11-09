import Foundation
import Observation

/// 移動履歴（保存はユーザーが ON にした場合のみ）。
@MainActor
@Observable
final class HistoryModel {
    private(set) var trips: [TripRecord] = []
    private(set) var isRecording = false
    private(set) var currentDistance: Double = 0
    /// アプリを開いてからの移動距離（保存しない・ウィジェット表示用）
    private(set) var sessionDistance: Double = 0
    private(set) var visits: [VisitRecord] = []
    private(set) var detectionLog: [DetectionLogEntry] = []
    private(set) var usage = UsageStats()

    @ObservationIgnored private var visitDetector = VisitDetector()
    @ObservationIgnored private var usageSaveCounter = 0
    /// 訪問を記録したときの地名の取得（AppModel が設定）
    @ObservationIgnored var placeNameLookup: ((GeoCoordinate) async -> String?)?

    @ObservationIgnored private var recorder = TripRecorder(keepsPoints: false)
    @ObservationIgnored private var sessionRecorder = TripRecorder(keepsPoints: false)
    @ObservationIgnored private var store: JSONFileStore?
    @ObservationIgnored private var destinationName: String?
    @ObservationIgnored private var transport: TransportMode?

    func load(from store: JSONFileStore) {
        self.store = store
        trips = store.load([TripRecord].self, from: "trips") ?? []
        visits = store.load([VisitRecord].self, from: "visits") ?? []
        detectionLog = store.load([DetectionLogEntry].self, from: "detections") ?? []
        usage = store.load(UsageStats.self, from: "usage") ?? UsageStats()
        usage.launches += 1
        saveUsage(force: true)
        sessionRecorder.start(at: Date())
    }

    func handle(_ sample: LocationSample, settings: HistorySettings) {
        sessionRecorder.add(sample)
        sessionDistance = sessionRecorder.distance
        if settings.enabled && settings.recordsVisits, let visit = visitDetector.add(sample) {
            addVisit(visit, settings: settings)
        }
        guard isRecording else { return }
        recorder.add(sample)
        currentDistance = recorder.distance
    }

    func addDetections(_ count: Int, settings: HistorySettings) {
        guard isRecording, settings.recordsDetections else { return }
        recorder.addDetections(count)
    }

    func start(settings: HistorySettings, destination: String? = nil, transport: TransportMode? = nil) {
        guard settings.enabled, !isRecording else { return }
        recorder = TripRecorder(keepsPoints: settings.recordsRoutePoints)
        recorder.start(at: Date())
        destinationName = destination
        self.transport = transport
        currentDistance = 0
        isRecording = true
    }

    func stop(settings: HistorySettings) {
        guard isRecording else { return }
        isRecording = false
        if settings.enabled, let trip = recorder.finish(at: Date(), destinationName: destinationName, transport: transport) {
            trips.append(trip)
            trips = HistoryStats.pruned(trips, retentionDays: settings.retentionDays, now: Date())
            save()
        }
        currentDistance = 0
    }

    private func addVisit(_ visit: VisitRecord, settings: HistorySettings) {
        visits.append(visit)
        if settings.retentionDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(settings.retentionDays) * 86_400)
            visits.removeAll { $0.arrivedAt < cutoff }
        }
        if visits.count > 1000 { visits.removeFirst(visits.count - 1000) }
        try? store?.save(visits, as: "visits")
        let id = visit.id
        Task { [weak self] in
            guard let name = await self?.placeNameLookup?(visit.coordinate) else { return }
            guard let self, let i = self.visits.firstIndex(where: { $0.id == id }) else { return }
            self.visits[i].placeName = name
            try? self.store?.save(self.visits, as: "visits")
        }
    }

    func logDetection(label: DetectionLabel, hazard: HazardLevel, settings: HistorySettings) {
        guard settings.enabled, settings.recordsDetections else { return }
        // 同じ種類・同じ危険度は 10 秒に1回まで
        if let last = detectionLog.last, last.label == label, last.hazard == hazard, Date().timeIntervalSince(last.time) < 10 { return }
        detectionLog.append(DetectionLogEntry(time: Date(), label: label, hazard: hazard))
        if detectionLog.count > 2000 { detectionLog.removeFirst(detectionLog.count - 2000) }
        try? store?.save(detectionLog, as: "detections")
    }

    func recordHUD(seconds: Double, preset: String, settings: HistorySettings) {
        guard settings.recordsUsage else { return }
        usage.recordHUD(seconds: seconds, preset: preset)
        saveUsage()
    }

    func recordCommand(_ summary: String, viaVoice: Bool, settings: HistorySettings) {
        guard settings.recordsUsage else { return }
        usage.recordCommand(summary, viaVoice: viaVoice)
        saveUsage()
    }

    func recordNavigation(distance: Double, settings: HistorySettings) {
        guard settings.recordsUsage else { return }
        usage.recordNavigation(distance: distance)
        saveUsage(force: true)
    }

    private func saveUsage(force: Bool = false) {
        usageSaveCounter += 1
        if force || usageSaveCounter % 6 == 0 { try? store?.save(usage, as: "usage") }
    }

    func resetUsage() {
        usage = UsageStats()
        try? store?.save(usage, as: "usage")
    }

    func deleteVisits() {
        visits.removeAll()
        store?.delete("visits")
    }

    func deleteDetectionLog() {
        detectionLog.removeAll()
        store?.delete("detections")
    }

    func replaceVisits(with incoming: [VisitRecord]) {
        var merged = visits
        for v in incoming where !merged.contains(where: { $0.id == v.id }) { merged.append(v) }
        visits = merged.sorted { $0.arrivedAt < $1.arrivedAt }
        try? store?.save(visits, as: "visits")
    }

    func delete(_ ids: Set<UUID>) {
        trips.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteAll() {
        trips.removeAll()
        store?.delete("trips")
        deleteVisits()
        deleteDetectionLog()
        resetUsage()
    }

    func replace(with incoming: [TripRecord]) {
        var merged = trips
        for t in incoming where !merged.contains(where: { $0.id == t.id }) { merged.append(t) }
        trips = merged.sorted { $0.startedAt < $1.startedAt }
        save()
    }

    func applyRetention(_ settings: HistorySettings) {
        let pruned = HistoryStats.pruned(trips, retentionDays: settings.retentionDays, now: Date())
        if pruned.count != trips.count {
            trips = pruned
            save()
        }
    }

    private func save() {
        try? store?.save(trips, as: "trips")
    }
}
