import Foundation

public struct SlugGenerator: Sendable {
    private static let unsafeCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")

    public static func generate(from title: String, maxLength: Int = 80) -> String {
        var slug = title.lowercased()

        // Remove unsafe characters
        slug = slug.unicodeScalars
            .filter { !unsafeCharacters.contains($0) }
            .map { String($0) }
            .joined()

        // Replace spaces and underscores with hyphens
        slug = slug.replacing(#/[\s_]+/#, with: "-")

        // Collapse consecutive hyphens
        slug = slug.replacing(#/-{2,}/#, with: "-")

        // Trim leading/trailing hyphens
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Truncate at maxLength on a word boundary
        if slug.count > maxLength {
            let truncated = String(slug.prefix(maxLength))
            if let lastHyphen = truncated.lastIndex(of: "-") {
                slug = String(truncated[truncated.startIndex..<lastHyphen])
            } else {
                slug = truncated
            }
        }

        return slug
    }
}
