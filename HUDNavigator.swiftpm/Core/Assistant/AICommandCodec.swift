import Foundation

/// クラウド AI に「アプリの操作」を頼むためのやり取り。
/// AI には使えるコマンドの一覧（ホワイトリスト）を渡し、JSON で返してもらう。
/// 一覧にないコマンド・不正な値は無視する（AI に任意の操作をさせない）。
public enum AICommandCodec {
    public struct Plan: Equatable, Sendable {
        public var commands: [AppCommand]
        public var reply: String
    }

    /// 1回の依頼で実行するコマンドの上限
    public static let maxCommands = 4

    /// AI に渡す説明（システムプロンプトの一部）
    public static var catalog: String {
        let presets = BuiltInContent.presetAliases.keys.sorted().joined(separator: ", ")
        let themes = BuiltInContent.themeAliases.keys.sorted().joined(separator: ", ")
        let widgets = WidgetKind.allCases.map(\.rawValue).joined(separator: ", ")
        let categories = NearbyCategory.allCases.map(\.rawValue).joined(separator: ", ")
        return """
        ユーザーの依頼がアプリの操作なら、次の JSON だけを返してください（説明文は reply に入れる）：
        {"commands":[{"name":"コマンド名","value":"値"}],"reply":"ユーザーへの短い返事"}
        操作でない質問なら {"commands":[],"reply":"答え"} を返してください。
        使えるコマンド（name / value）:
        - setBackground / black | camera
        - applyPreset / \(presets)
        - applyTheme / \(themes)
        - showWidget, hideWidget / \(widgets)
        - mapZoom / in | out
        - setMap3D / true | false
        - navigate / 目的地の名前
        - stopNavigation / （値なし）
        - searchNearby / \(categories)
        - search / 検索語
        - setVoiceGuidance, setDetection, setHazardAlerts, setNightDim, setStereo3D, setRecording, setHeadLock, setGlanceMode, setDepth / true | false
        - adjustHUDScale, adjustTextSize, adjustBrightness / up | down
        - moveHUD / up | down | left | right
        - cyclePreset / 1 | -1
        - nextTheme, autoArrange, repeatGuidance, startHUD, stopHUD, syncNow, connectHeartRate, recenterHead, measureDistance / （値なし）
        - status / time | date | battery | speed | eta | remainingDistance | weather | location | heading
        コマンドは最大\(maxCommands)個まで。安全のため、運転に関わる操作の依頼には応じないでください。
        """
    }

    /// AI の返答から JSON を取り出してコマンドに変換する。
    public static func decode(_ text: String) -> Plan {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Plan(commands: [], reply: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let reply = (object["reply"] as? String) ?? ""
        let raw = object["commands"] as? [[String: Any]] ?? []
        var commands: [AppCommand] = []
        for item in raw.prefix(maxCommands) {
            guard let name = item["name"] as? String else { continue }
            let value: String
            if let s = item["value"] as? String { value = s }
            else if let b = item["value"] as? Bool { value = b ? "true" : "false" }
            else if let n = item["value"] as? NSNumber { value = n.stringValue }
            else { value = "" }
            if let c = command(name: name, value: value) { commands.append(c) }
        }
        return Plan(commands: commands, reply: reply)
    }

    static func bool(_ v: String) -> Bool? {
        switch v.lowercased() {
        case "true", "on", "1", "yes": return true
        case "false", "off", "0", "no": return false
        default: return nil
        }
    }

    static func adjust(_ v: String) -> AdjustDirection? {
        switch v.lowercased() {
        case "up", "in", "+", "increase": return .up
        case "down", "out", "-", "decrease": return .down
        default: return nil
        }
    }

    public static func command(name: String, value: String) -> AppCommand? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "setBackground": return BackgroundMode(rawValue: v.lowercased()).map(AppCommand.setBackground)
        case "applyPreset": return BuiltInContent.presetAliases[v] != nil ? .applyPreset(key: v) : nil
        case "applyTheme": return BuiltInContent.themeAliases[v] != nil ? .applyTheme(key: v) : nil
        case "showWidget": return WidgetKind(rawValue: v).map(AppCommand.showWidget)
        case "hideWidget": return WidgetKind(rawValue: v).map(AppCommand.hideWidget)
        case "mapZoom": return adjust(v).map { .mapZoom($0 == .up ? .zoomIn : .zoomOut) }
        case "setMap3D": return bool(v).map(AppCommand.setMap3D)
        case "navigate": return v.isEmpty || v.count > 60 ? nil : .navigate(to: v)
        case "stopNavigation": return .stopNavigation
        case "searchNearby": return NearbyCategory(rawValue: v).map(AppCommand.searchNearby)
        case "search": return v.isEmpty || v.count > 60 ? nil : .search(v)
        case "setVoiceGuidance": return bool(v).map(AppCommand.setVoiceGuidance)
        case "setDetection": return bool(v).map(AppCommand.setDetection)
        case "setHazardAlerts": return bool(v).map(AppCommand.setHazardAlerts)
        case "setNightDim": return bool(v).map(AppCommand.setNightDim)
        case "setStereo3D": return bool(v).map(AppCommand.setStereo3D)
        case "setRecording": return bool(v).map(AppCommand.setRecording)
        case "adjustHUDScale": return adjust(v).map(AppCommand.adjustHUDScale)
        case "adjustTextSize": return adjust(v).map(AppCommand.adjustTextSize)
        case "adjustBrightness": return adjust(v).map(AppCommand.adjustBrightness)
        case "moveHUD": return MoveDirection(rawValue: v.lowercased()).map(AppCommand.moveHUD)
        case "cyclePreset": return Int(v).map { .cyclePreset($0 >= 0 ? 1 : -1) }
        case "nextTheme": return .nextTheme
        case "autoArrange": return .autoArrange
        case "repeatGuidance": return .repeatGuidance
        case "startHUD": return .startHUD
        case "stopHUD": return .stopHUD
        case "syncNow": return .syncNow
        case "connectHeartRate": return .connectHeartRate
        case "recenterHead": return .recenterHead
        case "setHeadLock": return bool(v).map(AppCommand.setHeadLock)
        case "setGlanceMode": return bool(v).map(AppCommand.setGlanceMode)
        case "setDepth": return bool(v).map(AppCommand.setDepth)
        case "measureDistance": return .measureDistance
        case "status": return StatusTopic(rawValue: v).map(AppCommand.status)
        default: return nil
        }
    }
}

/// URL（hudnavigator://…）からの操作。ウィジェット・ショートカット・他アプリから呼ぶ。
public enum DeepLink {
    public static let scheme = "hudnavigator"

    /// 例: hudnavigator://hud/start, hudnavigator://background/toggle, hudnavigator://preset/walkNav,
    ///     hudnavigator://navigate?to=東京駅, hudnavigator://nearby/cafe, hudnavigator://voice
    public static func command(from url: URL) -> AppCommand? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/").map(String.init)
        let first = parts.first ?? ""
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { query.first { $0.name == name }?.value }
        switch host {
        case "hud":
            switch first {
            case "start", "": return .startHUD
            case "stop": return .stopHUD
            case "edit": return .open(.hudEditor)
            default: return nil
            }
        case "background":
            if first == "toggle" || first.isEmpty { return .toggleBackground }
            return BackgroundMode(rawValue: first).map(AppCommand.setBackground)
        case "preset":
            if first == "next" { return .cyclePreset(1) }
            if first == "previous" { return .cyclePreset(-1) }
            return first.isEmpty ? nil : .applyPreset(key: first)
        case "navigate":
            if let to = q("to"), !to.isEmpty { return .navigate(to: to) }
            if first == "stop" { return .stopNavigation }
            return .open(.navigation)
        case "nearby":
            return NearbyCategory(rawValue: first).map(AppCommand.searchNearby)
        case "voice", "assistant":
            return .open(.assistant)
        case "open":
            return AppScreen(rawValue: first).map(AppCommand.open)
        case "depth":
            if first == "on" || first.isEmpty { return .setDepth(true) }
            if first == "off" { return .setDepth(false) }
            if first == "measure" { return .measureDistance }
            return nil
        case "scan":
            return .open(.scan3D)
        case "head":
            switch first {
            case "recenter", "": return .recenterHead
            case "lock": return .setHeadLock(true)
            case "unlock": return .setHeadLock(false)
            case "glance": return .setGlanceMode(true)
            case "full": return .setGlanceMode(false)
            default: return nil
            }
        case "guidance":
            if first == "on" { return .setVoiceGuidance(true) }
            if first == "off" { return .setVoiceGuidance(false) }
            return .repeatGuidance
        default:
            return nil
        }
    }

    public static func url(_ path: String) -> URL? { URL(string: "\(scheme)://\(path)") }
}

/// テキストウィジェットのテンプレート（例: "{time} 電池{battery} {speed}km/h"）
public enum TemplateRenderer {
    public static let tokens: [(token: String, description: String)] = [
        ("{time}", "時刻"),
        ("{date}", "日付"),
        ("{battery}", "電池残量"),
        ("{speed}", "速度（km/h）"),
        ("{heading}", "方角"),
        ("{place}", "現在地の地名"),
        ("{eta}", "到着予定時刻"),
        ("{remaining}", "残り距離"),
        ("{next}", "次の曲がり角"),
        ("{temp}", "気温"),
        ("{weather}", "天気"),
        ("{rain}", "降水確率"),
        ("{hr}", "心拍数"),
        ("{distance}", "移動距離"),
        ("{preset}", "プリセット名"),
        ("{steps}", "今日の歩数"),
        ("{yaw}", "頭の左右の向き"),
    ]

    /// 値のないトークンは "--" にする。テンプレートにない記号はそのまま。
    public static func render(_ template: String, values: [String: String]) -> String {
        var result = template
        for (token, _) in tokens where result.contains(token) {
            let key = String(token.dropFirst().dropLast())
            result = result.replacingOccurrences(of: token, with: values[key] ?? "--")
        }
        return result
    }

    public static func usesTokens(_ template: String) -> Bool {
        tokens.contains { template.contains($0.token) }
    }
}
