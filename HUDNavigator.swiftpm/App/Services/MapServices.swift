import Foundation
import MapKit
import Observation

/// 目的地の候補
struct PlaceResult: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var address: String
    var coordinate: GeoCoordinate
    var category: String?
    var phone: String?
    var url: URL?
    var distance: Double?

    static func == (lhs: PlaceResult, rhs: PlaceResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(id: UUID = UUID(), name: String, address: String, coordinate: GeoCoordinate, category: String? = nil, phone: String? = nil, url: URL? = nil, distance: Double? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.category = category
        self.phone = phone
        self.url = url
        self.distance = distance
    }

    init(mapItem: MKMapItem, from origin: GeoCoordinate?) {
        let coordinate = GeoCoordinate(mapItem.placemark.coordinate)
        let pm = mapItem.placemark
        let address = [pm.administrativeArea, pm.locality, pm.thoroughfare, pm.subThoroughfare].compactMap { $0 }.joined()
        self.init(
            name: mapItem.name ?? "名称不明",
            address: address,
            coordinate: coordinate,
            category: mapItem.pointOfInterestCategory.map(PlaceResult.categoryName),
            phone: mapItem.phoneNumber,
            url: mapItem.url,
            distance: origin.map { Geo.distance($0, coordinate) }
        )
    }

    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clCoordinate))
        item.name = name
        return item
    }

    static func categoryName(_ c: MKPointOfInterestCategory) -> String {
        switch c {
        case .restaurant: return "飲食店"
        case .cafe: return "カフェ"
        case .publicTransport: return "公共交通"
        case .parking: return "駐車場"
        case .restroom: return "トイレ"
        case .hospital: return "病院"
        case .pharmacy: return "薬局"
        case .gasStation: return "ガソリンスタンド"
        case .museum: return "博物館"
        case .park: return "公園"
        case .store: return "店舗"
        case .foodMarket: return "食料品店"
        case .library: return "図書館"
        case .police: return "警察"
        case .postOffice: return "郵便局"
        default: return "施設"
        }
    }
}

extension NearbyCategory {
    var mapKitCategories: [MKPointOfInterestCategory]? {
        switch self {
        case .convenienceStore: return [.store, .foodMarket]
        case .restaurant: return [.restaurant, .bakery]
        case .cafe: return [.cafe]
        case .station, .busStop: return [.publicTransport]
        case .parking: return [.parking]
        case .restroom: return [.restroom]
        case .hospital: return [.hospital]
        case .pharmacy: return [.pharmacy]
        case .sightseeing: return [.museum, .park, .nationalPark, .landmark]
        case .publicFacility: return [.library, .postOffice, .police, .fireStation, .school]
        case .gasStation: return [.gasStation, .evCharger]
        }
    }
}

/// 入力中の文字から候補を出す（MKLocalSearchCompleter）。
@MainActor
@Observable
final class SearchCompleterModel {
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private(set) var query = ""

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private let delegate = CompleterDelegate()

    init() {
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = delegate
        delegate.owner = self
    }

    func update(query: String, near coordinate: GeoCoordinate?) {
        self.query = query
        if let coordinate {
            completer.region = MKCoordinateRegion(center: coordinate.clCoordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestions = []
        } else {
            completer.queryFragment = query
        }
    }

    fileprivate func set(_ results: [MKLocalSearchCompletion]) {
        suggestions = Array(results.prefix(8))
    }
}

private final class CompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    weak var owner: SearchCompleterModel?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor [weak self] in self?.owner?.set(results) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

enum MapSearch {
    static func search(_ query: String, near coordinate: GeoCoordinate?) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let coordinate {
            request.region = MKCoordinateRegion(center: coordinate.clCoordinate, latitudinalMeters: 10_000, longitudinalMeters: 10_000)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { PlaceResult(mapItem: $0, from: coordinate) }
            .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    static func search(completion: MKLocalSearchCompletion, near coordinate: GeoCoordinate?) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { PlaceResult(mapItem: $0, from: coordinate) }
    }

    static func nearby(_ category: NearbyCategory, near coordinate: GeoCoordinate) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.searchQuery
        request.region = MKCoordinateRegion(center: coordinate.clCoordinate, latitudinalMeters: 2_000, longitudinalMeters: 2_000)
        request.resultTypes = .pointOfInterest
        if let cats = category.mapKitCategories {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: cats)
        }
        var results = try await MKLocalSearch(request: request).start().mapItems.map { PlaceResult(mapItem: $0, from: coordinate) }
        if results.isEmpty, category.mapKitCategories != nil {
            // カテゴリで絞って見つからなければ、文字検索だけで探し直す
            let loose = MKLocalSearch.Request()
            loose.naturalLanguageQuery = category.searchQuery
            loose.region = request.region
            results = try await MKLocalSearch(request: loose).start().mapItems.map { PlaceResult(mapItem: $0, from: coordinate) }
        }
        return results.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    static func placeName(for coordinate: GeoCoordinate) async -> String? {
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), preferredLocale: Locale(identifier: "ja_JP"))
        guard let p = placemarks?.first else { return nil }
        let text = [p.name, p.locality].compactMap { $0 }.first
        return text
    }
}

/// MapKit でルートを計算し、Core の NavRoute に変換する。
enum RoutePlanner {
    enum PlannerError: LocalizedError {
        case noRoute
        case transitStepsUnavailable(eta: TimeInterval?)

        var errorDescription: String? {
            switch self {
            case .noRoute: return "ルートが見つかりませんでした。"
            case .transitStepsUnavailable(let eta):
                let base = "公共交通機関の詳しい経路は Apple マップのアプリで確認してください（MapKit では到着予想時刻のみ取得できます）。"
                if let eta { return "所要時間の目安：約\(HUDFormat.duration(eta))。" + base }
                return base
            }
        }
    }

    static func routes(from origin: GeoCoordinate?, to destination: PlaceResult, transport: TransportMode) async throws -> [NavRoute] {
        let request = MKDirections.Request()
        if let origin {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.clCoordinate))
        } else {
            request.source = MKMapItem.forCurrentLocation()
        }
        request.destination = destination.mapItem
        request.requestsAlternateRoutes = true
        switch transport {
        case .walking: request.transportType = .walking
        case .automobile: request.transportType = .automobile
        case .transit:
            request.transportType = .transit
            let eta = try? await MKDirections(request: request).calculateETA()
            throw PlannerError.transitStepsUnavailable(eta: eta?.expectedTravelTime)
        }
        let response = try await MKDirections(request: request).calculate()
        guard !response.routes.isEmpty else { throw PlannerError.noRoute }
        return response.routes.map { convert($0, transport: transport, destinationName: destination.name) }
    }

    static func convert(_ route: MKRoute, transport: TransportMode, destinationName: String) -> NavRoute {
        let polyline = coordinates(route.polyline)
        var steps: [NavStep] = []
        for step in route.steps {
            let end = coordinates(step.polyline).last.map { $0 } ?? polyline.last ?? GeoCoordinate(latitude: 0, longitude: 0)
            let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty && step.distance < 1 { continue }
            steps.append(NavStep(instruction: text.isEmpty ? "直進" : text, distance: step.distance, endCoordinate: end))
        }
        if let last = steps.last, last.maneuver != .arrive, let dest = polyline.last {
            steps.append(NavStep(instruction: "目的地に到着", distance: 0, endCoordinate: dest, maneuver: .arrive))
        }
        return NavRoute(
            name: route.name.isEmpty ? "ルート" : route.name,
            transport: transport,
            distance: route.distance,
            expectedTravelTime: route.expectedTravelTime,
            polyline: polyline,
            steps: steps,
            destinationName: destinationName,
            advisoryNotices: route.advisoryNotices
        )
    }

    static func coordinates(_ polyline: MKPolyline) -> [GeoCoordinate] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords.map(GeoCoordinate.init)
    }

    /// Apple マップのアプリで開く（公共交通など MapKit で経路が取れない場合）
    static func openInMaps(_ destination: PlaceResult, transport: TransportMode) {
        let mode: String
        switch transport {
        case .walking: mode = MKLaunchOptionsDirectionsModeWalking
        case .automobile: mode = MKLaunchOptionsDirectionsModeDriving
        case .transit: mode = MKLaunchOptionsDirectionsModeTransit
        }
        destination.mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }
}
