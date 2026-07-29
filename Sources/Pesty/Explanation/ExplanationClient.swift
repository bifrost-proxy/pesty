import Foundation

private struct ExplanationChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Thinking: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let thinking: Thinking?
    let stream = false

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, thinking, stream
        case maxTokens = "max_tokens"
    }
}

private struct ExplanationChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

enum ExplanationClient {
    private static let systemPrompt = """
    你是简洁、可靠的内容解释助手。解释用户复制内容的含义；若包含代码、术语、报错或链接，说明其用途、关键上下文和用户下一步该关注什么。使用与用户相同的语言回答，默认中文。使用简洁 Markdown 输出：核心句可用粗体，短要点使用 “- ”，代码、命令和字段名使用反引号；不要输出代码围栏。先用一句话给出核心含义，再按需给出最多 3 个短要点；总计不超过 160 个汉字。内容简单时只回答一句。不要编造未知事实、不要复述整段原文、不要寒暄或展示思考过程。
    """

    static func explain(
        text: String,
        provider: ExplanationProvider,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        do {
            let request = try makeRequest(text: text, provider: provider)
            CommandLineJSONTransport.data(for: request) { result in
                do {
                    let (data, response) = try result.get()
                    completion(.success(try decode(data: data, response: response)))
                } catch {
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    static func makeRequest(text: String, provider: ExplanationProvider) throws -> URLRequest {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { throw ExplanationError.noText }

        let url: URL
        let model: String
        let apiKey: String
        let thinking: ExplanationChatRequest.Thinking?
        switch provider {
        case .doubao(let modelID, let key):
            url = DoubaoTranslationRequestBuilder.endpoint
            model = modelID
            apiKey = key
            thinking = .init(type: "disabled")
        case .openAICompatible(let profile, let key):
            guard let endpoint = chatCompletionEndpoint(from: profile.endpoint) else {
                throw ExplanationError.invalidEndpoint
            }
            url = endpoint
            model = profile.model
            apiKey = key
            thinking = nil
        }

        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExplanationError.providerNotConfigured
        }

        let payload = ExplanationChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: normalizedText),
            ],
            temperature: 0.2,
            // The prompt keeps answers short. Retain enough completion budget
            // for Doubao Evolving to produce a final answer instead of ending
            // after its internal response preparation.
            maxTokens: 400,
            thinking: thinking
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 30
        return request
    }

    static func chatCompletionEndpoint(from configuredEndpoint: String) -> URL? {
        let trimmed = configuredEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        let path = trimmed.lowercased()
        let complete = path.hasSuffix("/chat/completions")
            ? trimmed
            : "\(trimmed)/chat/completions"
        return URL(string: complete)
    }

    private static func decode(data: Data, response: URLResponse) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplanationError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ExplanationError.requestFailed(statusCode: httpResponse.statusCode)
        }
        let decoded = try JSONDecoder().decode(ExplanationChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !text.isEmpty else {
            throw ExplanationError.invalidResponse
        }
        return text
    }
}
