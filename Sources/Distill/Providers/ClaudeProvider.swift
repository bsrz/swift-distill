import Foundation

public struct ClaudeProvider: Sendable {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int

    public init(apiKey: String, model: String, maxTokens: Int) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    public func complete(prompt: String) async throws -> Summary {
        try await RetryHandler.withRetry {
            try await sendRequest(prompt: prompt)
        }
    }

    private func sendRequest(prompt: String) async throws -> Summary {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: model,
            max_tokens: maxTokens,
            messages: [
                ClaudeMessage(role: "user", content: prompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 300
        let session = URLSession(configuration: sessionConfig)
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                throw DistillError.missingAPIKey
            }
            throw DistillError.apiError(
                statusCode: httpResponse.statusCode,
                message: errorBody
            )
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let markdown = claudeResponse.content.first?.text ?? ""

        return Summary(
            markdown: markdown,
            inputTokens: claudeResponse.usage.input_tokens,
            outputTokens: claudeResponse.usage.output_tokens,
            model: claudeResponse.model
        )
    }
}

struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessage]
}

struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
    let model: String
    let usage: Usage

    struct ContentBlock: Decodable {
        let text: String
    }

    struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
    }
}
