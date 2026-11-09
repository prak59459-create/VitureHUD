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

    @ObservationIgnored private var recorder = TripRecorder(keepsPoints: false)
    @ObservationIgnored private var sessionRecorder = TripRecorder(keepsPoints: false)
    @ObservationIgnored private var store: JSONFileStore?
    @ObservationIgnored private var destinationName: String?
    @ObservationIgnored private var transport: TransportMode?

    func load(from store: JSONFileStore) {
        self.store = store
        trips = store.load([TripRecord].self, from: "trips") ?? []
        sessionRecorder.start(at: Date())
    }

    func handle(_ sample: LocationSample, settings: HistorySettings) {
        sessionRecorder.add(sample)
        sessionDistance = sessionRecorder.distance
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

    func delete(_ ids: Set<UUID>) {
        trips.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteAll() {
        trips.removeAll()
        store?.delete("trips")
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
