import Foundation

/// Cloud transcription using OpenAI Whisper API.
public struct WhisperCloudTranscriber: Sendable {
    private let apiKey: String
    private let language: String

    public init(apiKey: String, language: String = "en") {
        self.apiKey = apiKey
        self.language = language
    }

    /// Transcribes an audio file using the OpenAI Whisper API.
    public func transcribe(audioPath: URL) async throws -> Transcript {
        let audioData = try Data(contentsOf: audioPath)
        let boundary = UUID().uuidString

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        var body = Data()

        // model field
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-1")

        // response_format field — verbose_json gives us timestamps
        body.appendMultipart(boundary: boundary, name: "response_format", value: "verbose_json")

        // language field
        body.appendMultipart(boundary: boundary, name: "language", value: language)

        // file field
        body.appendMultipartFile(
            boundary: boundary,
            name: "file",
            filename: audioPath.lastPathComponent,
            mimeType: "audio/mpeg",
            data: audioData
        )

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let session = URLSession(configuration: .default)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DistillError.transcriptExtractionFailed("Invalid response from OpenAI Whisper API")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw DistillError.transcriptExtractionFailed(
                "OpenAI Whisper API error (\(httpResponse.statusCode)): \(errorBody)"
            )
        }

        return try parseVerboseJSON(data)
    }

    private func parseVerboseJSON(_ data: Data) throws -> Transcript {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segments = json["segments"] as? [[String: Any]] else {
            throw DistillError.transcriptExtractionFailed("Failed to parse Whisper API response")
        }

        let transcriptSegments = segments.compactMap { seg -> TranscriptSegment? in
            guard let start = seg["start"] as? Double,
                  let end = seg["end"] as? Double,
                  let text = seg["text"] as? String else { return nil }
            return TranscriptSegment(
                startTime: start,
                endTime: end,
                text: text.trimmingCharacters(in: .whitespaces)
            )
        }

        return Transcript(segments: transcriptSegments, source: .whisperCloud)
    }
}

// MARK: - Multipart Helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
