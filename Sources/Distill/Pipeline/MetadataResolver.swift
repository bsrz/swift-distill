import Foundation

public struct MetadataResolver: MetadataResolving {
    private let cookiesFromBrowser: String?

    public init(cookiesFromBrowser: String? = nil) {
        self.cookiesFromBrowser = cookiesFromBrowser
    }

    public func resolve(url: String) async throws -> VideoMetadata {
        var arguments = ["--dump-json", "--no-download"]
        if let browser = cookiesFromBrowser {
            arguments += ["--cookies-from-browser", browser]
        }
        arguments.append(url)

        let result = try await Shell.run(
            executable: "yt-dlp",
            arguments: arguments,
            timeout: 30
        )

        guard result.exitCode == 0 else {
            let details = [
                result.stderr.isEmpty ? nil : result.stderr,
                result.stdout.isEmpty ? nil : result.stdout,
            ]
                .compactMap { $0 }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = details.isEmpty
                ? "yt-dlp exited with code \(result.exitCode)"
                : "yt-dlp exited with code \(result.exitCode): \(details)"
            throw DistillError.metadataFailed(message)
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DistillError.metadataFailed("Failed to parse yt-dlp JSON output.")
        }

        let subtitles = json["subtitles"] as? [String: Any] ?? [:]
        let autoCaptions = json["automatic_captions"] as? [String: Any] ?? [:]

        return VideoMetadata(
            id: json["id"] as? String ?? "",
            title: json["title"] as? String ?? "",
            channel: json["channel"] as? String ?? json["uploader"] as? String ?? "",
            channelURL: json["channel_url"] as? String ?? json["uploader_url"] as? String ?? "",
            uploadDate: json["upload_date"] as? String ?? "",
            duration: json["duration"] as? Int ?? Int(json["duration"] as? Double ?? 0),
            durationString: json["duration_string"] as? String ?? "",
            description: json["description"] as? String ?? "",
            tags: json["tags"] as? [String] ?? [],
            thumbnailURL: json["thumbnail"] as? String ?? "",
            webpageURL: json["webpage_url"] as? String ?? url,
            hasSubtitles: subtitles["en"] != nil,
            hasAutomaticCaptions: autoCaptions["en"] != nil
        )
    }
}
