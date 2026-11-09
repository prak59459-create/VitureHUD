import Foundation

public struct RouteProgress: Hashable, Sendable {
    /// 経路の始点からの進んだ距離（m）
    public var distanceAlongRoute: Double
    public var remainingDistance: Double
    /// 残り時間（秒）の推定
    public var remainingTime: Double
    public var nextStepIndex: Int?
    public var distanceToNextManeuver: Double?
    /// 経路からのずれ（m）
    public var offRouteDistance: Double
    public var isOffRoute: Bool
    public var hasArrived: Bool
    public var snappedCoordinate: GeoCoordinate
    /// 経路の進行方向（度）
    public var routeBearing: Double?

    public func eta(from now: Date) -> Date { now.addingTimeInterval(remainingTime) }
}

/// 現在地とルートから、残り距離・次の曲がり角・ルート逸脱を計算する。
/// MapKit にはターンバイターン案内エンジンがないため自前で実装する。
public struct RouteProgressEngine: Sendable {
    public struct Configuration: Hashable, Sendable {
        /// この距離以上離れたら逸脱候補（m）
        public var offRouteThreshold: Double = 35
        /// 逸脱候補がこの秒数続いたら逸脱と判定
        public var offRouteDuration: TimeInterval = 8
        /// 目的地までこの距離以内で到着（m）
        public var arrivalThreshold: Double = 20
        /// 測位精度がこれより悪いサンプルは逸脱判定に使わない（m）
        public var maxAccuracyForOffRoute: Double = 50
        /// 現在位置を探す範囲：前回位置から前後何点まで探すか
        public var searchWindow: Int = 60
        public init() {}
    }

    public let route: NavRoute
    public var configuration: Configuration
    private let cumulative: [Double]
    private let stepEndDistances: [Double]
    private var lastSegmentIndex: Int = 0
    private var offRouteSince: Date?
    public private(set) var hasArrived = false

    public init(route: NavRoute, configuration: Configuration = Configuration()) {
        self.route = route
        self.configuration = configuration
        var cum: [Double] = [0]
        let pts = route.polyline
        if pts.count > 1 {
            for i in 1..<pts.count { cum.append(cum[i - 1] + Geo.distance(pts[i - 1], pts[i])) }
        }
        self.cumulative = cum
        // 各ステップの終点が経路上のどの距離にあたるか
        var ends: [Double] = []
        var acc = 0.0
        for step in route.steps {
            acc += step.distance
            ends.append(acc)
        }
        // ステップ距離の合計と折れ線の長さの差を補正
        let total = cum.last ?? 0
        if let last = ends.last, last > 0, total > 0 {
            let factor = total / last
            ends = ends.map { $0 * factor }
        }
        self.stepEndDistances = ends
    }

    public var totalDistance: Double { cumulative.last ?? route.distance }

    public mutating func update(with sample: LocationSample) -> RouteProgress {
        let pts = route.polyline
        guard pts.count > 1 else {
            let remaining = route.destination.map { Geo.distance(sample.coordinate, $0) } ?? 0
            hasArrived = hasArrived || remaining <= configuration.arrivalThreshold
            return RouteProgress(
                distanceAlongRoute: 0, remainingDistance: remaining, remainingTime: remaining / route.averageSpeed,
                nextStepIndex: route.steps.isEmpty ? nil : 0, distanceToNextManeuver: remaining,
                offRouteDistance: 0, isOffRoute: false, hasArrived: hasArrived,
                snappedCoordinate: sample.coordinate, routeBearing: nil
            )
        }

        // 前回位置の近くを優先して探す（行き来する経路で後戻りしないように）
        let lower = max(0, lastSegmentIndex - 5)
        let upper = min(pts.count - 2, lastSegmentIndex + configuration.searchWindow)
        var best = (index: lastSegmentIndex, fraction: 0.0, distance: Double.greatestFiniteMagnitude)
        for i in lower...upper {
            let r = Geo.project(sample.coordinate, onSegment: pts[i], pts[i + 1])
            if r.distance < best.distance { best = (i, r.fraction, r.distance) }
        }
        // 近くで見つからなければ全体を探す（リルート後・GPS飛び対策）
        if best.distance > configuration.offRouteThreshold * 2 {
            for i in 0..<(pts.count - 1) {
                let r = Geo.project(sample.coordinate, onSegment: pts[i], pts[i + 1])
                if r.distance < best.distance { best = (i, r.fraction, r.distance) }
            }
        }
        lastSegmentIndex = best.index

        let segLen = cumulative[best.index + 1] - cumulative[best.index]
        let along = cumulative[best.index] + segLen * best.fraction
        let remaining = max(0, totalDistance - along)
        let snapped = Geo.interpolate(pts[best.index], pts[best.index + 1], fraction: best.fraction)
        let bearing = Geo.bearing(pts[best.index], pts[best.index + 1])

        // 逸脱判定（精度の悪いサンプルは使わない）
        var offRoute = false
        if sample.horizontalAccuracy <= configuration.maxAccuracyForOffRoute, best.distance > configuration.offRouteThreshold {
            if let since = offRouteSince {
                offRoute = sample.timestamp.timeIntervalSince(since) >= configuration.offRouteDuration
            } else {
                offRouteSince = sample.timestamp
            }
        } else {
            offRouteSince = nil
        }

        // 到着判定
        if let dest = route.destination {
            let toDest = Geo.distance(sample.coordinate, dest)
            if toDest <= configuration.arrivalThreshold || remaining <= configuration.arrivalThreshold * 0.5 {
                hasArrived = true
            }
        }

        // 次の曲がり角
        var nextIndex: Int?
        var toNext: Double?
        for (i, end) in stepEndDistances.enumerated() where end > along + 1 {
            nextIndex = i
            toNext = end - along
            break
        }
        if nextIndex == nil, !route.steps.isEmpty {
            nextIndex = route.steps.count - 1
            toNext = remaining
        }

        // 残り時間：実測速度が有効ならそれも加味する
        var speed = route.averageSpeed
        if sample.hasValidSpeed, sample.speed > 0.5 {
            speed = (speed + sample.speed) / 2
        }
        let remainingTime = speed > 0 ? remaining / speed : 0

        return RouteProgress(
            distanceAlongRoute: along,
            remainingDistance: remaining,
            remainingTime: remainingTime,
            nextStepIndex: nextIndex,
            distanceToNextManeuver: toNext,
            offRouteDistance: best.distance,
            isOffRoute: offRoute && !hasArrived,
            hasArrived: hasArrived,
            snappedCoordinate: snapped,
            routeBearing: bearing
        )
    }

    /// リルート要求を出した後に呼び、逸脱状態をリセットする。
    public mutating func resetOffRoute() {
        offRouteSince = nil
    }
}
