import Foundation

public struct TranscriptSegment: Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String

    public init(startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public enum TranscriptSource: String, Sendable {
    case youtubeManual
    case youtubeAuto
}

public struct Transcript: Sendable {
    public let segments: [TranscriptSegment]
    public let source: TranscriptSource

    public var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }

    public init(segments: [TranscriptSegment], source: TranscriptSource) {
        self.segments = segments
        self.source = source
    }
}
