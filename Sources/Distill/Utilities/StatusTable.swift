import Foundation

/// Prints a formatted status table for batch/playlist results to stderr.
public struct StatusTable: Sendable {
    public static func print(results: [VideoResult], title: String = "Batch Results") {
        let stderr = FileHandle.standardError

        func write(_ s: String) {
            stderr.write(Data("\(s)\n".utf8))
        }

        let succeeded = results.filter(\.isSuccess).count
        let failed = results.count - succeeded
        let totalCost = results.reduce(0.0) { $0 + $1.cost }

        // Calculate column widths
        let indexWidth = 4
        let statusWidth = 16
        let maxVideoWidth = 46

        // Truncate video titles to fit
        let rows: [(index: Int, video: String, status: String, isSuccess: Bool)] = results.enumerated().map { idx, result in
            var video = result.title
            if video.count > maxVideoWidth {
                video = String(video.prefix(maxVideoWidth - 3)) + "..."
            }
            let status = result.isSuccess ? "Saved" : truncateError(result.statusString, max: statusWidth - 4)
            return (idx + 1, video, status, result.isSuccess)
        }

        let videoWidth = max(maxVideoWidth, title.count + 2)
        let totalWidth = indexWidth + 3 + videoWidth + 3 + statusWidth + 2

        // Top border
        write("")
        write(line("┌", "┐", totalWidth))
        write(padCenter(title, width: totalWidth))
        write(line3("├", "┼", "┼", "┤", indexWidth + 2, videoWidth + 2, statusWidth + 2))

        // Header
        write(row("#", "Video", "Status", indexWidth, videoWidth, statusWidth))
        write(line3("├", "┼", "┼", "┤", indexWidth + 2, videoWidth + 2, statusWidth + 2))

        // Data rows
        for r in rows {
            let marker = r.isSuccess ? "✓" : "✗"
            write(row(
                String(r.index),
                r.video,
                "\(marker) \(r.status)",
                indexWidth,
                videoWidth,
                statusWidth
            ))
        }

        // Summary
        write(line3("├", "┼", "┼", "┤", indexWidth + 2, videoWidth + 2, statusWidth + 2))
        let summary = "Total: \(succeeded)/\(results.count) succeeded, \(failed) failed"
        let costStr = "Cost: $\(String(format: "%.2f", totalCost))"
        write(row("", summary, costStr, indexWidth, videoWidth, statusWidth))

        // Bottom border
        write(line3("└", "┴", "┴", "┘", indexWidth + 2, videoWidth + 2, statusWidth + 2))
        write("")
    }

    private static func line(_ left: String, _ right: String, _ width: Int) -> String {
        "\(left)\(String(repeating: "─", count: width))\(right)"
    }

    private static func line3(_ left: String, _ mid1: String, _ mid2: String, _ right: String, _ w1: Int, _ w2: Int, _ w3: Int) -> String {
        "\(left)\(String(repeating: "─", count: w1))\(mid1)\(String(repeating: "─", count: w2))\(mid2)\(String(repeating: "─", count: w3))\(right)"
    }

    private static func padCenter(_ text: String, width: Int) -> String {
        let pad = max(0, width - text.count)
        let left = pad / 2
        let right = pad - left
        return "│\(String(repeating: " ", count: left))\(text)\(String(repeating: " ", count: right))│"
    }

    private static func row(_ col1: String, _ col2: String, _ col3: String, _ w1: Int, _ w2: Int, _ w3: Int) -> String {
        let c1 = col1.padding(toLength: w1, withPad: " ", startingAt: 0)
        let c2 = col2.padding(toLength: w2, withPad: " ", startingAt: 0)
        let c3 = col3.padding(toLength: w3, withPad: " ", startingAt: 0)
        return "│ \(c1) │ \(c2) │ \(c3) │"
    }

    private static func truncateError(_ error: String, max: Int) -> String {
        // Take first line, truncate
        let firstLine = error.components(separatedBy: .newlines).first ?? error
        if firstLine.count > max {
            return String(firstLine.prefix(max - 3)) + "..."
        }
        return firstLine
    }
}
