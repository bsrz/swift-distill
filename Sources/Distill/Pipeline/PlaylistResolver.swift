import Foundation

/// Resolves a YouTube playlist URL into individual video URLs using yt-dlp.
public struct PlaylistResolver: Sendable {
    private let cookiesFromBrowser: String?

    public init(cookiesFromBrowser: String? = nil) {
        self.cookiesFromBrowser = cookiesFromBrowser
    }

    /// Returns the list of video URLs and playlist title from a playlist URL.
    public func resolve(url: String) async throws -> PlaylistInfo {
        var arguments = [
            "--flat-playlist",
            "--dump-json",
            "--no-warnings",
        ]
        if let browser = cookiesFromBrowser {
            arguments += ["--cookies-from-browser", browser]
        }
        arguments.append(url)

        let result = try await Shell.run(
            executable: "yt-dlp",
            arguments: arguments,
            timeout: 120
        )

        guard result.exitCode == 0 else {
            throw DistillError.metadataFailed(
                "Failed to resolve playlist: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
            )
        }

        var videoURLs: [String] = []
        var playlistTitle: String?

        for line in result.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if playlistTitle == nil, let title = json["playlist_title"] as? String {
                playlistTitle = title
            }

            if let videoID = json["id"] as? String {
                videoURLs.append("https://www.youtube.com/watch?v=\(videoID)")
            } else if let videoURL = json["url"] as? String {
                videoURLs.append(videoURL)
            }
        }

        guard !videoURLs.isEmpty else {
            throw DistillError.metadataFailed("No videos found in playlist")
        }

        return PlaylistInfo(
            title: playlistTitle ?? "Playlist",
            videoURLs: videoURLs
        )
    }
}

public struct PlaylistInfo: Sendable {
    public let title: String
    public let videoURLs: [String]
}
