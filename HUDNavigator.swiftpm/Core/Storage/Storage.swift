import Foundation

/// JSON ファイルの保存・読み込み（端末内）。
public final class JSONFileStore: @unchecked Sendable {
    public let directory: URL
    private let queue = DispatchQueue(label: "hudnavigator.store")

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func url(for name: String) -> URL { directory.appendingPathComponent(name + ".json") }

    public func save<T: Encodable>(_ value: T, as name: String) throws {
        let data = try HUDJSON.encode(value)
        try queue.sync {
            try data.write(to: url(for: name), options: .atomic)
        }
    }

    public func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        queue.sync {
            guard let data = try? Data(contentsOf: url(for: name)) else { return nil }
            return try? HUDJSON.decode(type, from: data)
        }
    }

    public func loadData(_ name: String) -> Data? {
        queue.sync { try? Data(contentsOf: url(for: name)) }
    }

    public func delete(_ name: String) {
        queue.sync { _ = try? FileManager.default.removeItem(at: url(for: name)) }
    }

    public func deleteAll() {
        queue.sync {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension == "json" { try? FileManager.default.removeItem(at: f) }
        }
    }
}

/// 端末間で設定を移すためのファイル（iCloud Drive 経由で手動同期）。
public struct SettingsBundle: Codable, Sendable {
    public static let currentVersion = 1
    public static let fileExtension = "hudnav"

    public var version: Int
    public var exportedAt: Date
    public var deviceName: String
    public var settings: AppSettings?
    public var themes: [Theme]
    public var presets: [Preset]
    public var favorites: [FavoritePlace]
    public var trips: [TripRecord]?

    public init(version: Int = SettingsBundle.currentVersion, exportedAt: Date, deviceName: String, settings: AppSettings?, themes: [Theme], presets: [Preset], favorites: [FavoritePlace], trips: [TripRecord]? = nil) {
        self.version = version
        self.exportedAt = exportedAt
        self.deviceName = deviceName
        self.settings = settings
        self.themes = themes
        self.presets = presets
        self.favorites = favorites
        self.trips = trips
    }

    enum CodingKeys: String, CodingKey {
        case version, exportedAt, deviceName, settings, themes, presets, favorites, trips
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, default: 1)
        exportedAt = c.value(.exportedAt, default: Date())
        deviceName = c.value(.deviceName, default: "")
        settings = c.value(.settings, default: nil)
        themes = c.value(.themes, default: [])
        presets = c.value(.presets, default: [])
        favorites = c.value(.favorites, default: [])
        trips = c.value(.trips, default: nil)
    }

    public func encoded() throws -> Data { try HUDJSON.encode(self) }

    public static func decode(_ data: Data) throws -> SettingsBundle {
        let bundle = try HUDJSON.decode(SettingsBundle.self, from: data)
        guard bundle.version <= currentVersion else {
            throw SettingsBundleError.newerVersion(bundle.version)
        }
        return bundle
    }

    public enum MergeStrategy: Sendable { case replace, merge }

    /// 取り込み：同じIDは上書き、それ以外は追加（merge）／全部置き換え（replace）。組み込みは常に残す。
    public static func merged<T: Identifiable>(_ existing: [T], incoming: [T], strategy: MergeStrategy, isBuiltIn: (T) -> Bool) -> [T] where T.ID == UUID {
        switch strategy {
        case .replace:
            let builtIns = existing.filter(isBuiltIn)
            let incomingIDs = Set(incoming.map(\.id))
            return builtIns.filter { !incomingIDs.contains($0.id) } + incoming
        case .merge:
            var result = existing
            for item in incoming {
                if let i = result.firstIndex(where: { $0.id == item.id }) {
                    result[i] = item
                } else {
                    result.append(item)
                }
            }
            return result
        }
    }
}

public enum SettingsBundleError: Error, Equatable, LocalizedError {
    case newerVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .newerVersion(let v): return "新しいバージョンのアプリで書き出されたファイルです（形式 v\(v)）。アプリを更新してください。"
        }
    }
}
