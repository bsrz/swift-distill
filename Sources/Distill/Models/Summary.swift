public struct Summary: Sendable {
    public let markdown: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let model: String

    public init(markdown: String, inputTokens: Int, outputTokens: Int, model: String) {
        self.markdown = markdown
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.model = model
    }
}
