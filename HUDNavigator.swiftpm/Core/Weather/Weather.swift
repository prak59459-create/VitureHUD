import Foundation

/// 1時間ごとの予報
public struct HourlyForecast: Codable, Hashable, Sendable {
    public var time: Date
    public var temperature: Double?
    public var precipitationProbability: Double?
    public var weatherCode: Int?

    public init(time: Date, temperature: Double? = nil, precipitationProbability: Double? = nil, weatherCode: Int? = nil) {
        self.time = time
        self.temperature = temperature
        self.precipitationProbability = precipitationProbability
        self.weatherCode = weatherCode
    }

    public var symbolName: String { weatherCode.map { WeatherCode.symbol($0, isDay: true) } ?? "questionmark.circle" }
}

/// 天気・環境情報。取得できない値は nil（架空の値は表示しない）。
public struct WeatherSnapshot: Codable, Hashable, Sendable {
    public var temperature: Double?
    public var apparentTemperature: Double?
    public var humidity: Double?
    public var precipitation: Double?
    public var precipitationProbability: Double?
    public var weatherCode: Int?
    public var windSpeed: Double?
    public var windDirection: Double?
    public var uvIndex: Double?
    public var pm25: Double?
    public var pm10: Double?
    public var europeanAQI: Double?
    public var isDay: Bool?
    /// データの時刻（提供元の値）
    public var observationTime: Date?
    /// アプリが取得した時刻
    public var fetchedAt: Date
    public var source: String
    public var sourceURL: String
    /// これから先の1時間ごとの予報（最大12時間）
    public var hourly: [HourlyForecast] = []

    public init(fetchedAt: Date, source: String = "Open-Meteo.com", sourceURL: String = "https://open-meteo.com/") {
        self.fetchedAt = fetchedAt
        self.source = source
        self.sourceURL = sourceURL
    }

    /// 指定時間内に、降水確率が閾値以上になる最初の時間帯
    public func rainExpected(withinHours hours: Double, threshold: Double, after now: Date) -> HourlyForecast? {
        hourly.first { h in
            h.time >= now.addingTimeInterval(-1800) && h.time <= now.addingTimeInterval(hours * 3600)
                && (h.precipitationProbability ?? 0) >= threshold
        }
    }

    public var conditionText: String { weatherCode.map(WeatherCode.description) ?? "不明" }
    public var symbolName: String { weatherCode.map { WeatherCode.symbol($0, isDay: isDay ?? true) } ?? "questionmark.circle" }

    public var windDirectionName: String? { windDirection.map { Geo.cardinalName($0) } }

    public func isStale(at now: Date, maxAge: TimeInterval = 3600) -> Bool { now.timeIntervalSince(fetchedAt) > maxAge }

    public var spokenSummary: String {
        var parts = ["現在の天気は\(conditionText)"]
        if let t = temperature { parts.append("気温\(Int(t.rounded()))度") }
        if let p = precipitationProbability { parts.append("降水確率\(Int(p.rounded()))パーセント") }
        if let w = windSpeed, let dir = windDirectionName { parts.append("\(dir)の風\(String(format: "%.0f", w))メートル") }
        return parts.joined(separator: "、") + "です。出典はOpen-Meteoです。"
    }

    /// 大気質の目安（European AQI）
    public var airQualityText: String? {
        guard let aqi = europeanAQI else { return nil }
        switch aqi {
        case ..<20: return "良い"
        case ..<40: return "普通"
        case ..<60: return "やや悪い"
        case ..<80: return "悪い"
        case ..<100: return "非常に悪い"
        default: return "極めて悪い"
        }
    }
}

/// WMO 天気コード
public enum WeatherCode {
    public static func description(_ code: Int) -> String {
        switch code {
        case 0: return "快晴"
        case 1: return "晴れ"
        case 2: return "一部くもり"
        case 3: return "くもり"
        case 45, 48: return "霧"
        case 51, 53, 55: return "霧雨"
        case 56, 57: return "着氷性の霧雨"
        case 61: return "小雨"
        case 63: return "雨"
        case 65: return "強い雨"
        case 66, 67: return "着氷性の雨"
        case 71: return "小雪"
        case 73: return "雪"
        case 75: return "大雪"
        case 77: return "霧雪"
        case 80: return "にわか雨"
        case 81: return "強いにわか雨"
        case 82: return "激しいにわか雨"
        case 85, 86: return "にわか雪"
        case 95: return "雷雨"
        case 96, 99: return "ひょうを伴う雷雨"
        default: return "不明"
        }
    }

    public static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0, 1: return isDay ? "sun.max" : "moon.stars"
        case 2: return isDay ? "cloud.sun" : "cloud.moon"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55, 56, 57: return "cloud.drizzle"
        case 61, 63, 66, 80, 81: return "cloud.rain"
        case 65, 67, 82: return "cloud.heavyrain"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow"
        case 95, 96, 99: return "cloud.bolt.rain"
        default: return "questionmark.circle"
        }
    }
}

/// Open-Meteo（非商用は無料・APIキー不要、データは CC BY 4.0）。
public enum OpenMeteo {
    public static func forecastURL(for c: GeoCoordinate) -> URL? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        comps?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", c.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", c.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,wind_direction_10m,is_day,uv_index"),
            URLQueryItem(name: "hourly", value: "precipitation_probability,temperature_2m,weather_code"),
            URLQueryItem(name: "forecast_hours", value: "12"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return comps?.url
    }

    public static func airQualityURL(for c: GeoCoordinate) -> URL? {
        var comps = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        comps?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", c.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", c.longitude)),
            URLQueryItem(name: "current", value: "pm2_5,pm10,european_aqi,uv_index"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return comps?.url
    }

    struct ForecastResponse: Decodable {
        struct Current: Decodable {
            var time: String?
            var temperature_2m: Double?
            var apparent_temperature: Double?
            var relative_humidity_2m: Double?
            var precipitation: Double?
            var weather_code: Int?
            var wind_speed_10m: Double?
            var wind_direction_10m: Double?
            var is_day: Int?
            var uv_index: Double?
        }
        struct Hourly: Decodable {
            var time: [String]?
            var precipitation_probability: [Double?]?
            var temperature_2m: [Double?]?
            var weather_code: [Int?]?
        }
        var current: Current?
        var hourly: Hourly?
        var utc_offset_seconds: Int?
    }

    struct AirResponse: Decodable {
        struct Current: Decodable {
            var pm2_5: Double?
            var pm10: Double?
            var european_aqi: Double?
            var uv_index: Double?
        }
        var current: Current?
    }

    public static func parseForecast(_ data: Data, fetchedAt: Date) throws -> WeatherSnapshot {
        let r = try JSONDecoder().decode(ForecastResponse.self, from: data)
        var s = WeatherSnapshot(fetchedAt: fetchedAt)
        if let c = r.current {
            s.temperature = c.temperature_2m
            s.apparentTemperature = c.apparent_temperature
            s.humidity = c.relative_humidity_2m
            s.precipitation = c.precipitation
            s.weatherCode = c.weather_code
            s.windSpeed = c.wind_speed_10m
            s.windDirection = c.wind_direction_10m
            s.isDay = c.is_day.map { $0 == 1 }
            s.uvIndex = c.uv_index
            if let t = c.time { s.observationTime = parseLocalTime(t, utcOffset: r.utc_offset_seconds ?? 0) }
        }
        if let probs = r.hourly?.precipitation_probability {
            s.precipitationProbability = probs.compactMap { $0 }.first
        }
        if let h = r.hourly, let times = h.time {
            let offset = r.utc_offset_seconds ?? 0
            s.hourly = times.enumerated().compactMap { i, t in
                guard let date = parseLocalTime(t, utcOffset: offset) else { return nil }
                return HourlyForecast(
                    time: date,
                    temperature: h.temperature_2m.flatMap { i < $0.count ? $0[i] : nil },
                    precipitationProbability: h.precipitation_probability.flatMap { i < $0.count ? $0[i] : nil },
                    weatherCode: h.weather_code.flatMap { i < $0.count ? $0[i] : nil }
                )
            }
        }
        return s
    }

    public static func mergeAirQuality(_ data: Data, into snapshot: WeatherSnapshot) throws -> WeatherSnapshot {
        let r = try JSONDecoder().decode(AirResponse.self, from: data)
        var s = snapshot
        s.pm25 = r.current?.pm2_5
        s.pm10 = r.current?.pm10
        s.europeanAQI = r.current?.european_aqi
        if s.uvIndex == nil { s.uvIndex = r.current?.uv_index }
        return s
    }

    /// "2026-11-09T14:00"（現地時刻）を Date に
    static func parseLocalTime(_ text: String, utcOffset: Int) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: utcOffset)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: text)
    }
}
