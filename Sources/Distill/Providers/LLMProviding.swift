public protocol LLMProviding: Sendable {
    func complete(prompt: String) async throws -> Summary
}

extension ClaudeProvider: LLMProviding {}
extension OpenAIProvider: LLMProviding {}
extension OllamaProvider: LLMProviding {}
