import Foundation

public struct ExtractedFrame: Sendable {
    public let timestamp: TimeInterval
    public let filename: String
    public let path: String

    public init(timestamp: TimeInterval, filename: String, path: String) {
        self.timestamp = timestamp
        self.filename = filename
        self.path = path
    }

    public var timestampString: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

public struct FrameConfig: Sendable {
    public let maxFrames: Int
    public let intervalSeconds: Int
    public let sceneDetection: Bool
    public let sceneThreshold: Double

    public init(
        maxFrames: Int = 20,
        intervalSeconds: Int = 60,
        sceneDetection: Bool = true,
        sceneThreshold: Double = 0.4
    ) {
        self.maxFrames = maxFrames
        self.intervalSeconds = intervalSeconds
        self.sceneDetection = sceneDetection
        self.sceneThreshold = sceneThreshold
    }
}
