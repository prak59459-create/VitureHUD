import Foundation

/// Bluetooth 心拍計（標準規格 Heart Rate Service 0x180D / Measurement 0x2A37）のデータ解析。
public enum HeartRateParser {
    public static let serviceUUID = "180D"
    public static let measurementUUID = "2A37"

    /// Heart Rate Measurement の値 → bpm
    public static func bpm(from bytes: [UInt8]) -> Int? {
        guard let flags = bytes.first else { return nil }
        let is16Bit = flags & 0x01 != 0
        if is16Bit {
            guard bytes.count >= 3 else { return nil }
            return Int(UInt16(bytes[1]) | (UInt16(bytes[2]) << 8))
        }
        guard bytes.count >= 2 else { return nil }
        return Int(bytes[1])
    }

    /// 年齢から心拍ゾーンを求める（目安）
    public static func zone(bpm: Int, age: Int = 35) -> (index: Int, name: String) {
        let maxHR = Double(220 - age)
        let ratio = Double(bpm) / maxHR
        switch ratio {
        case ..<0.5: return (0, "安静")
        case ..<0.6: return (1, "ウォームアップ")
        case ..<0.7: return (2, "脂肪燃焼")
        case ..<0.8: return (3, "有酸素")
        case ..<0.9: return (4, "無酸素")
        default: return (5, "最大")
        }
    }
}

/// iCloud Drive の同期フォルダを使った自動同期の判断。
public enum SyncDecision {
    /// フォルダにある設定ファイルを取り込むべきか
    public static func shouldImport(remoteExportedAt: Date, remoteDeviceID: String?, localDeviceID: String, lastImportedAt: Date?, lastExportedAt: Date?) -> Bool {
        if remoteDeviceID == localDeviceID { return false }
        if let imported = lastImportedAt, remoteExportedAt <= imported { return false }
        // 自分が書き出した後に更新されたものだけ
        if let exported = lastExportedAt, remoteExportedAt <= exported { return false }
        return true
    }
}
