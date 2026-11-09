import SwiftUI

struct AssistantScreen: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            AssistantStatusCard()
                            if model.assistant.messages.isEmpty {
                                ExamplesCard { example in
                                    Task { await model.handleUtterance(example) }
                                }
                            }
                            ForEach(model.assistant.messages) { message in
                                MessageBubble(message: message).id(message.id)
                            }
                            if model.assistant.isThinking {
                                HStack { ProgressView(); Text("考え中…").foregroundStyle(.secondary) }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: model.assistant.messages.count) { _, _ in
                        if let last = model.assistant.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                Divider()
                InputBar(text: $text) {
                    let t = text
                    text = ""
                    Task { await model.handleUtterance(t) }
                }
            }
            .navigationTitle("アシスタント")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("消去") { model.assistant.clear() }.disabled(model.assistant.messages.isEmpty)
                }
            }
        }
    }
}

struct AssistantStatusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let input = model.speechInput
        let s = model.settings.assistant
        Card(title: "音声操作", systemImage: "mic") {
            HStack(spacing: 14) {
                Button {
                    input.toggle()
                } label: {
                    Image(systemName: input.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(input.isListening ? .orange : UIStyle.accent)
                        .symbolEffect(.pulse, isActive: input.isListening)
                }
                .accessibilityLabel(input.isListening ? "聞き取りを止める" : "話しかける")
                VStack(alignment: .leading, spacing: 4) {
                    switch input.state {
                    case .listening:
                        Text(input.transcript.isEmpty ? "聞き取り中…" : input.transcript).font(.headline)
                        ProgressView(value: Double(input.level)).tint(.orange)
                    case .processing:
                        Text("認識中…")
                    case .requestingPermission:
                        Text("許可を確認しています…")
                    case .unavailable(let reason):
                        Text(reason).font(.footnote).foregroundStyle(UIStyle.warning)
                        Button("閉じる") { input.resetError() }.font(.footnote)
                    case .idle:
                        Text("ボタンを押して話しかけてください").foregroundStyle(.secondary)
                    }
                    Text(input.isOnDevice || s.requiresOnDeviceSpeech ? "音声認識：端末内" : "音声認識：Apple のサーバー")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Image(systemName: s.provider.isCloud ? "cloud" : "iphone")
                Text(s.provider.isCloud ? "質問への回答：\(s.provider.displayName)\(s.cloudConsentGiven ? "" : "（同意が必要）")" : "質問への回答：端末内のみ（定型コマンドと状態の読み上げ）")
                    .font(.caption)
                Spacer()
                Button("設定") { model.open(.settings); model.settingsPath = [.assistant] }.font(.caption)
            }
            .foregroundStyle(.secondary)
            if !model.network.isOnline && s.provider.isCloud {
                NoticeBanner(text: "オフラインです。音声コマンドは使えますが、AIへの質問はできません。", systemImage: "wifi.slash")
            }
        }
    }
}

struct ExamplesCard: View {
    var onSelect: (String) -> Void
    private let examples = ["黒背景にして", "徒歩ナビモードにして", "速度を表示して", "地図を大きくして", "近くのコンビニを探して", "今何時？", "バッテリーは？", "HUDを開始して"]

    var body: some View {
        Card(title: "話しかける例（タップで実行）", systemImage: "text.bubble") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(examples, id: \.self) { e in
                    Button { onSelect(e) } label: {
                        Text("「\(e)」")
                            .font(.footnote)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("ほかに：" + LocalResponder.commandExamples.joined(separator: " ／ ")).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(10)
                    .background(message.role == .user ? UIStyle.accent.opacity(0.25) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                if let command = message.command {
                    Label(command, systemImage: "checkmark.circle").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}

struct InputBar: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        HStack {
            TextField("文字で入力（例：東京駅までナビして）", text: $text)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { if !text.isEmpty { onSend() } }
            Button {
                onSend()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }
}
