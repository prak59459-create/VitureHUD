import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Google Maps

struct GoogleMapsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKey = ""
    @State private var hasKey = false
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("地図エンジン", selection: $model.settings.map.engine) {
                    ForEach(MapEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if model.settings.map.engine == .googleMaps && !GoogleMapsService.isReady(model.settings.googleMaps) {
                    Label("APIキーの保存と送信への同意が済むまでは Apple マップを使います。", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(UIStyle.warning)
                }
            } footer: {
                Text("地図の表示は Apple マップのままです。Google Maps は「場所の検索」「経路」に使います。公共交通の経路は、APIキーがあれば地図エンジンが Apple でも Google で検索します（MapKit では乗り換え経路が取れないため）。")
            }
            Section {
                SecureField(hasKey ? "APIキー（保存済み・変更する場合のみ入力）" : "APIキー", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Button("APIキーを保存") {
                        KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: GoogleMapsService.keyAccount)
                        apiKey = ""
                        hasKey = GoogleMapsService.hasKey
                    }
                    .disabled(apiKey.isEmpty)
                    Spacer()
                    if hasKey {
                        Button("削除", role: .destructive) {
                            KeychainStore.delete(account: GoogleMapsService.keyAccount)
                            hasKey = GoogleMapsService.hasKey
                        }
                    }
                }
            } header: {
                Text("APIキー")
            } footer: {
                Text("Google Cloud Console でプロジェクトを作り、請求先を登録して「Places API (New)」と「Routes API」を有効にし、APIキーを作成します（iOS アプリ用の制限をかけることをおすすめします）。従量課金ですが、毎月の無料利用枠があります。料金は Google の最新の料金表で確認してください。APIキーは端末の Keychain に保存し、書き出しファイルには含めません。")
            }
            Section {
                Toggle("送信に同意する", isOn: $model.settings.googleMaps.consentGiven)
                Text("送信するもの：検索語、丸めた現在地（約100m）、経路検索時の出発地と目的地の座標。送信しないもの：カメラ映像、音声、移動履歴。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("同意")
            }
            Section("使う機能") {
                Toggle("場所の検索・周辺検索", isOn: $model.settings.googleMaps.usesForSearch)
                Toggle("徒歩・車の経路", isOn: $model.settings.googleMaps.usesForRoutes)
                Toggle("公共交通の経路（乗り換え案内）", isOn: $model.settings.googleMaps.usesForTransit)
            }
            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    if testing { ProgressView() } else { Text("接続をテスト（「東京駅」を検索）") }
                }
                .disabled(!GoogleMapsService.isReady(model.settings.googleMaps) || testing)
                if let testResult { Text(testResult).font(.footnote) }
            }
        }
        .navigationTitle("Google Maps")
        .onAppear { hasKey = GoogleMapsService.hasKey }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        do {
            let results = try await GoogleMapsService.search("東京駅", near: model.location.lastSample?.coordinate, network: model.network)
            testResult = "成功：\(results.count)件（\(results.first?.name ?? "")）"
        } catch {
            testResult = "失敗：\(error.localizedDescription)"
        }
    }
}

// MARK: - 心拍計（Bluetooth）

struct HeartRateSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let hr = model.heartRate
        Form {
            Section {
                Toggle("心拍計を使う", isOn: $model.settings.bluetooth.heartRateEnabled)
                LabeledContent("状態", value: hr.state.displayName)
                if let bpm = hr.bpm, hr.isFresh {
                    let zone = HeartRateParser.zone(bpm: bpm)
                    LabeledContent("心拍数", value: "\(bpm) bpm（ゾーン\(zone.index)・\(zone.name)）")
                }
            } footer: {
                Text("Bluetooth の標準「心拍サービス」に対応した心拍計（胸ベルト・アームバンドなど）を使えます。Apple Watch の心拍は他のアプリから直接は読めません。心拍ゾーンは年齢35歳の目安です。")
            }
            if model.settings.bluetooth.heartRateEnabled {
                Section {
                    if let name = model.settings.bluetooth.rememberedDeviceName {
                        LabeledContent("記憶している心拍計", value: name)
                        Button("記憶を消す", role: .destructive) {
                            model.settings.bluetooth.rememberedDeviceID = nil
                            model.settings.bluetooth.rememberedDeviceName = nil
                        }
                    }
                    Button {
                        hr.scan()
                    } label: {
                        Label(hr.state == .scanning ? "探しています…" : "心拍計を探す", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(hr.state == .scanning)
                    ForEach(hr.found) { device in
                        Button {
                            hr.connect(device.id)
                        } label: {
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text("\(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("接続")
                }
                Section {
                    Button("HUD に心拍ウィジェットを追加") { model.showWidget(.heartRate) }
                }
            }
        }
        .navigationTitle("心拍計")
        .serviceDemand(model.settings.bluetooth.heartRateEnabled ? [.bluetooth] : [])
    }
}

// MARK: - 提案（プロアクティブ）

struct ProactiveSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("状況に合わせて提案する", isOn: $model.settings.proactive.enabled)
            } footer: {
                Text("天気・電池・発熱・歩いている時間などから、役に立ちそうな操作を HUD とホーム画面で提案します。判断は端末内だけで行い、通信はしません。")
            }
            Section("提案の種類") {
                Toggle("雨・紫外線・暑さ・寒さ", isOn: $model.settings.proactive.weatherTips)
                Toggle("電池を長持ちさせる", isOn: $model.settings.proactive.batteryTips)
                Toggle("休憩（1時間歩き続けたとき）", isOn: $model.settings.proactive.breakReminders)
                Toggle("到着後の周辺検索", isOn: $model.settings.proactive.nearbyTips)
            }
            .disabled(!model.settings.proactive.enabled)
            Section {
                Button("今の状況で提案を確認") { model.runAdvisor() }
                if let s = model.suggestion {
                    VStack(alignment: .leading) {
                        Text(s.title).bold()
                        Text(s.message).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("提案")
    }
}

// MARK: - HUD の見え方（明るさ・3D・空間固定）

struct HUDAppearanceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let d = model.settings.display
        Section {
            LabeledSlider(title: "HUD の明るさ", value: $model.settings.display.brightness, range: 0.2...1, format: { "\(Int($0 * 100))%" })
            Toggle("夜は自動で暗くする", isOn: $model.settings.display.nightDimEnabled)
            if d.nightDimEnabled {
                LabeledSlider(title: "夜の明るさ（倍率）", value: $model.settings.display.nightBrightness, range: 0.2...1, format: { "\(Int($0 * 100))%" })
                Stepper("夜の始まり：\(d.nightStartHour)時", value: $model.settings.display.nightStartHour, in: 0...23)
                Stepper("夜の終わり：\(d.nightEndHour)時", value: $model.settings.display.nightEndHour, in: 0...23)
            }
            LabeledContent("今の明るさ", value: "\(Int(model.hudBrightness * 100))%")
        } header: {
            Text("明るさ")
        } footer: {
            Text("天気を取得している場合は、日の出・日の入り（昼か夜か）で切り替えます。取得していない場合は時刻で判断します。")
        }
        Section {
            Toggle("3D 表示（左右分割）", isOn: $model.settings.display.stereo3D)
            if d.stereo3D {
                LabeledSlider(title: "奥行き（左右のずらし）", value: $model.settings.display.stereoDepth, range: -40...40, format: { String(format: "%+.0f px", $0) })
                Text("グラスを 3D モード（左右分割）に切り替えてください。プラスで手前、マイナスで奥に見えます。3D 表示中はカメラ背景を使えません（黒背景になります）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let size = model.display.externalScreenSize, size.height > 0 {
                let wide = size.width / size.height >= 3
                LabeledContent("グラスの信号", value: "\(Int(size.width))×\(Int(size.height))\(wide ? "（3D・左右合計）" : "")")
                if wide {
                    Text("グラスが 3D モード（32:9）でつながっています。左右の目に自動で描き分けます（上の設定に関係なく）。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("3D")
        } footer: {
            Text("VITURE は 3D モードで 3840×1080（左右合計）の信号を受け取ります。端末がこの大きさで出力した場合は自動で左右に描き分け、1920×1080 のままの場合は「3D 表示」を ON にすると左右に半分ずつ描きます。")
        }
        Section {
            NavigationLink {
                HeadTrackingSettingsView()
            } label: {
                LabeledContent("頭の動き（空間固定・ジェスチャー）", value: model.settings.headTracking.source.displayName)
            }
        } header: {
            Text("頭の動き")
        }
        Section {
            Toggle("グラスに表示中は端末の画面を暗くする", isOn: $model.settings.display.dimsDeviceScreen)
        } footer: {
            Text("グラスに独立表示しているとき、端末の画面の明るさを下げて電池を節約します（アプリを離れると元に戻します）。")
        }
    }
}

// MARK: - 同期フォルダ（iCloud Drive など）

struct SyncFolderSection: View {
    @Environment(AppModel.self) private var model
    @State private var choosing = false
    @State private var working = false

    var body: some View {
        @Bindable var model = model
        let sync = model.settings.sync
        Section {
            if let name = model.syncFolder.folderName {
                LabeledContent("フォルダ", value: name)
            }
            Button(model.syncFolder.isConfigured ? "フォルダを変更" : "同期フォルダを選ぶ") { choosing = true }
            if model.syncFolder.isConfigured {
                Toggle("自動で同期する", isOn: $model.settings.sync.autoSyncEnabled)
                Toggle("移動履歴・訪問した場所も同期する", isOn: $model.settings.sync.includesHistory)
                Button {
                    working = true
                    Task {
                        let text = await model.syncNow()
                        model.showToast(text)
                        working = false
                    }
                } label: {
                    if working { ProgressView() } else { Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath") }
                }
                if let t = sync.lastExportedAt { LabeledContent("最後の書き出し", value: "\(HUDFormat.date(t)) \(HUDFormat.clock(t))") }
                if let t = sync.lastImportedAt { LabeledContent("最後の読み込み", value: "\(HUDFormat.date(t)) \(HUDFormat.clock(t))") }
                if let message = model.syncFolder.lastMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                Button("同期フォルダの設定を解除", role: .destructive) {
                    model.syncFolder.clearFolder()
                    model.settings.sync.autoSyncEnabled = false
                }
            }
        } header: {
            Text("自動同期（iCloud Drive のフォルダ）")
        } footer: {
            Text("両方の端末で、iCloud Drive の同じフォルダ（例：iCloud Drive › HUD Navigator）を選んでください。設定を変えると数秒後に書き出し、アプリを開いたときに相手の端末の新しい設定を読み込みます。APIキーと各種同意は同期しません。")
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            if model.syncFolder.setFolder(url) {
                model.settings.sync.folderName = url.lastPathComponent
                model.settings.sync.autoSyncEnabled = true
                Task { _ = await model.syncNow() }
            }
        }
    }
}

// MARK: - 訪問した場所・利用状況（履歴画面に追加）

struct VisitsAndUsageSections: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDeleteVisits = false

    var body: some View {
        @Bindable var model = model
        let usage = model.history.usage
        Section {
            Toggle("訪問した場所を記録（5分以上とどまった場所）", isOn: $model.settings.history.recordsVisits)
                .disabled(!model.settings.history.enabled)
            ForEach(model.history.visits.suffix(30).reversed()) { v in
                VStack(alignment: .leading) {
                    Text(v.placeName ?? "名称を取得中…")
                    Text("\(HUDFormat.date(v.arrivedAt)) \(HUDFormat.clock(v.arrivedAt))〜\(HUDFormat.clock(v.departedAt))・\(HUDFormat.duration(v.duration))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !model.history.visits.isEmpty {
                Button("訪問した場所を削除", role: .destructive) { confirmDeleteVisits = true }
            }
        } header: {
            Text("訪問した場所")
        } footer: {
            Text("端末内にだけ保存します。地名は Apple の逆ジオコーディングで取得します。")
        }
        if model.settings.history.recordsDetections && !model.history.detectionLog.isEmpty {
            Section("物体検出の記録") {
                ForEach(detectionRows) { row in
                    LabeledContent(row.id, value: row.value)
                }
                let high = model.history.detectionLog.filter { $0.hazard >= .high }.count
                LabeledContent("強い警告", value: "\(high)回")
                Button("物体検出の記録を削除", role: .destructive) { model.history.deleteDetectionLog() }
            }
        }
        Section {
            Toggle("利用状況を集計する", isOn: $model.settings.history.recordsUsage)
            if model.settings.history.recordsUsage {
                LabeledContent("起動", value: "\(usage.launches)回")
                LabeledContent("HUD を表示した時間", value: HUDFormat.duration(usage.hudSeconds))
                LabeledContent("ナビ", value: "\(usage.navigationCount)回・\(HUDFormat.distance(usage.navigationDistance))")
                LabeledContent("音声コマンド", value: "\(usage.voiceCommands)回")
                ForEach(usageRows(usage)) { row in
                    LabeledContent(row.id, value: row.value)
                }
                Button("集計をリセット", role: .destructive) { model.history.resetUsage() }
            }
        } header: {
            Text("利用状況")
        } footer: {
            Text("よく使う機能を知るための集計です（端末内のみ）。AI に質問するとき、この集計（位置を含まない）を参考情報として渡します。")
        }
        .confirmationDialog("訪問した場所をすべて削除しますか？", isPresented: $confirmDeleteVisits, titleVisibility: .visible) {
            Button("削除", role: .destructive) { model.history.deleteVisits() }
        }
    }

    struct Row: Identifiable {
        let id: String
        let value: String
    }

    private var detectionRows: [Row] {
        var counts: [DetectionLabel: Int] = [:]
        for e in model.history.detectionLog { counts[e.label, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map { Row(id: $0.key.displayName, value: "\($0.value)回") }
    }

    private func usageRows(_ usage: UsageStats) -> [Row] {
        var rows: [Row] = []
        for p in usage.topPresets() { rows.append(Row(id: "プリセット：\(p.name)", value: HUDFormat.duration(p.seconds))) }
        for c in usage.topCommands() { rows.append(Row(id: c.name, value: "\(c.count)回")) }
        return rows
    }
}

// MARK: - 頭の動き（ヘッドトラッキング）

struct HeadTrackingSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let h = model.settings.headTracking
        let ht = model.headTracking
        Form {
            Section {
                Picker("頭の向きの取り方", selection: $model.settings.headTracking.source) {
                    ForEach(HeadTrackingSource.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Text(h.source.detail).font(.caption).foregroundStyle(.secondary)
                LabeledContent("状態", value: ht.status)
                if let p = ht.pose {
                    LabeledContent("正面からのずれ", value: String(format: "左右 %+.0f°・上下 %+.0f°・傾き %+.0f°", p.yaw, p.pitch, p.roll))
                    LabeledContent("更新", value: String(format: "%.0f 回/秒", ht.sampleRate))
                }
                Button("今の向きを正面にする") { ht.recenter() }
                    .disabled(h.source == .off)
            } header: {
                Text("センサー")
            } footer: {
                Text("VITURE 本体のセンサーは iOS から公式には読めないため、ほかの方法で頭の向きを取ります。")
            }

            if h.source == .bleSensor { BLEIMUSection() }
            if h.source == .glassesUSB { GlassesUSBSection() }

            Section {
                Toggle("HUD を空間に固定", isOn: $model.settings.headTracking.headLock)
                LabeledSlider(title: "固定の強さ（1度あたり）", value: $model.settings.headTracking.strength, range: 5...80, format: { "\(Int($0)) px" })
                Toggle("傾けても HUD を水平に保つ", isOn: $model.settings.headTracking.compensatesRoll)
                LabeledSlider(title: "なめらかさ", value: $model.settings.headTracking.smoothing, range: 0...0.9, format: { "\(Int($0 * 100))%" })
            } header: {
                Text("空間固定")
            } footer: {
                Text("頭を右に向けると HUD が左に動き、空間に留まって見えます。向きが逆なら下の「反転」を使ってください。")
            }

            Section {
                Toggle("左右を反転", isOn: $model.settings.headTracking.invertYaw)
                Toggle("上下を反転", isOn: $model.settings.headTracking.invertPitch)
                Toggle("傾きを反転", isOn: $model.settings.headTracking.invertRoll)
                Toggle("上下と傾きを入れ替える（センサーを横向きに付けた場合）", isOn: $model.settings.headTracking.swapPitchRoll)
            } header: {
                Text("向きの調整")
            }

            Section {
                Toggle("頭のジェスチャーで操作", isOn: $model.settings.headTracking.gesturesEnabled)
                Picker("うなずく", selection: $model.settings.headTracking.nodAction) { actions }
                Picker("首を横に振る", selection: $model.settings.headTracking.shakeAction) { actions }
                Picker("首を左にかしげる", selection: $model.settings.headTracking.tiltLeftAction) { actions }
                Picker("首を右にかしげる", selection: $model.settings.headTracking.tiltRightAction) { actions }
                if let g = ht.lastGesture, let at = ht.lastGestureAt {
                    LabeledContent("最後のジェスチャー", value: "\(g.displayName)（\(HUDFormat.clock(at, seconds: true))）")
                }
            } header: {
                Text("ジェスチャー")
            } footer: {
                Text("うなずき＝下→上にすばやく、首振り＝左右に 2 往復、かしげる＝傾けたまま 0.5 秒。")
            }

            Section {
                Toggle("下を見たときだけ詳しく表示", isOn: $model.settings.headTracking.glanceMode)
                LabeledSlider(title: "下を向いたとみなす角度", value: $model.settings.headTracking.glanceAngle, range: 5...40, format: { "\(Int($0))°" })
                if h.glanceMode {
                    LabeledContent("今", value: ht.isGlancing ? "下を見ている（詳しく表示）" : "前を見ている（時計・曲がり角・通知だけ）")
                }
            } header: {
                Text("チラ見モード")
            }
        }
        .navigationTitle("頭の動き")
        .serviceDemand([.headTracking])
    }

    @ViewBuilder private var actions: some View {
        ForEach(HeadGestureAction.allCases, id: \.self) { Text($0.displayName).tag($0) }
    }
}

/// Bluetooth の動きセンサーの接続
struct BLEIMUSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ble = model.headTracking.ble
        Section {
            LabeledContent("状態", value: ble.state)
            if let name = ble.connectedName {
                LabeledContent("接続中", value: "\(name)\(ble.kind.map { "（\($0)）" } ?? "")")
                if ble.kind == "WitMotion" {
                    HStack {
                        Button("20Hz") { ble.setWitMotionRate(20) }
                        Button("50Hz") { ble.setWitMotionRate(50) }
                        Button("100Hz") { ble.setWitMotionRate(100) }
                    }
                    .buttonStyle(.bordered)
                }
                if let a = ble.lastAcceleration {
                    LabeledContent("加速度", value: String(format: "%.2f / %.2f / %.2f G", a.x, a.y, a.z))
                }
            }
            Button("センサーを探す") { ble.scan() }
            ForEach(ble.found) { d in
                Button {
                    ble.connect(d.id)
                } label: {
                    HStack {
                        Text(d.name)
                        Spacer()
                        Text("\(d.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let name = model.settings.headTracking.rememberedSensorName {
                LabeledContent("記憶しているセンサー", value: name)
                Button("記憶を消す", role: .destructive) {
                    model.settings.headTracking.rememberedSensorID = nil
                    model.settings.headTracking.rememberedSensorName = nil
                }
            }
        } header: {
            Text("Bluetooth の動きセンサー")
        } footer: {
            Text("WitMotion の Bluetooth 5.0 センサー（WT901BLECL など・数千円）を VITURE のつるにテープで付けると、グラスそのものの向き・加速度が取れます。ESP32 などで自作する場合は、リポジトリの Extensions/Hardware のスケッチを使ってください。")
        }
    }
}

/// VITURE 本体（USB）の診断
struct GlassesUSBSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ht = model.headTracking
        Section {
            LabeledContent("受信したデータ", value: "\(ht.usbPackets) 件")
            ForEach(Array(ht.usbLog.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption2.monospaced())
            }
            Button("結果をコピー（報告用）") {
                UIPasteboard.general.string = ht.usbLog.joined(separator: "\n")
                model.showToast("コピーしました")
            }
        } header: {
            Text("VITURE 本体（USB・実験）の記録")
        } footer: {
            Text("公開されている解析結果（オープンソース）を元に、USB の HID 経由でセンサーの送信を始める命令を送ります。iOS が一般のアプリに USB 機器を開かせない場合は「許可されていません」と表示されます。")
        }
    }
}

// MARK: - 距離・3D（ビジョン画面）

struct DepthSettingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let s = model.settings.depth
        let d = model.depth
        Card(title: "距離・3D", systemImage: "ruler") {
            Toggle("距離を推定する", isOn: $model.settings.depth.enabled)
            Picker("方法", selection: $model.settings.depth.source) {
                ForEach(DepthSourceKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Text("この端末：LiDAR \(DepthService.hasLiDAR ? "あり" : "なし")・2 つのカメラ \(DepthService.hasDualCamera ? "あり" : "なし")・AI 推定 あり → 使う方法：\(DepthService.resolve(s.source).displayName)")
                .font(.caption).foregroundStyle(.secondary)
            if s.enabled {
                LabeledContent("状態", value: d.status)
                if !d.aiStatus.isEmpty { Text(d.aiStatus).font(.caption) }
                LabeledContent("正面まで", value: d.centerDistance.map { String(format: "%.2f m", $0) } ?? "--")
                if let o = d.obstacle { LabeledContent("近くの物", value: "\(o.direction) \(String(format: "%.1f", o.distance)) m") }
                if d.activeSource == .aiMonocular { LabeledContent("AI の処理時間", value: "\(Int(d.inferenceMs)) ms") }
            }
            LabeledSlider(title: "端末を持つ高さ（AI の換算用）", value: $model.settings.depth.cameraHeight, range: 0.5...2.0, format: { String(format: "%.2f m", $0) })
            LabeledSlider(title: "AI 推定の回数", value: $model.settings.depth.aiFPS, range: 1...10, format: { String(format: "%.0f 回/秒", $0) })
            Toggle("距離の数字を表示", isOn: $model.settings.depth.showsGrid)
            Toggle("距離を色で表示", isOn: $model.settings.depth.showsHeatmap)
            Toggle("中央の照準と距離", isOn: $model.settings.depth.showsReticle)
            Toggle("検出した物に距離を付ける", isOn: $model.settings.depth.showsObjectDistance)
            Toggle("近くの物を知らせる", isOn: $model.settings.depth.obstacleAlerts)
            LabeledSlider(title: "知らせる距離", value: $model.settings.depth.obstacleDistance, range: 0.5...4, format: { String(format: "%.1f m", $0) })
            Text("AI 推定は「地面がどう見えるか」から m に直すので、端末を少し下に向けて地面が映るようにすると正確になります。何の物か分からなくても、近い物はすべて知らせます。距離は目安です。")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                model.showsScan3D = true
            } label: {
                Label("3D スキャン（周りを立体的に記録・測定）", systemImage: "cube.transparent")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
