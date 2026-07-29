import CFNetwork
import Foundation

struct DoubaoTranslationRequestBuilder {
    static let endpoint = URL(string: "https://ark.cn-beijing.volces.com/api/v3/chat/completions")!

    static func make(
        text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        modelID: String,
        apiKey: String
    ) throws -> URLRequest {
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw TranslationServiceError.doubaoEndpointRequired
        }
        guard target != .automatic else {
            throw TranslationServiceError.targetLanguageRequired
        }

        let sourceDescription = source == .automatic
            ? "自动识别原文语言"
            : source.displayName
        let prompt = """
        你是专业翻译引擎。请把用户提供的文本从\(sourceDescription)翻译为\(target.displayName)。
        只输出译文，不解释、不加引号；保留原有段落、换行、代码、URL 和专有名词。
        """
        let payload = DoubaoChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: prompt),
                .init(role: "user", content: text),
            ],
            temperature: 0,
            // Clipboard translation should return the translation, not spend tokens
            // on a reasoning trace. This is particularly important for Evolving.
            thinking: .init(type: "disabled")
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 30
        return request
    }
}

private struct DoubaoChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let thinking: Thinking
    let stream = false

    struct Thinking: Encodable {
        let type: String
    }
}

private struct DoubaoChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

struct DoubaoPromptDiagnosticResponse {
    let requestBody: String
    let statusCode: Int
    let responseBody: String
}

enum DoubaoTranslationClient {
    static func translate(
        text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        modelID: String,
        apiKey: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            translate(
                text: text,
                source: source,
                target: target,
                modelID: modelID,
                apiKey: apiKey,
                completion: { result in
                    continuation.resume(with: result)
                }
            )
        }
    }

    static func translate(
        text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        modelID: String,
        apiKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        do {
            let request = try DoubaoTranslationRequestBuilder.make(
                text: text,
                source: source,
                target: target,
                modelID: modelID,
                apiKey: apiKey
            )
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

    /// Test-only support for inspecting the provider's JSON contract without including
    /// credentials. Production translation continues through the decoded API above.
    static func diagnosePrompt(
        text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        modelID: String,
        apiKey: String,
        completion: @escaping (Result<DoubaoPromptDiagnosticResponse, Error>) -> Void
    ) {
        do {
            let request = try DoubaoTranslationRequestBuilder.make(
                text: text,
                source: source,
                target: target,
                modelID: modelID,
                apiKey: apiKey
            )
            guard let requestBody = request.httpBody,
                  let requestText = String(data: requestBody, encoding: .utf8) else {
                completion(.failure(TranslationServiceError.invalidDoubaoResponse))
                return
            }
            CommandLineJSONTransport.data(for: request) { result in
                do {
                    let (data, response) = try result.get()
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw TranslationServiceError.invalidDoubaoResponse
                    }
                    completion(.success(DoubaoPromptDiagnosticResponse(
                        requestBody: requestText,
                        statusCode: httpResponse.statusCode,
                        responseBody: String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
                    )))
                } catch {
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    private static func decode(data: Data, response: URLResponse) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationServiceError.invalidDoubaoResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TranslationServiceError.doubaoRequestFailed(statusCode: httpResponse.statusCode)
        }
        let decoded = try JSONDecoder().decode(DoubaoChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !content.isEmpty else {
            throw TranslationServiceError.invalidDoubaoResponse
        }
        return content
    }
}

/// In this macOS environment, a local network extension can leave Pesty's URLSession
/// requests suspended while the system curl transport completes normally. Keep the
/// credential in the process stdin config rather than exposing it in process arguments.
/// Shared secure curl transport for user-configured JSON chat-completion APIs.
/// Credentials are provided through stdin only, never via argv or a file.
enum CommandLineJSONTransport {
    private static let statusMarker = Data("\n__PESTY_HTTP_STATUS:".utf8)

    static func data(
        for request: URLRequest,
        completion: @escaping (Result<(Data, URLResponse), Error>) -> Void
    ) {
        guard let url = request.url,
              let body = request.httpBody,
              let authorization = request.value(forHTTPHeaderField: "Authorization") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let collector = OutputCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collector.append(chunk)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--http1.1", "--silent", "--show-error", "--connect-timeout", "10", "--max-time", "40",
            "--config", "-", "--write-out", "\\n__PESTY_HTTP_STATUS:%{http_code}",
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { process in
            output.fileHandleForReading.readabilityHandler = nil
            collector.append(output.fileHandleForReading.readDataToEndOfFile())
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? "<non-UTF8 curl stderr>"
            guard process.terminationStatus == 0 else {
                completion(.failure(TransportError(
                    exitStatus: process.terminationStatus,
                    detail: errorText
                )))
                return
            }
            guard let result = response(from: collector.data, url: url) else {
                completion(.failure(TransportError(
                    exitStatus: process.terminationStatus,
                    detail: errorText.isEmpty ? "curl did not emit an HTTP status marker" : errorText
                )))
                return
            }
            completion(.success(result))
        }

        do {
            try process.run()
            input.fileHandleForWriting.write(configData(
                url: url,
                authorization: authorization,
                body: body,
                proxy: systemProxy(for: url)
            ))
            try input.fileHandleForWriting.close()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            completion(.failure(error))
        }
    }

    private static func configData(
        url: URL,
        authorization: String,
        body: Data,
        proxy: String?
    ) -> Data {
        let bodyText = String(data: body, encoding: .utf8) ?? "{}"
        var lines = [
            "url = \(quoted(url.absoluteString))",
            "request = \(quoted("POST"))",
            "header = \(quoted("Content-Type: application/json"))",
            "header = \(quoted("Authorization: \(authorization)"))",
            "data = \(quoted(bodyText))",
        ]
        if let proxy {
            lines.insert("proxy = \(quoted(proxy))", at: 1)
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func systemProxy(for url: URL) -> String? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
            as? [String: Any] else {
            return nil
        }
        let isHTTPS = url.scheme?.lowercased() == "https"
        let enabledKey = isHTTPS ? kCFNetworkProxiesHTTPSEnable : kCFNetworkProxiesHTTPEnable
        let hostKey = isHTTPS ? kCFNetworkProxiesHTTPSProxy : kCFNetworkProxiesHTTPProxy
        let portKey = isHTTPS ? kCFNetworkProxiesHTTPSPort : kCFNetworkProxiesHTTPPort
        guard (settings[enabledKey as String] as? NSNumber)?.boolValue == true,
              let host = settings[hostKey as String] as? String,
              let port = (settings[portKey as String] as? NSNumber)?.intValue,
              !host.isEmpty,
              port > 0 else {
            return nil
        }
        return "http://\(host):\(port)"
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func response(from output: Data, url: URL) -> (Data, URLResponse)? {
        guard let markerRange = output.range(of: statusMarker, options: .backwards),
              let statusText = String(data: output[markerRange.upperBound...], encoding: .utf8),
              let statusCode = Int(statusText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: nil
              ) else {
            return nil
        }
        return (Data(output[..<markerRange.lowerBound]), response)
    }

    /// Curl diagnostics are intentionally limited to its exit status and redacted stderr.
    /// Request headers and the API key are never included in a diagnostic result.
    private struct TransportError: LocalizedError {
        let exitStatus: Int32
        let detail: String

        var errorDescription: String? {
            let redacted = detail.replacingOccurrences(
                of: "Authorization:[^\\r\\n]*",
                with: "Authorization: <redacted>",
                options: .regularExpression
            )
            let normalized = redacted
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(240)
            return "curl-exit-\(exitStatus): \(normalized)"
        }
    }

    private final class OutputCollector {
        private let lock = NSLock()
        private var storage = Data()

        func append(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock()
            storage.append(data)
            lock.unlock()
        }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
