import Foundation

public struct VTTParser: Sendable {
    public static func parse(_ vttContent: String) -> Transcript {
        var segments: [TranscriptSegment] = []
        let lines = vttContent.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Look for timestamp lines: "00:00:00.000 --> 00:00:05.000"
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                guard parts.count == 2 else {
                    i += 1
                    continue
                }

                // Strip position/alignment attributes from end time
                let startStr = parts[0].trimmingCharacters(in: .whitespaces)
                let endPart = parts[1].trimmingCharacters(in: .whitespaces)
                let endStr = endPart.components(separatedBy: " ").first ?? endPart

                guard let startTime = parseTimestamp(startStr),
                      let endTime = parseTimestamp(endStr) else {
                    i += 1
                    continue
                }

                // Collect text lines until empty line or next timestamp
                var textLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].isEmpty && !lines[i].contains("-->") {
                    // Skip numeric cue identifiers
                    if let _ = Int(lines[i].trimmingCharacters(in: .whitespaces)) {
                        i += 1
                        continue
                    }
                    textLines.append(lines[i])
                    i += 1
                }

                let rawText = textLines.joined(separator: " ")
                let cleanText = stripTags(rawText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !cleanText.isEmpty {
                    segments.append(TranscriptSegment(
                        startTime: startTime,
                        endTime: endTime,
                        text: cleanText
                    ))
                }
            } else {
                i += 1
            }
        }

        // Deduplicate overlapping cues (YouTube rolling window)
        let deduped = deduplicateSegments(segments)

        return Transcript(segments: deduped, source: .youtubeAuto)
    }

    static func parseTimestamp(_ str: String) -> TimeInterval? {
        // Handles both HH:MM:SS.mmm and MM:SS.mmm
        let components = str.components(separatedBy: ":")
        switch components.count {
        case 3:
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        case 2:
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else { return nil }
            return minutes * 60 + seconds
        default:
            return nil
        }
    }

    static func stripTags(_ text: String) -> String {
        // Remove <c>, </c>, <c.colorCCCCCC>, word-timing tags like <00:00:01.520>, etc.
        text.replacing(#/<[^>]*>/#, with: "")
    }

    static func deduplicateSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard !segments.isEmpty else { return [] }

        var result: [TranscriptSegment] = []
        var seenTexts = Set<String>()

        for segment in segments {
            let normalized = segment.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if seenTexts.contains(normalized) {
                continue
            }

            // Check if this segment's text is a substring of a previous one
            let isDuplicate = result.contains { existing in
                existing.text.lowercased().contains(normalized)
            }

            if !isDuplicate {
                seenTexts.insert(normalized)
                result.append(segment)
            }
        }

        return result
    }
}
