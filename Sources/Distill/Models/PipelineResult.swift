import Foundation

/// The result of a successful pipeline run for a single video.
public struct PipelineResult: Sendable {
    public let title: String
    public let durationString: String
    public let outputPath: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let costEstimate: Double

    public init(
        title: String,
        durationString: String,
        outputPath: String,
        inputTokens: Int,
        outputTokens: Int,
        costEstimate: Double
    ) {
        self.title = title
        self.durationString = durationString
        self.outputPath = outputPath
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costEstimate = costEstimate
    }
}
