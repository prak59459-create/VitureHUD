import SwiftUI

// MARK: - 詳細・診断

struct AdvancedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("表示") {
                Toggle("計測値を HUD に表示（fps・温度・電池）", isOn: $model.settings.showsMetricsOverlay)
                Button("視認性テストを表示") { model.showsTestPattern = true }
            }
            Section {
                Toggle("自動で省電力にする", isOn: $model.settings.power.automaticPowerSaving)
                Toggle("HUD 表示中は自動ロックしない", isOn: $model.settings.power.keepsScreenAwake)
                LabeledContent("現在のレベル", value: model.powerProfile.quality.displayName)
                LabeledContent("カメラ", value: "\(model.powerProfile.cameraFPS)fps・\(model.powerProfile.cameraMaxHeight)p")
                LabeledContent("推論", value: String(format: "最大 %.0f 回/秒", model.powerProfile.inferenceFPS))
            } header: {
                Text("電力・発熱")
            } footer: {
                Text("端末が熱くなったり電池が少なくなったりすると、カメラ・推論・センサーの頻度を自動で下げます。")
            }
            Section("ビルド") {
                LabeledContent("実行環境", value: DeviceTestModel.environment.displayName)
                LabeledContent("バージョン", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                LabeledContent("端末", value: "\(model.device.hardwareIdentifier)・\(model.device.systemVersion)")
            }
            Section("通知の履歴") {
                if model.alerts.history.isEmpty { Text("なし").foregroundStyle(.secondary) }
                ForEach(model.alerts.history.prefix(30)) { a in
                    VStack(alignment: .leading) {
                        Text("\(HUDFormat.clock(a.createdAt, seconds: true)) \(a.category.displayName)：\(a.title)").font(.caption)
                        if !a.message.isEmpty { Text(a.message).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("詳細・診断")
    }
}

// MARK: - 実機テストモード

struct DeviceTestView: View {
    @Environment(AppModel.self) private var model
    @State private var share: ShareItem?
    @State private var confirmReset = false

    var body: some View {
        let test = model.deviceTest
        let items = test.items
        let entries = items.map { test.entry(for: $0.id) }
        Form {
            Section {
                LabeledContent("実行環境", value: DeviceTestModel.environment.displayName)
                LabeledContent("結果", value: "OK \(entries.filter { $0.result == .pass }.count)・NG \(entries.filter { $0.result == .fail }.count)・未実施 \(entries.filter { $0.result == .notRun }.count)")
                Toggle("計測を記録（10秒ごと）", isOn: Binding(
                    get: { test.isRecordingMetrics },
                    set: { on in
                        if on { model.metrics.start(); test.startMetrics() } else { test.stopMetrics() }
                    }
                ))
                LabeledContent("記録した計測", value: "\(test.metrics.count)件")
                Button {
                    let report = test.report(deviceModel: model.device.hardwareIdentifier, systemVersion: model.device.systemVersion, externalDisplay: model.display.isExternalConnected ? model.display.statusDescription : nil)
                    if let url = test.exportFile(report, roundLocations: model.settings.privacy.roundsExportedLocations) { share = ShareItem(url: url) }
                } label: {
                    Label("結果を書き出す（GitHub Issue に添付）", systemImage: "square.and.arrow.up")
                }
                Button("結果をリセット", role: .destructive) { confirmReset = true }
            } header: {
                Text("実機テスト")
            } footer: {
                Text("Swift Playgrounds では何度でも、AltStore の正式アプリは週7回までを目安に確認してください。書き出したファイルの位置情報は丸められます（設定 → プライバシー）。")
            }
            ForEach(0...7, id: \.self) { phase in
                let phaseItems = items.filter { $0.phase == phase }
                if !phaseItems.isEmpty {
                    Section("Phase \(phase)") {
                        ForEach(phaseItems) { item in
                            ChecklistRow(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle("実機テストモード")
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .confirmationDialog("テスト結果をリセットしますか？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("リセット", role: .destructive) { test.reset() }
        }
    }
}

struct ChecklistRow: View {
    @Environment(AppModel.self) private var model
    let item: ChecklistItem
    @State private var note = ""

    var body: some View {
        let test = model.deviceTest
        let entry = test.entry(for: item.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(item.title).font(.subheadline.bold())
                if let note = item.deviceNote { Text(note).font(.caption2).padding(.horizontal, 4).background(Color(.tertiarySystemFill), in: Capsule()) }
            }
            Text("手順：\(item.steps)").font(.caption)
            Text("期待：\(item.expected)").font(.caption).foregroundStyle(.secondary)
            Picker("結果", selection: Binding(get: { entry.result }, set: { test.set(item.id, result: $0) })) {
                ForEach(CheckResult.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("メモ（読めた文字サイズ・気づいたこと）", text: $note)
                .font(.caption)
                .onSubmit { test.setNote(item.id, note: note) }
                .onChange(of: note) { _, v in test.setNote(item.id, note: v) }
        }
        .padding(.vertical, 4)
        .onAppear { note = entry.note }
    }
}

// MARK: - このアプリについて

struct AboutView: View {
    var body: some View {
        Form {
            Section("安全") {
                Text("・自動車・自転車などの運転中には使用しないでください。")
                Text("・物体認識・危険検知は実験的な補助機能で、安全装置ではありません。")
                Text("・歩行中も周囲の安全を最優先にし、HUD で視界を塞がないでください。")
                Text("・距離・到着時刻などは目安です。")
            }
            .font(.footnote)
            Section("データの提供元") {
                Text("地図・検索・経路：Apple MapKit")
                Link("天気・空気質：Open-Meteo.com（CC BY 4.0）", destination: URL(string: "https://open-meteo.com/")!)
                Text("物体認識：Apple Vision（内蔵）／ユーザーが読み込んだ Core ML モデル")
                Text("音声：Apple Speech・AVSpeechSynthesizer")
            }
            .font(.footnote)
            Section("対応機器") {
                Text("iPad（A16）・iPhone 15 で開発・検証しています。VITURE などの USB-C 接続 XR グラスを外部ディスプレイとして使います。VITURE は各社の商標です。本アプリは VITURE 社の公式アプリではありません。")
                    .font(.footnote)
            }
        }
        .navigationTitle("このアプリについて")
    }
}
