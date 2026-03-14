import Foundation

public struct VideoMetadata: Sendable {
    public let id: String
    public let title: String
    public let channel: String
    public let channelURL: String
    public let uploadDate: String
    public let duration: Int
    public let durationString: String
    public let description: String
    public let tags: [String]
    public let thumbnailURL: String
    public let webpageURL: String
    public let hasSubtitles: Bool
    public let hasAutomaticCaptions: Bool

    /// Converts YYYYMMDD → YYYY-MM-DD
    public var publishedDate: String {
        guard uploadDate.count == 8 else { return uploadDate }
        let year = uploadDate.prefix(4)
        let month = uploadDate.dropFirst(4).prefix(2)
        let day = uploadDate.dropFirst(6).prefix(2)
        return "\(year)-\(month)-\(day)"
    }

    public init(
        id: String,
        title: String,
        channel: String,
        channelURL: String,
        uploadDate: String,
        duration: Int,
        durationString: String,
        description: String,
        tags: [String],
        thumbnailURL: String,
        webpageURL: String,
        hasSubtitles: Bool,
        hasAutomaticCaptions: Bool
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.channelURL = channelURL
        self.uploadDate = uploadDate
        self.duration = duration
        self.durationString = durationString
        self.description = description
        self.tags = tags
        self.thumbnailURL = thumbnailURL
        self.webpageURL = webpageURL
        self.hasSubtitles = hasSubtitles
        self.hasAutomaticCaptions = hasAutomaticCaptions
    }
}
