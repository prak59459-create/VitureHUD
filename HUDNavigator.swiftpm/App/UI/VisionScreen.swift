import SwiftUI
import UniformTypeIdentifiers

struct VisionScreen: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NoticeBanner(text: "物体認識・危険検知は実験的な補助機能です。安全装置ではありません。誤検知・検知漏れがあります。", systemImage: "exclamationmark.triangle.fill")
                    ZStack {
                        CameraBackground(surface: .visionLab)
                        if model.detectionActive && model.camera.activeSurface == .visionLab {
                            DetectionOverlay()
                        }
                    }
                    .aspectRatio(model.camera.imageAspect > 1 ? 16 / 9 : 3 / 4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: UIStyle.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius, style: .continuous).strokeBorder(UIStyle.cardStroke, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if model.camera.isRunning {
                            Label("カメラ使用中", systemImage: "circle.fill")
                                .font(.caption.bold()).foregroundStyle(.red)
                                .padding(6).background(.black.opacity(0.5), in: Capsule()).padding(8)
                        }
                    }
                    VisionStatsCard()
                    DepthSettingsCard()
                    VisionDiagnosticsCard()
                    Card(title: "物体認識", systemImage: "viewfinder") {
                        Toggle("物体認識を使う", isOn: Binding(
                            get: { model.settings.detection.enabled },
                            set: { on in
                                if on && !model.settings.detection.hasAcceptedDisclaimer {
                                    model.showsVisionDisclaimer = true
                                } else {
                                    model.settings.detection.enabled = on
                                }
                            }
                        ))
                        Toggle("歩行者を検出（内蔵）", isOn: $model.settings.detection.detectsPeople)
                        Toggle("犬・猫を検出（内蔵）", isOn: $model.settings.detection.detectsAnimals)
                        Toggle("ラベルを表示", isOn: $model.settings.detection.showsLabels)
                        Toggle("信頼度を表示", isOn: $model.settings.detection.showsConfidence)
                        Toggle("距離の目安を表示", isOn: $model.settings.detection.showsDistanceEstimate)
                        LabeledSlider(title: "最低信頼度", value: $model.settings.detection.minimumConfidence, range: 0.2...0.95, format: { "\(Int($0 * 100))%" })
                        LabeledSlider(title: "推論の回数（1秒あたり）", value: $model.settings.detection.inferenceFPS, range: 1...15, format: { String(format: "%.0f回", $0) })
                        Text("回数を減らすと発熱と電池消費が減ります。端末が熱くなると自動で減らします。").font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "危険検知（実験）", systemImage: "exclamationmark.triangle") {
                        Toggle("接近を警告する", isOn: Binding(
                            get: { model.settings.detection.hazardAlertsEnabled },
                            set: { on in
                                if on && !model.settings.detection.hasAcceptedDisclaimer {
                                    model.showsVisionDisclaimer = true
                                } else {
                                    model.settings.detection.hazardAlertsEnabled = on
                                    if on { model.settings.detection.enabled = true }
                                }
                            }
                        ))
                        Text("画面の中央で枠が急に大きくなる物体（近づいてくる物体）を警告します。カメラの向き・速さ・手ぶれで結果が変わります。警告が出ないことは安全を意味しません。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "路面の線・標識（実験）", systemImage: "road.lanes") {
                        Toggle("路面の白線（車線）を表示", isOn: $model.settings.detection.detectsLanes)
                        Toggle("標識・看板の文字を読む", isOn: $model.settings.detection.readsSigns)
                        if let sign = model.lastSign {
                            LabeledContent("最後に読んだ標識", value: "\(sign.kind)（\(sign.text)）")
                        }
                        Text("白線は輪郭から「まっすぐで斜めの線」を探す簡易的な推定です。標識は文字（止まれ・徐行・通行止め など）から種類を推定し、重要なものは HUD で知らせます。どちらも見落とし・誤認識があります。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "物体検出モデル（アプリに内蔵）", systemImage: "cpu") {
                        Toggle("物体検出モデルを使う（80 種類）", isOn: $model.settings.detection.usesCustomModel)
                        Picker("モデル", selection: $model.settings.detection.objectModel) {
                            ForEach(BundledObjectModel.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                            if let name = model.vision.customModelName {
                                Text("読み込んだモデル（\(name)）").tag("custom")
                            }
                        }
                        if let m = BundledObjectModel(rawValue: model.settings.detection.objectModel) {
                            Text(m.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        if !model.vision.objectModelStatus.isEmpty {
                            Text(model.vision.objectModelStatus).font(.caption)
                        }
                        Toggle("黒背景（グラスで透明）でも認識する", isOn: $model.settings.detection.runsWithBlackBackground)
                        Toggle("黒背景でも検出枠を HUD に描く（位置はおおよそ）", isOn: $model.settings.detection.showsBoxesOnBlack)
                        Text(BundledObjectModel.credit).font(.caption2).foregroundStyle(.secondary)
                        Divider()
                        Text("別の物体検出モデル（.mlmodel）も読み込めます。モデルのライセンスはご自身で確認してください。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let name = model.vision.customModelName {
                            Label("読み込み済み：\(name)", systemImage: "checkmark.circle").foregroundStyle(.green)
                            Button("読み込んだモデルを削除", role: .destructive) {
                                model.vision.removeCustomModel()
                                if model.settings.detection.objectModel == "custom" { model.settings.detection.objectModel = BundledObjectModel.yolov3Tiny.rawValue }
                            }
                        }
                        Button {
                            importing = true
                        } label: {
                            Label("モデルを読み込む", systemImage: "square.and.arrow.down")
                        }
                        if let status = model.vision.modelStatus { Text(status).font(.caption) }
                    }
                    Card(title: "カメラ", systemImage: "camera") {
                        LabeledSlider(title: "明るさ（露出補正）", value: $model.settings.camera.exposureBias, range: -2...2, format: { String(format: "%+.1f EV", $0) })
                        LabeledSlider(title: "ズーム", value: $model.settings.camera.zoom, range: 1...4, format: { String(format: "×%.1f", $0) })
                        LabeledSlider(title: "コントラスト", value: $model.settings.camera.contrast, range: 0.5...1.5, format: { String(format: "%.2f", $0) })
                        Toggle("超広角カメラを使う（iPhone）", isOn: $model.settings.camera.prefersUltraWide)
                        Toggle("外部カメラを使う（iPad の USB-C カメラ）", isOn: $model.settings.camera.useExternalCamera)
                        if model.settings.camera.useExternalCamera {
                            let cameras = CameraPipeline.externalCameras
                            Text(cameras.isEmpty ? "外部カメラが見つかりません（つなぐと自動で切り替わります。見つからない間は内蔵カメラを使います）。" : "接続中：" + cameras.map(\.localizedName).joined(separator: "、"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("カメラ映像は端末内でのみ処理し、保存・送信しません。グラスは光学透過のため、カメラ映像は二重に見えることがあります。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .padding(.bottom, 90)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle("ビジョン")
        }
        .sheet(isPresented: $model.showsVisionDisclaimer) {
            VisionDisclaimerSheet()
                .environment(model)
                .tint(UIStyle.accent)
                .fontDesign(.rounded)
                .preferredColorScheme(.dark)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "mlmodel") ?? .data, .data]) { result in
            if case .success(let url) = result {
                Task {
                    await model.vision.importModel(from: url)
                    if model.vision.customModelName != nil { model.settings.detection.objectModel = "custom" }
                }
            }
        }
    }
}

/// 認識が動いているかを確かめる（フレームが届いているか・推論が動いているか・エラー）
struct VisionDiagnosticsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let stats = model.vision.engine.stats
            let cam = model.camera
            Card(title: "動作の確認", systemImage: "stethoscope") {
                LabeledContent("物体認識", value: model.detectionActive ? "オン" : (model.settings.detection.hasAcceptedDisclaimer ? "オフ" : "注意事項の同意がまだです"))
                LabeledContent("カメラ", value: cam.isRunning ? "動作中（\(cam.activeSurface == nil ? "映像なし" : "映像あり")）" : "停止中")
                LabeledContent("届いたフレーム", value: "\(cam.pipeline.frameCount)")
                LabeledContent("認識に回したフレーム", value: "\(stats.framesRun) / \(stats.framesSeen)")
                LabeledContent("直前の検出数", value: "\(stats.lastCount)")
                LabeledContent("物体検出モデル", value: stats.hasObjectModel ? "読み込み済み" : "なし")
                if let e = stats.lastError { Text("エラー：\(e)").font(.caption).foregroundStyle(UIStyle.warning) }
                if let e = cam.lastError { Text("カメラ：\(e)").font(.caption).foregroundStyle(UIStyle.warning) }
                if !model.detectionActive {
                    Text("上の「物体認識を使う」をオンにしてください。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct VisionStatsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let v = model.vision
        Card(title: "認識の状態", systemImage: "chart.bar") {
            if !model.detectionActive {
                Text("物体認識はオフです").foregroundStyle(.secondary)
            } else {
                Text("推論 \(String(format: "%.1f", v.inferenceFPS)) 回/秒・1回 \(Int(v.lastInferenceMs)) ms・省電力 \(model.powerProfile.quality.displayName)")
                    .font(.footnote).monospacedDigit()
                if v.detections.isEmpty {
                    Text("検出なし").foregroundStyle(.secondary)
                } else {
                    ForEach(v.detections) { d in
                        HStack {
                            Text(d.label == .other ? d.rawLabel : d.label.displayName)
                            Spacer()
                            Text("\(Int(d.confidence * 100))%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                ForEach(v.hazards, id: \.trackID) { h in
                    Label("\(h.label.displayName)：\(h.level.displayName)　\(h.reason)", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(h.level >= .high ? UIStyle.danger : UIStyle.warning)
                }
            }
        }
    }
}

struct VisionDisclaimerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("物体認識・危険検知について", systemImage: "exclamationmark.triangle.fill")
                        .font(.title3.bold())
                        .foregroundStyle(UIStyle.warning)
                    Text("この機能は実験的な補助機能で、安全装置ではありません。")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("・誤検知（ないものを検出）や検知漏れ（あるものを見逃す）が起こります。")
                        Text("・警告が出ないことは、安全であることを意味しません。")
                        Text("・距離は物体の大きさからの目安で、正確ではありません。")
                        Text("・端末のカメラの向きは、あなたの視線の向きと一致しません。")
                        Text("・自動車・自転車の運転中には使わないでください。")
                        Text("・カメラ映像は端末内でのみ処理し、保存・送信しません。")
                    }
                    .font(.subheadline)
                    Button {
                        model.settings.detection.hasAcceptedDisclaimer = true
                        model.settings.detection.enabled = true
                        dismiss()
                    } label: {
                        Text("理解して有効にする").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    Button("やめる", role: .cancel) { dismiss() }
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
        }
        .presentationDetents([.large])
    }
}
