import Foundation

public struct OpenAIProvider: Sendable {
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
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OpenAIRequest(
            model: model,
            max_tokens: maxTokens,
            messages: [
                OpenAIMessage(role: "user", content: prompt)
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

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let markdown = openAIResponse.choices.first?.message.content ?? ""

        return Summary(
            markdown: markdown,
            inputTokens: openAIResponse.usage.prompt_tokens,
            outputTokens: openAIResponse.usage.completion_tokens,
            model: openAIResponse.model
        )
    }
}

struct OpenAIRequest: Encodable {
    let model: String
    let max_tokens: Int
    let messages: [OpenAIMessage]
}

struct OpenAIMessage: Encodable {
    let role: String
    let content: String
}

struct OpenAIResponse: Decodable {
    let choices: [Choice]
    let model: String
    let usage: Usage

    struct Choice: Decodable {
        let message: Message
        struct Message: Decodable {
            let content: String
        }
    }

    struct Usage: Decodable {
        let prompt_tokens: Int
        let completion_tokens: Int
    }
}
