import Foundation

/// シミュレーション・テスト用のデモルート（公共の場所のみ。個人の位置は含めない）。
/// 皇居外苑（東京駅 丸の内側 → 和田倉噴水公園 → 皇居外苑の広場）付近の、おおまかな徒歩ルート。
public enum DemoRoutes {
    public static let tokyoStationName = "東京駅 丸の内中央口"
    public static let destinationName = "皇居外苑"

    /// 曲がり角の点（おおよその位置）。
    public static let waypoints: [GeoCoordinate] = [
        GeoCoordinate(latitude: 35.68124, longitude: 139.76603), // 東京駅 丸の内中央口前
        GeoCoordinate(latitude: 35.68180, longitude: 139.76330), // 行幸通りを西へ
        GeoCoordinate(latitude: 35.68232, longitude: 139.76070), // 和田倉門 交差点付近
        GeoCoordinate(latitude: 35.68110, longitude: 139.75940), // 南へ（右手に公園）
        GeoCoordinate(latitude: 35.67980, longitude: 139.75840), // 皇居外苑の広場
    ]

    /// 曲がり角の間を細かく補間した点列（GPS の更新に近い間隔）。
    public static func densePolyline(spacing: Double = 8) -> [GeoCoordinate] {
        var result: [GeoCoordinate] = []
        for i in 0..<(waypoints.count - 1) {
            let a = waypoints[i]
            let b = waypoints[i + 1]
            let d = Geo.distance(a, b)
            let n = max(1, Int(d / spacing))
            for k in 0..<n {
                result.append(Geo.interpolate(a, b, fraction: Double(k) / Double(n)))
            }
        }
        result.append(waypoints[waypoints.count - 1])
        return result
    }

    public static func walkingRoute() -> NavRoute {
        let pts = densePolyline()
        let legs = (0..<(waypoints.count - 1)).map { Geo.distance(waypoints[$0], waypoints[$0 + 1]) }
        let steps: [NavStep] = [
            NavStep(instruction: "行幸通りを西へ直進", distance: legs[0], endCoordinate: waypoints[1]),
            NavStep(instruction: "そのまま直進", distance: legs[1], endCoordinate: waypoints[2]),
            NavStep(instruction: "左折して内堀通りに入る", distance: legs[2], endCoordinate: waypoints[3]),
            NavStep(instruction: "目的地に到着", distance: legs[3], endCoordinate: waypoints[4]),
        ]
        let total = legs.reduce(0, +)
        return NavRoute(
            name: "デモ（皇居外苑まで）",
            transport: .walking,
            distance: total,
            expectedTravelTime: total / 1.3,
            polyline: pts,
            steps: steps,
            destinationName: destinationName
        )
    }

    public static var gpx: String {
        let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00:00 UTC（固定）
        let track = SimulatedTrack(points: densePolyline(), speed: 1.4)
        var samples: [LocationSample] = []
        var t: TimeInterval = 0
        while let s = track.sample(at: t, startDate: start) {
            samples.append(s)
            t += 2
        }
        return GPX.export(name: "デモ 皇居外苑", points: samples)
    }
}
