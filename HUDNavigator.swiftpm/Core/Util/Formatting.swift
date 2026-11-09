import Foundation

/// 日本語の読み上げ・表示用フォーマット。
public enum HUDFormat {
    /// 表示用の距離（例: "350 m", "1.2 km"）
    public static func distance(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "--" }
        if meters < 1000 {
            let rounded = meters < 100 ? (meters / 5).rounded() * 5 : (meters / 10).rounded() * 10
            return "\(Int(rounded)) m"
        }
        let km = meters / 1000
        return km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
    }

    /// 読み上げ用の距離（例: "350メートル", "1.2キロメートル"）
    public static func spokenDistance(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "" }
        if meters < 1000 {
            let rounded: Int
            if meters < 30 {
                rounded = Int((meters / 5).rounded() * 5)
            } else if meters < 100 {
                rounded = Int((meters / 10).rounded() * 10)
            } else {
                rounded = Int((meters / 50).rounded() * 50)
            }
            return "\(max(rounded, 5))メートル"
        }
        let km = meters / 1000
        if km < 10 {
            let text = String(format: "%.1f", km)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + "キロメートル"
        }
        return "\(Int(km.rounded()))キロメートル"
    }

    /// 所要時間（例: "12分", "1時間5分"）
    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--" }
        if seconds < 60 { return "1分未満" }
        let totalMinutes = Int((seconds / 60).rounded())
        if totalMinutes < 60 { return "\(totalMinutes)分" }
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return m == 0 ? "\(h)時間" : "\(h)時間\(m)分"
    }

    /// 時刻（例: "14:05"）
    public static func clock(_ date: Date, seconds: Bool = false, use24Hour: Bool = true, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        var hour = c.hour ?? 0
        var prefix = ""
        if !use24Hour {
            prefix = hour < 12 ? "午前" : "午後"
            hour = hour % 12
            if hour == 0 { hour = 12 }
        }
        let base = String(format: "%d:%02d", hour, c.minute ?? 0)
        let withSeconds = seconds ? base + String(format: ":%02d", c.second ?? 0) : base
        return prefix + withSeconds
    }

    /// 読み上げ用の時刻（例: "14時5分"）
    public static func spokenClock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minute = c.minute ?? 0
        return minute == 0 ? "\(c.hour ?? 0)時" : "\(c.hour ?? 0)時\(minute)分"
    }

    /// 日付（例: "11月9日(月)"）
    public static func date(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        let w = weekdays[((c.weekday ?? 1) - 1 + 7) % 7]
        return "\(c.month ?? 1)月\(c.day ?? 1)日(\(w))"
    }

    public static func speed(_ metersPerSecond: Double, unit: SpeedUnit) -> String {
        guard metersPerSecond >= 0 else { return "--" }
        let v = unit.convert(metersPerSecond: metersPerSecond)
        return v < 10 ? String(format: "%.1f", v) : "\(Int(v.rounded()))"
    }

    public static func percent(_ fraction: Double) -> String {
        guard fraction >= 0 else { return "--" }
        return "\(Int((fraction * 100).rounded()))%"
    }
}
