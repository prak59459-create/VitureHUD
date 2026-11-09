import Foundation
import Observation

struct ChatMessage: Identifiable, Hashable {
    enum Role: String { case user, assistant, system }
    let id = UUID()
    var role: Role
    var text: String
    var date = Date()
    /// 実行したコマンド（あれば）
    var command: String?
    /// クラウドに送ったか
    var sentToCloud = false
}

/// クラウド LLM への問い合わせ（ユーザーが API キーを入れて同意した場合のみ）。
enum CloudAssistant {
    enum CloudError: LocalizedError {
        case missingKey
        case http(Int, String)
        case refused
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingKey: return "APIキーが設定されていません（設定 → AIアシスタント）。"
            case .http(let code, let body): return "AIサービスがエラーを返しました（\(code)）。\(body.prefix(120))"
            case .refused: return "AIが回答を控えました。質問の言い方を変えてみてください。"
            case .emptyResponse: return "AIから回答がありませんでした。"
            }
        }
    }

    static func keyAccount(_ provider: AssistantProviderKind) -> String { "assistant.\(provider.rawValue)" }

    static let systemPrompt = """
    あなたは歩行者向けHUDナビゲーションアプリ「HUD Navigator」の音声アシスタントです。
    返答は日本語で、HUDに表示し読み上げるため2〜3文の短い文にしてください。
    安全を最優先し、運転中・自転車走行中の操作は勧めないでください。
    分からないことや確認できない情報（営業時間・混雑など）は推測で断定せず、確認方法を伝えてください。
    """

    static func ask(_ question: String, context: String, settings: AssistantSettings, network: NetworkLog, extraSystem: String = "") async throws -> String {
        guard let key = KeychainStore.load(account: keyAccount(settings.provider)), !key.isEmpty else { throw CloudError.missingKey }
        let userText = context.isEmpty ? question : "状況:\n\(context)\n\n質問: \(question)"
        let system = extraSystem.isEmpty ? systemPrompt : systemPrompt + "\n\n" + extraSystem
        switch settings.provider {
        case .localOnly:
            throw CloudError.missingKey
        case .anthropic:
            return try await askAnthropic(userText, key: key, settings: settings, network: network, system: system)
        case .gemini:
            return try await askGemini(userText, key: key, settings: settings, network: network, system: system)
        case .openAICompatible:
            return try await askOpenAICompatible(userText, key: key, settings: settings, network: network, system: system)
        }
    }

    // MARK: Anthropic Messages API

    static func askAnthropic(_ text: String, key: String, settings: AssistantSettings, network: NetworkLog, system: String = CloudAssistant.systemPrompt) async throws -> String {
        let base = settings.effectiveBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/v1/messages") else { throw URLError(.badURL) }
        let model = settings.effectiveModel
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": text]],
            // 短い会話なので推論量は少なめ
            "output_config": ["effort": "low"],
        ]
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // 安全分類で断られた場合に別モデルで自動再試行（サーバー側フォールバック）。Haiku には無い。
        if !model.contains("haiku") {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.send(request, purpose: "AIアシスタント（Anthropic）")
        guard response.statusCode == 200 else { throw CloudError.http(response.statusCode, String(data: data, encoding: .utf8) ?? "") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // 回答を読む前に stop_reason を確認する
        if (json?["stop_reason"] as? String) == "refusal" { throw CloudError.refused }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        let answer = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !answer.isEmpty else { throw CloudError.emptyResponse }
        return answer
    }

    // MARK: Google Gemini

    static func askGemini(_ text: String, key: String, settings: AssistantSettings, network: NetworkLog, system: String = CloudAssistant.systemPrompt) async throws -> String {
        let base = settings.effectiveBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1beta/models/\(settings.effectiveModel):generateContent") else { throw URLError(.badURL) }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": text]]]],
            "generationConfig": ["maxOutputTokens": 1024],
        ]
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.send(request, purpose: "AIアシスタント（Gemini）")
        guard response.statusCode == 200 else { throw CloudError.http(response.statusCode, String(data: data, encoding: .utf8) ?? "") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]] ?? []
        let content = candidates.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        let answer = parts.compactMap { $0["text"] as? String }.joined()
        guard !answer.isEmpty else { throw CloudError.emptyResponse }
        return answer
    }

    // MARK: OpenAI 互換

    static func askOpenAICompatible(_ text: String, key: String, settings: AssistantSettings, network: NetworkLog, system: String = CloudAssistant.systemPrompt) async throws -> String {
        let base = settings.effectiveBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/chat/completions") else { throw URLError(.badURL) }
        let body: [String: Any] = [
            "model": settings.effectiveModel,
            "messages": [["role": "system", "content": system], ["role": "user", "content": text]],
            "max_tokens": 1024,
        ]
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.send(request, purpose: "AIアシスタント（OpenAI互換）")
        guard response.statusCode == 200 else { throw CloudError.http(response.statusCode, String(data: data, encoding: .utf8) ?? "") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]] ?? []
        let message = choices.first?["message"] as? [String: Any]
        guard let answer = message?["content"] as? String, !answer.isEmpty else { throw CloudError.emptyResponse }
        return answer
    }
}

/// 会話の記録と、最後の応答（HUD のアシスタントウィジェット用）。
@MainActor
@Observable
final class AssistantModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    private(set) var lastResponse: String?
    /// クラウドに送る前に表示する、送信内容の確認
    var pendingCloudQuestion: String?

    func append(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > 100 { messages.removeFirst(messages.count - 100) }
        if message.role == .assistant { lastResponse = message.text }
    }

    func setThinking(_ value: Bool) { isThinking = value }

    func clear() {
        messages.removeAll()
        lastResponse = nil
    }
}
