import Foundation

public struct URLValidator: Sendable {
    public static func validate(_ urlString: String) throws -> String {
        if let match = urlString.firstMatch(of: #/(?:https?://)?(?:www\.)?(?:youtube\.com|youtube-nocookie\.com)/(?:watch\?.*v=|shorts/|embed/|v/)([\w-]{11})/#) {
            return String(match.1)
        }
        if let match = urlString.firstMatch(of: #/(?:https?://)?youtu\.be/([\w-]{11})/#) {
            return String(match.1)
        }
        throw DistillError.invalidURL(urlString)
    }

    public static func extractVideoID(_ urlString: String) -> String? {
        try? validate(urlString)
    }
}
