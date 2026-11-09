import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - 履歴・分析

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var period: StatsPeriod = .day
    @State private var confirmDelete = false
    @State private var share: ShareItem?
    @State private var analysis: String?
    @State private var analyzing = false

    var body: some View {
        @Bindable var model = model
        let trips = model.history.trips
        let buckets = HistoryStats.buckets(trips, period: period)
        Form {
            Section {
                Toggle("移動履歴を記録する", isOn: $model.settings.history.enabled)
                Toggle("ルート（位置の点列）も保存", isOn: $model.settings.history.recordsRoutePoints)
                    .disabled(!model.settings.history.enabled)
                Toggle("物体検出の件数も保存", isOn: $model.settings.history.recordsDetections)
                    .disabled(!model.settings.history.enabled)
                Picker("保存期間", selection: $model.settings.history.retentionDays) {
                    Text("7日").tag(7)
                    Text("30日").tag(30)
                    Text("90日").tag(90)
                    Text("1年").tag(365)
                    Text("無期限").tag(0)
                }
                .disabled(!model.settings.history.enabled)
            } header: {
                Text("記録")
            } footer: {
                Text("記録は端末内にだけ保存します（初期設定はオフ）。ナビ中は自動で記録し、下のボタンで手動でも記録できます。")
            }
            if model.settings.history.enabled {
                Section {
                    if model.history.isRecording {
                        LabeledContent("記録中", value: HUDFormat.distance(model.history.currentDistance))
                        Button("記録を終える") { model.history.stop(settings: model.settings.history) }
                    } else {
                        Button("今から記録する") {
                            model.history.start(settings: model.settings.history)
                            model.refreshServices()
                        }
                    }
                }
            }
            Section("集計") {
                Picker("期間", selection: $period) {
                    ForEach(StatsPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                if buckets.isEmpty {
                    Text("記録がありません").foregroundStyle(.secondary)
                } else {
                    Chart(buckets) { b in
                        BarMark(x: .value("期間", b.start, unit: chartUnit), y: .value("距離(km)", b.distance / 1000))
                            .foregroundStyle(UIStyle.accent)
                    }
                    .frame(height: 180)
                    let total = trips.reduce(0) { $0 + $1.distance }
                    let time = trips.reduce(0) { $0 + $1.duration }
                    LabeledContent("合計距離", value: HUDFormat.distance(total))
                    LabeledContent("合計時間", value: HUDFormat.duration(time))
                    LabeledContent("平均速度", value: "\(HUDFormat.speed(time > 0 ? total / time : 0, unit: .kilometersPerHour)) km/h")
                    LabeledContent("最高速度", value: "\(HUDFormat.speed(trips.map(\.maxSpeed).max() ?? 0, unit: .kilometersPerHour)) km/h")
                }
            }
            Section {
                Button {
                    Task { await analyze() }
                } label: {
                    if analyzing { ProgressView() } else { Label("AI で傾向を分析", systemImage: "sparkles") }
                }
                .disabled(trips.isEmpty || analyzing)
                if let analysis { Text(analysis).font(.subheadline) }
            } footer: {
                Text("AI には集計値だけを送ります（位置は送りません）。クラウドAIが未設定の場合は端末内の集計だけを表示します。")
            }
            Section("記録の一覧") {
                ForEach(trips.reversed()) { trip in
                    VStack(alignment: .leading) {
                        Text("\(HUDFormat.date(trip.startedAt)) \(HUDFormat.clock(trip.startedAt))〜\(HUDFormat.clock(trip.endedAt))")
                        Text("\(HUDFormat.distance(trip.distance))・\(HUDFormat.duration(trip.duration))\(trip.destinationName.map { "・\($0)" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("削除", role: .destructive) { model.history.delete([trip.id]) }
                        if !trip.points.isEmpty {
                            Button("GPX") { share = exportGPX(trip) }.tint(.blue)
                        }
                    }
                }
                if !trips.isEmpty {
                    Button("すべての履歴を削除", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle("履歴・分析")
        .confirmationDialog("すべての履歴を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { model.history.deleteAll() }
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
    }

    private var chartUnit: Calendar.Component {
        switch period {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    private func analyze() async {
        analyzing = true
        defer { analyzing = false }
        let summary = HistoryStats.summaryText(model.history.trips)
        let s = model.settings.assistant
        if s.provider.isCloud && s.cloudConsentGiven && model.network.isOnline {
            do {
                analysis = try await CloudAssistant.ask("次の移動記録の集計から、移動の傾向を3文以内で説明してください。", context: summary, settings: s, network: model.network)
            } catch {
                analysis = summary + "\n\n" + error.localizedDescription
            }
        } else {
            analysis = summary
        }
    }

    private func exportGPX(_ trip: TripRecord) -> ShareItem? {
        let step = trip.duration / Double(max(1, trip.points.count - 1))
        let samples = trip.points.enumerated().map { i, c in
            LocationSample(coordinate: c, timestamp: trip.startedAt.addingTimeInterval(Double(i) * step))
        }
        let text = GPX.export(name: "HUD Navigator \(HUDFormat.date(trip.startedAt))", points: samples)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trip-\(Int(trip.startedAt.timeIntervalSince1970)).gpx")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return ShareItem(url: url)
    }
}

// MARK: - 天気

struct WeatherDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("天気を取得する", isOn: $model.settings.privacy.weatherEnabled)
            } footer: {
                Text("Open-Meteo（無料・APIキー不要・非商用）から取得します。送るのは小数3桁（約100m）に丸めた現在地だけです。")
            }
            if let w = model.weather.snapshot {
                Section("現在") {
                    LabeledContent("天気", value: w.conditionText)
                    LabeledContent("気温", value: w.temperature.map { String(format: "%.1f℃", $0) } ?? "取得できません")
                    LabeledContent("体感温度", value: w.apparentTemperature.map { String(format: "%.1f℃", $0) } ?? "取得できません")
                    LabeledContent("降水確率", value: w.precipitationProbability.map { "\(Int($0))%" } ?? "取得できません")
                    LabeledContent("降水量", value: w.precipitation.map { String(format: "%.1f mm", $0) } ?? "取得できません")
                    LabeledContent("湿度", value: w.humidity.map { "\(Int($0))%" } ?? "取得できません")
                    LabeledContent("風", value: w.windSpeed.map { String(format: "%@ %.1f m/s", w.windDirectionName ?? "", $0) } ?? "取得できません")
                    LabeledContent("紫外線指数", value: w.uvIndex.map { String(format: "%.1f", $0) } ?? "取得できません")
                }
                Section("空気質") {
                    LabeledContent("PM2.5", value: w.pm25.map { String(format: "%.1f μg/m³", $0) } ?? "取得できません")
                    LabeledContent("PM10", value: w.pm10.map { String(format: "%.1f μg/m³", $0) } ?? "取得できません")
                    LabeledContent("大気質指数（欧州）", value: w.europeanAQI.map { "\(Int($0))（\(w.airQualityText ?? "")）" } ?? "取得できません")
                }
                Section("出典") {
                    LabeledContent("提供元", value: w.source)
                    LabeledContent("取得", value: "\(HUDFormat.date(w.fetchedAt)) \(HUDFormat.clock(w.fetchedAt))")
                    if let obs = w.observationTime { LabeledContent("データの時刻", value: HUDFormat.clock(obs)) }
                    Link("Weather data by Open-Meteo.com（CC BY 4.0）", destination: URL(string: w.sourceURL)!)
                }
            } else {
                Section {
                    Text(model.weather.lastError ?? (model.location.lastSample == nil ? "現在地を取得しています…" : "取得していません"))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("今すぐ更新") {
                    if let c = model.location.lastSample?.coordinate { Task { await model.weather.refresh(at: c) } }
                }
                .disabled(model.location.lastSample == nil || !model.settings.privacy.weatherEnabled)
            }
        }
        .navigationTitle("天気・環境情報")
        .serviceDemand([.location, .weather])
    }
}

// MARK: - データ・同期

struct SyncView: View {
    @Environment(AppModel.self) private var model
    @State private var includeHistory = false
    @State private var strategy: SettingsBundle.MergeStrategy = .merge
    @State private var share: ShareItem?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Text("iPad と iPhone で設定をそろえるには、片方で「書き出し」→「ファイルに保存」で iCloud Drive に保存し、もう片方で「読み込み」を選びます。")
                    .font(.subheadline)
            } header: {
                Text("同期のしかた")
            } footer: {
                Text("自動同期（iCloud / CloudKit）は有料の Apple Developer Program が必要なため、ファイルでの同期にしています。")
            }
            Section("書き出し") {
                Toggle("移動履歴も含める", isOn: $includeHistory)
                Button {
                    if let url = model.exportBundleFile(includeHistory: includeHistory) { share = ShareItem(url: url) }
                } label: {
                    Label("設定・テーマ・プリセット・お気に入りを書き出す", systemImage: "square.and.arrow.up")
                }
            }
            Section {
                Picker("読み込み方", selection: $strategy) {
                    Text("追加・上書き").tag(SettingsBundle.MergeStrategy.merge)
                    Text("置き換え").tag(SettingsBundle.MergeStrategy.replace)
                }
                .pickerStyle(.segmented)
                Button {
                    importing = true
                } label: {
                    Label("ファイルから読み込む", systemImage: "square.and.arrow.down")
                }
                if let message { Text(message).font(.footnote) }
            } header: {
                Text("読み込み")
            } footer: {
                Text("組み込みのテーマ・プリセットは常に残ります。APIキーと各種同意は端末ごとの設定のため読み込みません。")
            }
        }
        .navigationTitle("データ・同期")
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { message = model.importFile(url, strategy: strategy) }
        }
    }
}

// MARK: - プライバシー

struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("このアプリが扱うデータ") {
                Label("カメラ映像：端末内で処理し、保存・送信しない", systemImage: "camera")
                Label("位置情報：端末内で使用。天気取得時のみ丸めた座標を送信", systemImage: "location")
                Label("音声：端末内で文字にする（設定による）", systemImage: "mic")
                Label("移動履歴：保存は任意（初期はオフ）・端末内のみ", systemImage: "clock")
                Label("AIへの質問：クラウドAIを設定・同意した場合のみ、文字だけを送信", systemImage: "cloud")
            }
            .font(.footnote)
            Section("設定") {
                Toggle("天気を取得する（Open-Meteo）", isOn: $model.settings.privacy.weatherEnabled)
                Toggle("書き出すレポートの位置を丸める", isOn: $model.settings.privacy.roundsExportedLocations)
                Toggle("AIに地名（おおよその現在地）を伝える", isOn: $model.settings.assistant.sharesApproximateLocation)
            }
            Section {
                if model.network.entries.isEmpty {
                    Text("まだ通信していません").foregroundStyle(.secondary)
                }
                ForEach(model.network.entries) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(HUDFormat.clock(e.date, seconds: true))  \(e.host)").font(.caption.monospaced())
                        Text("\(e.purpose)・送信 \(e.bytesSent)B・受信 \(e.bytesReceived)B・\(e.status.map { "HTTP \($0)" } ?? (e.error ?? ""))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if !model.network.entries.isEmpty { Button("記録を消去") { model.network.clear() } }
            } header: {
                Text("通信ログ（このアプリからの外部通信）")
            } footer: {
                Text("地図・検索・経路は Apple の MapKit を使います（Apple のサービスとの通信はこの一覧に含まれません）。")
            }
            Section {
                Button("すべてのデータを削除", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("設定・テーマ・プリセット・履歴・お気に入り・APIキー・読み込んだモデルを削除し、初期状態に戻します。")
            }
        }
        .navigationTitle("プライバシー")
        .confirmationDialog("すべてのデータを削除しますか？元に戻せません。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive) { model.deleteAllData() }
        }
    }
}

// MARK: - AIアシスタント

struct AssistantSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKey = ""
    @State private var hasKey = false
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        @Bindable var model = model
        let s = model.settings.assistant
        Form {
            Section {
                Picker("回答の方法", selection: $model.settings.assistant.provider) {
                    ForEach(AssistantProviderKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("回答を読み上げる", isOn: $model.settings.assistant.speaksResponses)
                Toggle("音声認識は端末内だけで行う", isOn: $model.settings.assistant.requiresOnDeviceSpeech)
            } footer: {
                Text("「端末内のみ」でも、音声コマンド（背景切替・ナビ・ウィジェット表示など）と時刻・電池・到着予定などの読み上げは使えます。端末内の生成AI（Apple Intelligence）は A16 チップでは使えません。")
            }
            if s.provider.isCloud {
                Section {
                    TextField("モデル（空欄で \(s.provider.defaultModel)）", text: $model.settings.assistant.model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("接続先（空欄で標準）", text: $model.settings.assistant.baseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField(hasKey ? "APIキー（保存済み・変更する場合のみ入力）" : "APIキー", text: $apiKey)
                    HStack {
                        Button("APIキーを保存") {
                            KeychainStore.save(apiKey, account: CloudAssistant.keyAccount(s.provider))
                            apiKey = ""
                            refreshKeyState()
                        }
                        .disabled(apiKey.isEmpty)
                        Spacer()
                        if hasKey {
                            Button("削除", role: .destructive) {
                                KeychainStore.delete(account: CloudAssistant.keyAccount(s.provider))
                                refreshKeyState()
                            }
                        }
                    }
                } header: {
                    Text("接続")
                } footer: {
                    Text(costNote(s.provider) + " APIキーは端末の Keychain に保存し、ログや書き出しファイルには含めません。")
                }
                Section {
                    Toggle("送信に同意する", isOn: $model.settings.assistant.cloudConsentGiven)
                    Text("送信するもの：あなたの質問の文字、現在時刻、案内中の目的地・残り時間、天気の概要（同意した場合は地名）。送信しないもの：カメラ映像、正確な位置座標、音声データ。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("同意")
                }
                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        if testing { ProgressView() } else { Text("接続をテスト") }
                    }
                    .disabled(!hasKey || !s.cloudConsentGiven || testing)
                    if let testResult { Text(testResult).font(.footnote) }
                }
            }
        }
        .navigationTitle("AIアシスタント")
        .onAppear { refreshKeyState() }
        .onChange(of: model.settings.assistant.provider) { _, _ in refreshKeyState() }
    }

    private func refreshKeyState() {
        hasKey = KeychainStore.load(account: CloudAssistant.keyAccount(model.settings.assistant.provider)) != nil
    }

    private func costNote(_ p: AssistantProviderKind) -> String {
        switch p {
        case .gemini: return "Google AI Studio で APIキーを取得します。無料枠があります（回数制限あり。無料枠では送信内容がサービス改善に使われる場合があります）。"
        case .anthropic: return "Anthropic Console で APIキーを取得します。従量課金です。料金を抑えたい場合はモデルに claude-haiku-5-5 を指定できます。"
        case .openAICompatible: return "OpenAI など互換 API の APIキーを使います。多くは従量課金です。"
        case .localOnly: return ""
        }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        do {
            let answer = try await CloudAssistant.ask("接続テストです。「接続できました」とだけ答えてください。", context: "", settings: model.settings.assistant, network: model.network)
            testResult = "成功：\(answer)"
        } catch {
            testResult = "失敗：\(error.localizedDescription)"
        }
    }
}

// MARK: - ショートカット

struct ShortcutsInfoView: View {
    var body: some View {
        Form {
            #if FULL_BUILD
            Section {
                Text("ショートカット App や Siri から次の操作を呼び出せます。")
                ForEach(["「HUD Navigator で HUD を開始」", "「HUD Navigator で背景を切り替え」", "「HUD Navigator のプリセットを適用」", "「HUD Navigator でナビを開始」", "「HUD Navigator でナビを終了」", "「HUD Navigator で音声案内を切り替え」"], id: \.self) {
                    Label($0, systemImage: "square.on.square")
                }
            } footer: {
                Text("ショートカット App の「アクションを追加」で「HUD Navigator」を検索してください。")
            }
            #else
            Section {
                Text("ショートカット連携は正式アプリ（AltStore でインストールした IPA）でのみ使えます。Swift Playgrounds 版では使えません。")
            }
            #endif
        }
        .navigationTitle("ショートカット")
    }
}
