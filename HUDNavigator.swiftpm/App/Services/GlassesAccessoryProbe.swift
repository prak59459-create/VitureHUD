import Foundation
import ExternalAccessory
import CoreMIDI
import AVFoundation
import GameController
import Observation

/// VITURE（本体・公式の USB-C XR 充電アダプター）が iOS の「公開されている API」でどう見えるかを調べ、
/// 見えたデータの中に頭の向きがあれば使う。
///
/// - 非公開の API は使わない（USB を直接開く方法は iOS が許可しないことを実機で確認済み）。
/// - 機器には何も送らず、届いたデータを読むだけ。
/// - VITURE 公式の説明では、iPhone に直接つないだ場合は頭の向きは使えず、公式アダプター＋公式アプリ（SpaceWalker）が必要。
///   アダプターとアプリの間のやり取りは公開されていないため、ここで分かるのは「iOS から何が見えるか」まで。
@MainActor
@Observable
final class GlassesAccessoryProbe {
    struct Item: Identifiable, Hashable {
        var id: String
        var kind: String
        var name: String
        var detail: String
    }

    private(set) var items: [Item] = []
    private(set) var log: [String] = []
    private(set) var packets = 0
    private(set) var receivedBytes = 0
    private(set) var lastHex: String?
    private(set) var openSession: String?
    private(set) var isRunning = false

    @ObservationIgnored var onPose: ((HeadPose) -> Void)?
    @ObservationIgnored private var session: EASession?
    @ObservationIgnored private var streamDelegate: StreamReader?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var midiClient = MIDIClientRef()
    @ObservationIgnored private var midiPort = MIDIPortRef()
    @ObservationIgnored private var buffer: [UInt8] = []

    /// アプリが「話せる」と宣言しているアクセサリーの通信の名前（Info.plist）
    static var declaredProtocols: [String] {
        Bundle.main.object(forInfoDictionaryKey: "UISupportedExternalAccessoryProtocols") as? [String] ?? []
    }

    private func note(_ text: String) {
        log.append("\(HUDFormat.clock(Date(), seconds: true)) \(text)")
        if log.count > 80 { log.removeFirst(log.count - 80) }
    }

    // MARK: - 開始・終了

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NotificationCenter.default
        for name in [Notification.Name.EAAccessoryDidConnect, .EAAccessoryDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.accessoriesChanged() }
            })
        }
        EAAccessoryManager.shared().registerForLocalNotifications()
        startMIDI()
        refresh()
        openFirstUsableAccessory()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        EAAccessoryManager.shared().unregisterForLocalNotifications()
        closeSession()
        if midiPort != 0 { MIDIPortDispose(midiPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
        midiPort = 0
        midiClient = 0
    }

    private func accessoriesChanged() {
        refresh()
        if session == nil { openFirstUsableAccessory() }
    }

    // MARK: - 見えるものの一覧

    /// 公開 API で見える機器を集め直す
    func refresh() {
        var found: [Item] = []

        // 1. MFi アクセサリー（ExternalAccessory）
        for a in EAAccessoryManager.shared().connectedAccessories {
            let protocols = a.protocolStrings.isEmpty ? "（通信の名前なし）" : a.protocolStrings.joined(separator: ", ")
            found.append(Item(
                id: "ea-\(a.connectionID)",
                kind: "アクセサリー（MFi）",
                name: a.name.isEmpty ? "名前なし" : a.name,
                detail: "\(a.manufacturer) \(a.modelNumber)・FW \(a.firmwareRevision)・\(protocols)"
            ))
        }

        // 2. USB / Bluetooth の MIDI 機器（CoreMIDI）
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            found.append(Item(id: "midi-\(i)", kind: "MIDI", name: Self.midiString(source, kMIDIPropertyDisplayName) ?? "名前なし",
                              detail: Self.midiString(source, kMIDIPropertyManufacturer) ?? ""))
        }

        // 3. 音の出入り口（グラスのスピーカー・マイクは USB オーディオとして見える）
        let audio = AVAudioSession.sharedInstance()
        var seen = Set<String>()
        for port in audio.currentRoute.outputs + audio.currentRoute.inputs + (audio.availableInputs ?? []) {
            guard port.portType != .builtInSpeaker, port.portType != .builtInMic, port.portType != .builtInReceiver else { continue }
            guard seen.insert(port.uid).inserted else { continue }
            found.append(Item(id: "audio-\(port.uid)", kind: "オーディオ", name: port.portName, detail: port.portType.rawValue))
        }

        // 4. ゲームコントローラー（動きセンサー付きなら向きが取れる）
        for (i, controller) in GCController.controllers().enumerated() {
            found.append(Item(id: "gc-\(i)", kind: "コントローラー", name: controller.vendorName ?? "名前なし",
                              detail: controller.motion == nil ? "動きセンサーなし" : "動きセンサーあり"))
        }

        // 5. 外付けカメラ（iPad）
        let cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: nil, position: .unspecified).devices
        for camera in cameras {
            found.append(Item(id: "cam-\(camera.uniqueID)", kind: "外付けカメラ", name: camera.localizedName, detail: camera.manufacturer))
        }

        // 6. 有線のネットワーク（アダプターがネットワーク機器として見える場合）
        for (name, address) in Self.wiredInterfaces() {
            found.append(Item(id: "net-\(name)", kind: "ネットワーク", name: name, detail: address))
        }

        if found != items {
            items = found
            note(found.isEmpty ? "公開 API で見える機器はありません" : "見える機器：" + found.map { "\($0.kind)「\($0.name)」" }.joined(separator: "、"))
        }
    }

    private static func midiString(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Wi-Fi（en0）・モバイル通信以外で、アドレスを持つネットワーク
    private static func wiredInterfaces() -> [(String, String)] {
        var result: [(String, String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en"), name != "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append((name, String(cString: host)))
            }
        }
        return result
    }

    // MARK: - MFi アクセサリーのデータを読む

    private func openFirstUsableAccessory() {
        let declared = Set(Self.declaredProtocols)
        for accessory in EAAccessoryManager.shared().connectedAccessories {
            guard let proto = accessory.protocolStrings.first(where: { declared.contains($0) }) else {
                if !accessory.protocolStrings.isEmpty {
                    note("「\(accessory.name)」の通信（\(accessory.protocolStrings.joined(separator: ", "))）は、このアプリでは開けません")
                }
                continue
            }
            guard let session = EASession(accessory: accessory, forProtocol: proto), let input = session.inputStream else {
                note("「\(accessory.name)」（\(proto)）を開けませんでした")
                continue
            }
            let reader = StreamReader()
            reader.owner = self
            input.delegate = reader
            input.schedule(in: .main, forMode: .default)
            input.open()
            self.session = session
            streamDelegate = reader
            openSession = "\(accessory.name)（\(proto)）"
            note("「\(accessory.name)」（\(proto)）を開きました。データを待っています")
            return
        }
    }

    private func closeSession() {
        if let input = session?.inputStream {
            input.close()
            input.remove(from: .main, forMode: .default)
            input.delegate = nil
        }
        session = nil
        streamDelegate = nil
        openSession = nil
        buffer = []
    }

    fileprivate func streamEnded() {
        note("アクセサリーとの通信が終わりました")
        closeSession()
    }

    // MARK: - MIDI のデータを読む

    private func startMIDI() {
        guard midiClient == 0 else { return }
        let status = MIDIClientCreateWithBlock("HUDNavigator" as CFString, &midiClient) { [weak self] _ in
            Task { @MainActor in self?.midiSetupChanged() }
        }
        guard status == noErr else {
            note("MIDI を使えません（\(status)）")
            return
        }
        let portStatus = MIDIInputPortCreateWithBlock(midiClient, "HUDNavigator In" as CFString, &midiPort) { [weak self] packetList, _ in
            var bytes: [UInt8] = []
            for packet in packetList.unsafeSequence() {
                let length = Int(packet.pointee.length)
                guard length > 0, let offset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data) else { continue }
                let start = UnsafeRawPointer(packet).advanced(by: offset)
                bytes.append(contentsOf: UnsafeRawBufferPointer(start: start, count: length))
            }
            guard !bytes.isEmpty else { return }
            Task { @MainActor in self?.received(bytes, from: "MIDI") }
        }
        guard portStatus == noErr else { return }
        connectMIDISources()
    }

    private func midiSetupChanged() {
        connectMIDISources()
        refresh()
    }

    private func connectMIDISources() {
        guard midiPort != 0 else { return }
        for i in 0..<MIDIGetNumberOfSources() {
            MIDIPortConnectSource(midiPort, MIDIGetSource(i), nil)
        }
    }

    // MARK: - 届いたデータ

    /// 届いたデータの中に、VITURE の「頭の向き」の形（公開されている解析結果と同じ形）があれば使う
    fileprivate func received(_ bytes: [UInt8], from source: String) {
        packets += 1
        receivedBytes += bytes.count
        lastHex = VitureHIDProtocol.hex(Array(bytes.prefix(48)))
        if packets <= 5 { note("\(source) から \(bytes.count) バイト：\(lastHex ?? "")") }
        buffer.append(contentsOf: bytes)
        if buffer.count > 4096 { buffer.removeFirst(buffer.count - 4096) }
        // FF FC で始まるかたまりを探す
        var index = 0
        var consumed = 0
        while index + 30 <= buffer.count {
            if buffer[index] == 0xFF, buffer[index + 1] == 0xFC {
                let end = min(buffer.count, index + VitureHIDProtocol.packetSize)
                if let reading = VitureHIDProtocol.parseIMU(Array(buffer[index..<end])) {
                    onPose?(VitureHIDProtocol.pose(reading))
                    index = end
                    consumed = end
                    continue
                }
            }
            index += 1
        }
        if consumed > 0 { buffer.removeFirst(consumed) }
    }

    // MARK: - 報告用

    /// コピーして報告できる文章
    var report: String {
        var lines = ["HUD Navigator：VITURE 接続の診断（公開 API のみ）"]
        let declared = Self.declaredProtocols
        lines.append("アプリが宣言している通信の名前：\(declared.isEmpty ? "なし" : declared.joined(separator: ", "))")
        lines.append("見える機器：\(items.isEmpty ? "なし" : "")")
        for item in items { lines.append("・\(item.kind)：\(item.name)（\(item.detail)）") }
        lines.append("開いている通信：\(openSession ?? "なし")")
        lines.append("受け取ったデータ：\(packets) 回・\(receivedBytes) バイト")
        if let lastHex { lines.append("最後のデータ：\(lastHex)") }
        lines.append("記録：")
        lines.append(contentsOf: log)
        return lines.joined(separator: "\n")
    }
}

/// アクセサリーからの入力を読む（メインの実行ループで呼ばれる）
private final class StreamReader: NSObject, StreamDelegate {
    weak var owner: GlassesAccessoryProbe?

    func stream(_ stream: Stream, handle event: Stream.Event) {
        guard let input = stream as? InputStream else { return }
        if event.contains(.hasBytesAvailable) {
            var chunk = [UInt8](repeating: 0, count: 1024)
            var all: [UInt8] = []
            while input.hasBytesAvailable {
                let n = input.read(&chunk, maxLength: chunk.count)
                guard n > 0 else { break }
                all.append(contentsOf: chunk[0..<n])
            }
            if !all.isEmpty {
                MainActor.assumeIsolated { owner?.received(all, from: "アクセサリー") }
            }
        }
        if event.contains(.endEncountered) || event.contains(.errorOccurred) {
            MainActor.assumeIsolated { owner?.streamEnded() }
        }
    }
}
