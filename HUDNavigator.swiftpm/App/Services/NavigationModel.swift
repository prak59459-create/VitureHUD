import Foundation
import Observation

/// ルート案内の状態（検索 → ルート比較 → 案内中 → 到着）。
@MainActor
@Observable
final class NavigationModel {
    enum Phase: Equatable {
        case idle
        case planning
        case choosing
        case guiding
        case arrived
    }

    private(set) var phase: Phase = .idle
    var destination: PlaceResult?
    var transport: TransportMode = .walking
    private(set) var routes: [NavRoute] = []
    var selectedRouteID: UUID?
    private(set) var activeRoute: NavRoute?
    private(set) var progress: RouteProgress?
    private(set) var startedAt: Date?
    private(set) var message: String?
    private(set) var isDemo = false
    private(set) var rerouteCount = 0

    @ObservationIgnored private var engine: RouteProgressEngine?
    @ObservationIgnored private var planner: GuidancePlanner?
    @ObservationIgnored private var lastReroute: Date?
    @ObservationIgnored private var lastSample: LocationSample?

    /// 読み上げ・通知（AppModel が設定）
    @ObservationIgnored var announce: ((GuidanceAnnouncement) -> Void)?
    @ObservationIgnored var onArrive: ((NavRoute) -> Void)?
    @ObservationIgnored var onStart: ((NavRoute) -> Void)?
    @ObservationIgnored var onStop: (() -> Void)?
    @ObservationIgnored var voiceSettings: (() -> VoiceSettings)?
    @ObservationIgnored var currentLocation: (() -> GeoCoordinate?)?

    var isGuiding: Bool { phase == .guiding }

    var selectedRoute: NavRoute? {
        routes.first { $0.id == selectedRouteID } ?? routes.first
    }

    var nextStep: NavStep? {
        guard let route = activeRoute, let i = progress?.nextStepIndex, i < route.steps.count else { return nil }
        return route.steps[i]
    }

    var eta: Date? { progress.map { $0.eta(from: Date()) } }

    // MARK: - ルート検索

    func plan(to place: PlaceResult, transport: TransportMode) async {
        destination = place
        self.transport = transport
        phase = .planning
        message = nil
        do {
            let result = try await RoutePlanner.routes(from: currentLocation?(), to: place, transport: transport)
            routes = result
            selectedRouteID = result.first?.id
            phase = .choosing
        } catch {
            routes = []
            phase = .idle
            message = error.localizedDescription
        }
    }

    func clearPlan() {
        guard !isGuiding else { return }
        routes = []
        destination = nil
        phase = .idle
        message = nil
    }

    // MARK: - 案内

    func start(route: NavRoute? = nil, demo: Bool = false) {
        guard let route = route ?? selectedRoute else {
            message = "先に目的地とルートを選んでください。"
            return
        }
        activeRoute = route
        isDemo = demo
        engine = RouteProgressEngine(route: route)
        let v = voiceSettings?() ?? VoiceSettings()
        var p = GuidancePlanner(transport: route.transport, frequency: v.frequency, announcesETA: v.announceETA)
        let now = Date()
        announce?(p.startAnnouncement(route: route, now: now))
        planner = p
        startedAt = now
        progress = nil
        rerouteCount = 0
        phase = .guiding
        message = nil
        onStart?(route)
        if let s = lastSample { handle(s) }
    }

    func startDemo() {
        let route = DemoRoutes.walkingRoute()
        destination = PlaceResult(name: route.destinationName, address: "デモ", coordinate: route.destination ?? DemoRoutes.waypoints.last!)
        routes = [route]
        selectedRouteID = route.id
        transport = .walking
        start(route: route, demo: true)
    }

    func stop() {
        guard phase == .guiding || phase == .arrived else { return }
        phase = .idle
        activeRoute = nil
        engine = nil
        planner = nil
        progress = nil
        isDemo = false
        routes = []
        onStop?()
    }

    func handle(_ sample: LocationSample) {
        lastSample = sample
        guard phase == .guiding, var engine, var planner, let route = activeRoute else { return }
        let p = engine.update(with: sample)
        progress = p
        for a in planner.announcements(for: p, route: route, now: sample.timestamp) {
            announce?(a)
        }
        self.engine = engine
        self.planner = planner
        if p.hasArrived {
            phase = .arrived
            onArrive?(route)
            return
        }
        if p.isOffRoute && !isDemo {
            reroute(from: sample.coordinate)
        }
    }

    private func reroute(from coordinate: GeoCoordinate) {
        if let last = lastReroute, Date().timeIntervalSince(last) < 15 { return }
        guard let destination else { return }
        lastReroute = Date()
        engine?.resetOffRoute()
        Task {
            do {
                let result = try await RoutePlanner.routes(from: coordinate, to: destination, transport: transport)
                guard let best = result.first, phase == .guiding else { return }
                activeRoute = best
                routes = result
                selectedRouteID = best.id
                engine = RouteProgressEngine(route: best)
                if var p = planner {
                    announce?(p.rerouteAnnouncement(route: best))
                    planner = p
                }
                rerouteCount += 1
            } catch {
                message = "ルートの再検索に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    func dismissArrival() {
        if phase == .arrived { stop() }
    }

    /// 曲がる方向の読み上げを繰り返す
    func repeatInstruction() -> String? {
        guard let step = nextStep, let distance = progress?.distanceToNextManeuver, let planner else { return nil }
        return planner.maneuverText(step: step, distance: distance)
    }
}
