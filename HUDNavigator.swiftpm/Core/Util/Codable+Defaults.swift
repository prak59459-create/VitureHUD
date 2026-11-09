import Foundation

// 設定ファイルの前方互換のための補助。
// 新しい項目が増えても、古いJSONを読み込めるようにする（欠けている項目は既定値）。

extension KeyedDecodingContainer {
    /// キーが無い・型が違う場合は既定値を返す。
    func value<T: Decodable>(_ key: Key, default defaultValue: @autoclosure () -> T) -> T {
        if let decoded = try? decodeIfPresent(T.self, forKey: key) {
            return decoded
        }
        return defaultValue()
    }
}

public enum HUDJSON {
    public static func encoder(pretty: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode<T: Encodable>(_ value: T, pretty: Bool = true) throws -> Data {
        try encoder(pretty: pretty).encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
