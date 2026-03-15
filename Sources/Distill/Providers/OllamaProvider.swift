import Foundation

public struct OllamaProvider: Sendable {
    private let model: String
    private let baseURL: String

    public init(model: String, baseURL: String = "http://localhost:11434") {
        self.model = model
        self.baseURL = baseURL
    }

    public func complete(prompt: String) async throws -> Summary {
        try await sendRequest(prompt: prompt)
    }

    private func sendRequest(prompt: String) async throws -> Summary {
        let url = URL(string: "\(baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OllamaRequest(
            model: model,
            messages: [
                OllamaMessage(role: "user", content: prompt)
            ],
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 600
        sessionConfig.timeoutIntervalForResource = 600
        let session = URLSession(configuration: sessionConfig)
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DistillError.apiError(
                statusCode: httpResponse.statusCode,
                message: errorBody
            )
        }

        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        let markdown = ollamaResponse.message.content

        return Summary(
            markdown: markdown,
            inputTokens: ollamaResponse.prompt_eval_count ?? 0,
            outputTokens: ollamaResponse.eval_count ?? 0,
            model: model
        )
    }
}

struct OllamaRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
}

struct OllamaMessage: Encodable {
    let role: String
    let content: String
}

struct OllamaResponse: Decodable {
    let message: Message
    let prompt_eval_count: Int?
    let eval_count: Int?

    struct Message: Decodable {
        let content: String
    }
}
