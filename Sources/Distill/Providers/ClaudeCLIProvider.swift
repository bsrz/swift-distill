import Foundation

public struct ClaudeCLIProvider: LLMProviding {
    private let model: String?
    private let timeout: TimeInterval

    public init(model: String? = nil, timeout: TimeInterval = 300) {
        self.model = model
        self.timeout = timeout
    }

    public func complete(prompt: String) async throws -> Summary {
        var arguments = ["-p", "--output-format", "json", "--max-turns", "1"]
        if let model {
            arguments += ["--model", model]
        }

        // Strip API keys so claude uses the user's subscription login
        // instead of API-key-based billing
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        env.removeValue(forKey: "OPENAI_API_KEY")

        let result: ShellResult
        do {
            result = try await Shell.run(
                executable: "claude",
                arguments: arguments,
                stdin: prompt,
                environment: env,
                timeout: timeout
            )
        } catch let error as DistillError {
            if case .toolNotFound = error {
                throw DistillError.configurationError(
                    "claude CLI not found. Install it from https://claude.ai/download or use --provider claude with an API key."
                )
            }
            throw error
        }

        guard result.exitCode == 0 else {
            throw DistillError.apiError(
                statusCode: Int(result.exitCode),
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw DistillError.summarizationFailed("Empty response from claude CLI")
        }

        let response = try JSONDecoder().decode(ClaudeCLIResponse.self, from: data)

        guard !response.is_error else {
            throw DistillError.summarizationFailed(response.result)
        }

        let modelName = response.modelUsage?.keys.first ?? "claude-cli"
        let usage = response.modelUsage?.values.first

        return Summary(
            markdown: response.result,
            inputTokens: usage?.inputTokens ?? response.usage.input_tokens,
            outputTokens: usage?.outputTokens ?? response.usage.output_tokens,
            model: modelName
        )
    }
}

// MARK: - Response Models

struct ClaudeCLIResponse: Decodable {
    let result: String
    let is_error: Bool
    let usage: CLICLIUsage
    let modelUsage: [String: CLIModelUsage]?

    struct CLICLIUsage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
    }

    struct CLIModelUsage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        let costUSD: Double?
    }
}
