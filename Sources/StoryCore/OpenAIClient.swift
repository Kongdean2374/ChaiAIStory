import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ResponseEnvelope: Decodable, Sendable {
    public struct Output: Decodable, Sendable {
        public struct Summary: Decodable, Sendable { public let type: String; public let text: String }
        public let summary: [Summary]?
        public let encrypted_content: String?
        public struct Content: Decodable, Sendable { public let type: String; public let text: String?; public let refusal: String? }
        public let type: String
        public let id: String?
        public let call_id: String?
        public let name: String?
        public let arguments: String?
        public let content: [Content]?
    }
    public struct Usage: Decodable, Sendable {
        public struct Details: Decodable, Sendable { public let cached_tokens: Int? }
        public let input_tokens: Int
        public let output_tokens: Int
        public let input_tokens_details: Details?
    }
    public struct Failure: Decodable, Sendable { public let message: String?; public let code: String? }
    public let id: String
    public let status: String
    public let output: [Output]?
    public let usage: Usage?
    public let error: Failure?
    public var text: String { (output ?? []).flatMap { $0.content ?? [] }.filter { $0.type == "output_text" }.compactMap(\.text).joined() }
    public var calls: [Output] { (output ?? []).filter { $0.type == "function_call" } }
    public var refused: Bool { (output ?? []).flatMap { $0.content ?? [] }.contains { $0.type == "refusal" } }
}
public struct Pricing: Codable, Sendable {
    public var inputPerMillion: Double
    public var cachedPerMillion: Double
    public var outputPerMillion: Double
    public init(input: Double = 0, cached: Double = 0, output: Double = 0) { inputPerMillion = input; cachedPerMillion = cached; outputPerMillion = output }
    public func estimate(input: Int, cached: Int, output: Int) -> Double? {
        guard inputPerMillion > 0, outputPerMillion > 0 else { return nil }
        return (Double(max(0, input - cached)) * inputPerMillion + Double(cached) * cachedPerMillion + Double(output) * outputPerMillion) / 1_000_000
    }
}
public final class OpenAIClient: @unchecked Sendable {
    private let key: String
    private let transport: URLSession
    public init(key: String, transport: URLSession = .shared) { self.key = key; self.transport = transport }
    private func request(_ path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        guard !key.isEmpty else { throw StoryError.noKey }
        guard let url = URL(string: "https://api.openai.com/v1/" + path) else { throw StoryError.invalid("API 路徑錯誤。") }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = method == "GET" ? 45 : 180
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        // Never automatically retry a POST: it could have started a billable response.
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StoryError.interrupted }
        guard (200...299).contains(http.statusCode) else {
            // Only sanitized error text; neither request headers nor body are logged.
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            let message = (error?["message"] as? String ?? "請檢查網路、模型權限與額度。")
                .replacingOccurrences(of: key, with: "[已隱藏]")
            throw StoryError.api(http.statusCode, String(message.prefix(350)))
        }
        return data
    }
    public func models() async throws -> [String] {
        let data = try await request("models", method: "GET")
        struct ModelList: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id).sorted()
    }
    public func create(model: String, input: [[String: Any]], background: Bool, memoryOnly: Bool = false, probe: Bool = false, withTools: Bool = true, range: NarrativeRange = NarrativeRange(), opening: Bool = false, revision: Bool = false) async throws -> ResponseEnvelope {
        var body: [String: Any] = ["model": model, "input": input, "instructions": probe ? "Return ok=true." : ContextBuilder.instructions + (revision ? "\n本次是正文修正，不產出世界命令；只輸出 narrative 欄位，依提供的凍結候選保持所有事件不變。" : ""),
            "background": background, "store": false, "include": ["reasoning.encrypted_content"], "max_output_tokens": probe ? 256 : memoryOnly ? 8000 : NarrativePolicy.outputBudget(range: range, model: model, opening: opening, revision: revision),
            "text": ["format": ["type": "json_schema", "name": probe ? "capability_probe" : memoryOnly ? "memory_audit" : revision ? "narrative_revision" : "story_turn", "strict": true, "schema": probe ? ResponseSchemas.probe : memoryOnly ? ResponseSchemas.memory : revision ? ResponseSchemas.revision : ResponseSchemas.story]]]
        if !probe && !memoryOnly && !revision && withTools { body["tools"] = ResponseSchemas.tools; body["parallel_tool_calls"] = false }
        return try JSONDecoder().decode(ResponseEnvelope.self, from: await request("responses", method: "POST", body: body))
    }
    public func retrieve(_ id: String) async throws -> ResponseEnvelope {
        guard id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw StoryError.invalid("回應識別碼無效。") }
        return try JSONDecoder().decode(ResponseEnvelope.self, from: await request("responses/\(id)", method: "GET"))
    }
    public func cancel(_ id: String) async throws {
        guard id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return }
        _ = try await request("responses/\(id)/cancel", method: "POST")
    }
    public static func assistantItems(_ response: ResponseEnvelope) throws -> [[String: Any]] {
        // Preserve reasoning items (including opaque encrypted content if supplied) for stateless tool continuation,
        // but never render or log them. Raw items come from the response's output only in the caller's in-memory input.
        (response.output ?? []).compactMap { item -> [String: Any]? in
            if item.type == "function_call" {
                return ["type": "function_call", "call_id": item.call_id ?? "", "name": item.name ?? "", "arguments": item.arguments ?? "{}"]
            }
            if item.type == "reasoning" {
                var result: [String: Any] = ["type": "reasoning", "summary": (item.summary ?? []).map { ["type": $0.type, "text": $0.text] }]
                if let encrypted = item.encrypted_content { result["encrypted_content"] = encrypted }
                return result
            }
            return nil
        }
    }
}
