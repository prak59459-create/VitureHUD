import Foundation

/// Google の「エンコードされたポリライン」を座標列に戻す。
public enum EncodedPolyline {
    public static func decode(_ encoded: String, precision: Double = 1e5) -> [GeoCoordinate] {
        var coordinates: [GeoCoordinate] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lon = 0
        func next() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }
        while index < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            coordinates.append(GeoCoordinate(latitude: Double(lat) / precision, longitude: Double(lon) / precision))
        }
        return coordinates
    }

    public static func encode(_ coordinates: [GeoCoordinate], precision: Double = 1e5) -> String {
        var result = ""
        var lastLat = 0
        var lastLon = 0
        func encodeValue(_ v: Int) {
            var value = v < 0 ? ~(v << 1) : (v << 1)
            while value >= 0x20 {
                result.append(Character(UnicodeScalar(UInt8((0x20 | (value & 0x1F)) + 63))))
                value >>= 5
            }
            result.append(Character(UnicodeScalar(UInt8(value + 63))))
        }
        for c in coordinates {
            let lat = Int((c.latitude * precision).rounded())
            let lon = Int((c.longitude * precision).rounded())
            encodeValue(lat - lastLat)
            encodeValue(lon - lastLon)
            lastLat = lat
            lastLon = lon
        }
        return result
    }
}

/// Google の場所（Places API の結果）
public struct GooglePlace: Hashable, Sendable {
    public var id: String
    public var name: String
    public var address: String
    public var coordinate: GeoCoordinate
    public var rating: Double?
    public var ratingCount: Int?
    public var openNow: Bool?
    public var openingHours: [String]
    public var category: String?
    public var phone: String?
    public var mapsURL: String?
}

/// Google Maps Platform の REST API（Places API (New)・Routes API）。
/// APIキーは X-Goog-Api-Key ヘッダーで送る。従量課金（無料枠あり）。
public enum GoogleMapsAPI {
    public static let placesTextURL = URL(string: "https://places.googleapis.com/v1/places:searchText")!
    public static let placesNearbyURL = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
    public static let routesURL = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!

    public static let placesFieldMask = "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.currentOpeningHours.openNow,places.regularOpeningHours.weekdayDescriptions,places.primaryTypeDisplayName,places.nationalPhoneNumber,places.googleMapsUri"

    public static let routesFieldMask = "routes.description,routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.warnings,routes.legs.steps.distanceMeters,routes.legs.steps.staticDuration,routes.legs.steps.polyline.encodedPolyline,routes.legs.steps.endLocation,routes.legs.steps.navigationInstruction,routes.legs.steps.travelMode,routes.legs.steps.transitDetails"

    // MARK: 検索

    public static func textSearchBody(query: String, near: GeoCoordinate?, radius: Double = 10_000) -> [String: Any] {
        var body: [String: Any] = ["textQuery": query, "languageCode": "ja", "regionCode": "JP", "maxResultCount": 15]
        if let c = near {
            body["locationBias"] = ["circle": ["center": ["latitude": c.latitude, "longitude": c.longitude], "radius": radius]]
        }
        return body
    }

    /// 周辺施設のカテゴリ → Places のタイプ
    public static func placeTypes(_ category: NearbyCategory) -> [String] {
        switch category {
        case .convenienceStore: return ["convenience_store"]
        case .restaurant: return ["restaurant"]
        case .cafe: return ["cafe"]
        case .station: return ["train_station", "subway_station", "transit_station"]
        case .busStop: return ["bus_stop", "bus_station"]
        case .parking: return ["parking"]
        case .restroom: return ["public_bathroom"]
        case .hospital: return ["hospital", "doctor"]
        case .pharmacy: return ["pharmacy", "drugstore"]
        case .sightseeing: return ["tourist_attraction", "museum", "park"]
        case .publicFacility: return ["city_hall", "library", "post_office", "local_government_office"]
        case .gasStation: return ["gas_station", "electric_vehicle_charging_station"]
        }
    }

    public static func nearbyBody(category: NearbyCategory, near c: GeoCoordinate, radius: Double = 1500) -> [String: Any] {
        [
            "includedTypes": placeTypes(category),
            "maxResultCount": 15,
            "languageCode": "ja",
            "regionCode": "JP",
            "rankPreference": "DISTANCE",
            "locationRestriction": ["circle": ["center": ["latitude": c.latitude, "longitude": c.longitude], "radius": radius]],
        ]
    }

    public static func parsePlaces(_ data: Data) throws -> [GooglePlace] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let places = json["places"] as? [[String: Any]] ?? []
        return places.compactMap { p in
            guard let loc = p["location"] as? [String: Any],
                  let lat = (loc["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (loc["longitude"] as? NSNumber)?.doubleValue else { return nil }
            let name = (p["displayName"] as? [String: Any])?["text"] as? String ?? "名称不明"
            let hours = (p["regularOpeningHours"] as? [String: Any])?["weekdayDescriptions"] as? [String] ?? []
            let openNow = (p["currentOpeningHours"] as? [String: Any])?["openNow"] as? Bool
            return GooglePlace(
                id: p["id"] as? String ?? UUID().uuidString,
                name: name,
                address: p["formattedAddress"] as? String ?? "",
                coordinate: GeoCoordinate(latitude: lat, longitude: lon),
                rating: (p["rating"] as? NSNumber)?.doubleValue,
                ratingCount: (p["userRatingCount"] as? NSNumber)?.intValue,
                openNow: openNow,
                openingHours: hours,
                category: (p["primaryTypeDisplayName"] as? [String: Any])?["text"] as? String,
                phone: p["nationalPhoneNumber"] as? String,
                mapsURL: p["googleMapsUri"] as? String
            )
        }
    }

    // MARK: ルート

    public static func travelMode(_ t: TransportMode) -> String {
        switch t {
        case .walking: return "WALK"
        case .automobile: return "DRIVE"
        case .transit: return "TRANSIT"
        }
    }

    public static func routesBody(from: GeoCoordinate, to: GeoCoordinate, transport: TransportMode, departure: Date? = nil) -> [String: Any] {
        func waypoint(_ c: GeoCoordinate) -> [String: Any] {
            ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]
        }
        var body: [String: Any] = [
            "origin": waypoint(from),
            "destination": waypoint(to),
            "travelMode": travelMode(transport),
            "languageCode": "ja",
            "regionCode": "JP",
            "units": "METRIC",
            "computeAlternativeRoutes": transport != .transit,
        ]
        if transport == .automobile { body["routingPreference"] = "TRAFFIC_AWARE" }
        if transport == .transit, let d = departure {
            body["departureTime"] = ISO8601DateFormatter().string(from: d)
        }
        return body
    }

    /// "123s" → 123
    public static func seconds(_ text: String?) -> Double {
        guard let t = text, t.hasSuffix("s") else { return 0 }
        return Double(t.dropLast()) ?? 0
    }

    /// Google の maneuver → 曲がる方向
    public static func maneuver(_ value: String?) -> ManeuverKind? {
        switch value {
        case "TURN_LEFT": return .left
        case "TURN_RIGHT": return .right
        case "TURN_SLIGHT_LEFT": return .slightLeft
        case "TURN_SLIGHT_RIGHT": return .slightRight
        case "TURN_SHARP_LEFT": return .sharpLeft
        case "TURN_SHARP_RIGHT": return .sharpRight
        case "UTURN_LEFT", "UTURN_RIGHT": return .uTurn
        case "STRAIGHT", "NAME_CHANGE": return .straight
        case "RAMP_LEFT", "FORK_LEFT": return .keepLeft
        case "RAMP_RIGHT", "FORK_RIGHT": return .keepRight
        case "MERGE": return .merge
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT", "ROUNDABOUT_CLOCKWISE", "ROUNDABOUT_COUNTERCLOCKWISE": return .roundabout
        case "DEPART": return .depart
        default: return nil
        }
    }

    public static func parseRoutes(_ data: Data, transport: TransportMode, destinationName: String) throws -> [NavRoute] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let routes = json["routes"] as? [[String: Any]] ?? []
        return routes.map { r in
            let polyline = EncodedPolyline.decode(((r["polyline"] as? [String: Any])?["encodedPolyline"] as? String) ?? "")
            var steps: [NavStep] = []
            for leg in r["legs"] as? [[String: Any]] ?? [] {
                for s in leg["steps"] as? [[String: Any]] ?? [] {
                    let nav = s["navigationInstruction"] as? [String: Any]
                    var text = (nav?["instructions"] as? String) ?? ""
                    if let transit = s["transitDetails"] as? [String: Any] {
                        text = transitText(transit, fallback: text)
                    }
                    let distance = (s["distanceMeters"] as? NSNumber)?.doubleValue ?? 0
                    let end: GeoCoordinate
                    if let e = (s["endLocation"] as? [String: Any])?["latLng"] as? [String: Any],
                       let lat = (e["latitude"] as? NSNumber)?.doubleValue, let lon = (e["longitude"] as? NSNumber)?.doubleValue {
                        end = GeoCoordinate(latitude: lat, longitude: lon)
                    } else {
                        let stepLine = EncodedPolyline.decode(((s["polyline"] as? [String: Any])?["encodedPolyline"] as? String) ?? "")
                        end = stepLine.last ?? polyline.last ?? GeoCoordinate(latitude: 0, longitude: 0)
                    }
                    let kind = maneuver(nav?["maneuver"] as? String) ?? ManeuverKind.classify(text)
                    steps.append(NavStep(instruction: text.isEmpty ? "直進" : text, distance: distance, endCoordinate: end, maneuver: kind))
                }
            }
            if let dest = polyline.last {
                steps.append(NavStep(instruction: "目的地に到着", distance: 0, endCoordinate: dest, maneuver: .arrive))
            }
            let warnings = r["warnings"] as? [String] ?? []
            return NavRoute(
                name: (r["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Google ルート",
                transport: transport,
                distance: (r["distanceMeters"] as? NSNumber)?.doubleValue ?? Geo.pathLength(polyline),
                expectedTravelTime: seconds(r["duration"] as? String),
                polyline: polyline,
                steps: steps,
                destinationName: destinationName,
                advisoryNotices: warnings
            )
        }
    }

    /// 乗り換え案内の1区間を文章にする（例: 「JR山手線 品川方面 東京→有楽町（1駅）」）
    static func transitText(_ t: [String: Any], fallback: String) -> String {
        let line = t["transitLine"] as? [String: Any]
        let lineName = (line?["nameShort"] as? String) ?? (line?["name"] as? String) ?? ""
        let headsign = t["headsign"] as? String
        let stops = t["stopDetails"] as? [String: Any]
        let from = (stops?["departureStop"] as? [String: Any])?["name"] as? String
        let to = (stops?["arrivalStop"] as? [String: Any])?["name"] as? String
        let count = (t["stopCount"] as? NSNumber)?.intValue
        var parts: [String] = []
        if !lineName.isEmpty { parts.append(lineName) }
        if let h = headsign { parts.append("\(h)方面") }
        if let f = from, let to = to { parts.append("\(f)→\(to)") }
        if let c = count { parts.append("（\(c)駅）") }
        let text = parts.joined(separator: " ")
        return text.isEmpty ? fallback : text
    }
}
