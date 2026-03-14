import Foundation

public enum DistillError: LocalizedError {
    case invalidURL(String)
    case missingAPIKey
    case toolNotFound(String)
    case metadataFailed(String)
    case transcriptNotAvailable
    case transcriptExtractionFailed(String)
    case summarizationFailed(String)
    case apiError(statusCode: Int, message: String)
    case outputWriteFailed(String)
    case configurationError(String)
    case batchPartialFailure(succeeded: Int, failed: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid YouTube URL: \(url)"
        case .missingAPIKey:
            return "Anthropic API key not found."
        case .toolNotFound(let tool):
            return "Required tool not found: \(tool)"
        case .metadataFailed(let reason):
            return "Failed to fetch video metadata: \(reason)"
        case .transcriptNotAvailable:
            return "No transcript available for this video."
        case .transcriptExtractionFailed(let reason):
            return "Failed to extract transcript: \(reason)"
        case .summarizationFailed(let reason):
            return "Summarization failed: \(reason)"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .outputWriteFailed(let reason):
            return "Failed to write output: \(reason)"
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
        case .batchPartialFailure(let succeeded, let failed):
            return "Batch completed with partial failures: \(succeeded) succeeded, \(failed) failed."
        }
    }

    public var suggestion: String? {
        switch self {
        case .invalidURL:
            return "Provide a valid YouTube URL (e.g. https://www.youtube.com/watch?v=VIDEO_ID)."
        case .missingAPIKey:
            return "Set the ANTHROPIC_API_KEY environment variable."
        case .toolNotFound(let tool):
            return "Install \(tool) and ensure it is in your PATH."
        case .metadataFailed:
            return "Check that the URL is correct and yt-dlp is installed."
        case .transcriptNotAvailable:
            return "This video has no captions. Try --transcription local (requires mlx-whisper or whisper.cpp) or --transcription cloud (requires OPENAI_API_KEY)."
        case .transcriptExtractionFailed:
            return "Try again or check that yt-dlp is up to date."
        case .summarizationFailed:
            return "Check your API key and network connection."
        case .apiError(let statusCode, _):
            if statusCode == 401 {
                return "Check that your API key is valid."
            } else if statusCode == 429 {
                return "Rate limited. Wait a moment and try again."
            } else {
                return "Try again later."
            }
        case .outputWriteFailed:
            return "Check that the output directory exists and is writable."
        case .configurationError:
            return "Check your configuration."
        case .batchPartialFailure:
            return "Some videos failed. Check the status table above for details."
        }
    }

    public var exitCode: Int32 {
        switch self {
        case .configurationError, .missingAPIKey:
            return 3
        case .batchPartialFailure:
            return 2
        default:
            return 1
        }
    }

    /// Determines the exit code for a batch of video results.
    public static func batchExitCode(results: [VideoResult]) -> Int32 {
        let succeeded = results.filter(\.isSuccess).count
        let failed = results.count - succeeded
        if failed == 0 { return 0 }
        if succeeded == 0 { return 1 }
        return 2 // partial failure
    }

    public var isCaptionUnavailable: Bool {
        switch self {
        case .transcriptNotAvailable:
            return true
        default:
            return false
        }
    }

    public var isTransient: Bool {
        switch self {
        case .apiError(let statusCode, _):
            return statusCode == 429 || (500...599).contains(statusCode)
        case .metadataFailed, .transcriptExtractionFailed:
            return true
        default:
            return false
        }
    }
}
