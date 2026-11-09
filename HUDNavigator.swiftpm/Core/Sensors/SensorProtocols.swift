import Foundation

/// VITURE 本体の USB HID のやり取り（非公式）。
/// 公式 SDK は iOS 非対応のため、オープンソースの解析結果を参考にした実験的な実装。
/// 出典：github.com/mgschwan/viture_virtual_display（MIT ライセンス）の viture_connection.c / v4l2_gl.c の説明を元に、
/// Swift で書き直したもの（コードの複製ではない）。作者自身も一部（CRC の初期値など）を推定としている。
public enum VitureHIDProtocol {
    public static let vendorID = 0x35CA
    /// 頭の向きのデータが来るインターフェース番号と、命令を送るインターフェース番号
    public static let imuInterface = 0
    public static let mcuInterface = 1
    /// IMU の送信を開始・停止する命令
    public static let setIMUCommandID: UInt16 = 0x15
    public static let packetSize = 64

    /// CRC-16/CCITT（多項式 0x1021、初期値 0、反転なし）
    public static func crc16<C: Collection>(_ bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0
        for b in bytes {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    /// 命令（64 バイト）：FF FE | CRC(2) | 長さ(2) | 0×8 | 命令ID(2) | 0×2 | データ
    public static func command(id: UInt16, data: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: packetSize)
        out[0] = 0xFF
        out[1] = 0xFE
        let payloadLength = UInt16(0x0C + min(data.count, packetSize - 0x12))
        out[0x0E] = UInt8(id & 0xFF)
        out[0x0F] = UInt8(id >> 8)
        for (i, b) in data.prefix(packetSize - 0x12).enumerated() { out[0x12 + i] = b }
        out[4] = UInt8(payloadLength & 0xFF)
        out[5] = UInt8(payloadLength >> 8)
        let crc = crc16(out[4..<(6 + Int(payloadLength))])
        out[2] = UInt8(crc & 0xFF)
        out[3] = UInt8(crc >> 8)
        return out
    }

    public static func setIMU(_ enabled: Bool) -> [UInt8] {
        command(id: setIMUCommandID, data: [enabled ? 1 : 0])
    }

    public struct IMUReading: Equatable, Sendable {
        public var roll: Double
        public var pitch: Double
        public var yaw: Double
        public var checksumValid: Bool
    }

    /// IMU のデータ（FF FC で始まる）を読む。先頭にレポート ID が付いていても読めるようにする。
    public static func parseIMU(_ report: [UInt8]) -> IMUReading? {
        for start in 0...1 where report.count >= start + 0x12 + 12 {
            guard report[start] == 0xFF, report[start + 1] == 0xFC else { continue }
            let payloadLength = Int(report[start + 4]) | Int(report[start + 5]) << 8
            guard payloadLength >= 0x0C + 12 else { continue }
            let base = start + 0x12
            let roll = Double(bigEndianFloat(report, at: base))
            let pitch = Double(bigEndianFloat(report, at: base + 4))
            let yaw = Double(bigEndianFloat(report, at: base + 8))
            guard [roll, pitch, yaw].allSatisfy({ $0.isFinite && abs($0) <= 720 }) else { continue }
            var valid = false
            let end = start + 6 + payloadLength
            if end <= report.count {
                let stored = UInt16(report[start + 2]) | UInt16(report[start + 3]) << 8
                valid = crc16(report[(start + 4)..<end]) == stored
            }
            return IMUReading(roll: roll, pitch: pitch, yaw: yaw, checksumValid: valid)
        }
        return nil
    }

    /// HeadPose の向きにそろえる（参考元のアプリは yaw の符号を反転して使っている）
    public static func pose(_ r: IMUReading) -> HeadPose {
        HeadPose(yaw: -r.yaw, pitch: r.pitch, roll: r.roll)
    }

    static func bigEndianFloat(_ bytes: [UInt8], at i: Int) -> Float {
        let bits = UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
        return Float(bitPattern: bits)
    }

    /// 診断用：16 進表示
    public static func hex(_ bytes: [UInt8], limit: Int = 32) -> String {
        bytes.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ") + (bytes.count > limit ? " …" : "")
    }
}

/// WitMotion の Bluetooth 5.0 動きセンサー（WT901BLECL など）。公開されている通信仕様に基づく。
/// 通知のデータ：0x55 0x61 + 9 個の符号付き 16 ビット（下位バイトが先）＝加速度・角速度・角度。
public enum WitMotionBLE {
    public static let serviceUUID = "0000FFE5-0000-1000-8000-00805F9A34FB"
    public static let notifyUUID = "0000FFE4-0000-1000-8000-00805F9A34FB"
    public static let writeUUID = "0000FFE9-0000-1000-8000-00805F9A34FB"
    public static let namePrefixes = ["WT", "HC-", "Wit"]

    public struct Sample: Equatable, Sendable {
        /// 加速度（G）
        public var ax: Double, ay: Double, az: Double
        /// 角速度（度/秒）
        public var gx: Double, gy: Double, gz: Double
        /// 角度（度）
        public var roll: Double, pitch: Double, yaw: Double
    }

    /// 1 回の通知に複数のパケットが入っていても読む
    public static func parse(_ bytes: [UInt8]) -> [Sample] {
        var result: [Sample] = []
        var i = 0
        while i + 20 <= bytes.count {
            if bytes[i] == 0x55 && bytes[i + 1] == 0x61 {
                func v(_ k: Int) -> Double {
                    Double(Int16(bitPattern: UInt16(bytes[i + 2 + 2 * k]) | UInt16(bytes[i + 3 + 2 * k]) << 8))
                }
                result.append(Sample(
                    ax: v(0) / 32768 * 16, ay: v(1) / 32768 * 16, az: v(2) / 32768 * 16,
                    gx: v(3) / 32768 * 2000, gy: v(4) / 32768 * 2000, gz: v(5) / 32768 * 2000,
                    roll: v(6) / 32768 * 180, pitch: v(7) / 32768 * 180, yaw: v(8) / 32768 * 180
                ))
                i += 20
            } else {
                i += 1
            }
        }
        return result
    }

    /// 向きをそろえる：センサーの Z 軸の角度は反時計回りがプラスなので、右を向くとプラスになるよう反転
    public static func pose(_ s: Sample) -> HeadPose {
        HeadPose(yaw: -s.yaw, pitch: s.pitch, roll: s.roll)
    }

    /// 出力の頻度を変える命令（保存はしないので電源を切ると元に戻る）：ロック解除 → 頻度
    public static func rateCommands(hz: Int) -> [[UInt8]] {
        let code: UInt8
        switch hz {
        case ..<15: code = 0x06   // 10Hz
        case ..<35: code = 0x07   // 20Hz
        case ..<75: code = 0x08   // 50Hz
        default: code = 0x09      // 100Hz
        }
        return [[0xFF, 0xAA, 0x69, 0x88, 0xB5], [0xFF, 0xAA, 0x03, code, 0x00]]
    }
}

/// 自作センサー（ESP32 など）用のかんたんな Bluetooth の約束事。
/// 通知のデータ：yaw・pitch・roll（度、float32、下位バイトが先）＋任意で加速度 x・y・z（G）。
/// 向きは HeadPose と同じ（右・上・右に傾けるとプラス）。Extensions/Hardware のスケッチがこの形で送る。
public enum HUDIMUBLE {
    public static let serviceUUID = "4855444E-4156-4900-8000-494D55000000"
    public static let poseUUID = "4855444E-4156-4900-8000-494D55000001"
    public static let namePrefix = "HUD-IMU"

    public struct Sample: Equatable, Sendable {
        public var pose: HeadPose
        public var acceleration: (x: Double, y: Double, z: Double)?

        public static func == (a: Sample, b: Sample) -> Bool {
            a.pose == b.pose && a.acceleration?.x == b.acceleration?.x && a.acceleration?.y == b.acceleration?.y && a.acceleration?.z == b.acceleration?.z
        }
    }

    public static func parse(_ bytes: [UInt8]) -> Sample? {
        guard bytes.count >= 12 else { return nil }
        func f(_ i: Int) -> Double {
            Double(Float(bitPattern: UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24))
        }
        let pose = HeadPose(yaw: f(0), pitch: f(4), roll: f(8))
        guard [pose.yaw, pose.pitch, pose.roll].allSatisfy({ $0.isFinite }) else { return nil }
        var acc: (Double, Double, Double)?
        if bytes.count >= 24 { acc = (f(12), f(16), f(20)) }
        return Sample(pose: pose, acceleration: acc)
    }

    public static func encode(_ pose: HeadPose) -> [UInt8] {
        [pose.yaw, pose.pitch, pose.roll].flatMap { v -> [UInt8] in
            let bits = Float(v).bitPattern
            return [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8(bits >> 24)]
        }
    }
}
