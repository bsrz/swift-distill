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
            return "This video has no captions. Whisper transcription is not yet supported."
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
        }
    }

    public var exitCode: Int32 {
        switch self {
        case .configurationError, .missingAPIKey:
            return 3
        default:
            return 1
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
