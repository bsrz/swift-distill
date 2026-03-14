import Foundation

public struct FrameExtractor: FrameExtracting {
    private let config: FrameConfig
    private let cookiesFromBrowser: String?

    public init(config: FrameConfig, cookiesFromBrowser: String? = nil) {
        self.config = config
        self.cookiesFromBrowser = cookiesFromBrowser
    }

    public func extract(metadata: VideoMetadata, to attachmentsDir: String) async throws -> [ExtractedFrame] {
        // 1. Download video to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("distill-frames-\(metadata.id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoPath = tempDir.appendingPathComponent("\(metadata.id).mp4").path

        let spinner = Spinner(message: "Downloading video for frame extraction...")
        await spinner.start()

        var dlArgs = [
            "--format", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4",
            "--output", videoPath,
        ]
        if let browser = cookiesFromBrowser {
            dlArgs += ["--cookies-from-browser", browser]
        }
        dlArgs.append(metadata.webpageURL)

        let dlResult = try await Shell.run(
            executable: "yt-dlp",
            arguments: dlArgs,
            timeout: 300
        )

        guard dlResult.exitCode == 0 else {
            await spinner.fail("Video download failed")
            throw DistillError.metadataFailed("Failed to download video for frame extraction: \(dlResult.stderr)")
        }
        await spinner.succeed("Video downloaded")

        // 2. Create attachments directory
        let attachmentsURL = URL(fileURLWithPath: attachmentsDir)
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)

        // 3. Extract frames using ffmpeg
        let extractSpinner = Spinner(message: "Extracting frames...")
        await extractSpinner.start()

        var frames: [ExtractedFrame] = []

        // Interval-based extraction
        let intervalFrames = try await extractIntervalFrames(
            videoPath: videoPath,
            tempDir: tempDir,
            intervalSeconds: config.intervalSeconds,
            duration: metadata.duration
        )
        frames.append(contentsOf: intervalFrames)

        // Scene-detection extraction
        if config.sceneDetection {
            let sceneFrames = try await extractSceneFrames(
                videoPath: videoPath,
                tempDir: tempDir,
                threshold: config.sceneThreshold
            )
            frames.append(contentsOf: sceneFrames)
        }

        // Deduplicate frames that are too close together (within 5 seconds)
        frames = deduplicateFrames(frames, minimumGap: 5)

        // Sort by timestamp and limit
        frames.sort { $0.timestamp < $1.timestamp }
        if frames.count > config.maxFrames {
            frames = Array(frames.prefix(config.maxFrames))
        }

        // 4. Copy frames to attachments with sequential naming
        var finalFrames: [ExtractedFrame] = []
        for (index, frame) in frames.enumerated() {
            let filename = String(format: "frame-%03d.png", index + 1)
            let destPath = attachmentsURL.appendingPathComponent(filename).path
            try FileManager.default.copyItem(atPath: frame.path, toPath: destPath)
            finalFrames.append(ExtractedFrame(
                timestamp: frame.timestamp,
                filename: filename,
                path: destPath
            ))
        }

        await extractSpinner.succeed("Extracted \(finalFrames.count) frames")
        return finalFrames
    }

    private func extractIntervalFrames(
        videoPath: String,
        tempDir: URL,
        intervalSeconds: Int,
        duration: Int
    ) async throws -> [ExtractedFrame] {
        let outputPattern = tempDir.appendingPathComponent("interval-%04d.png").path

        // fps=1/interval extracts one frame every N seconds
        let result = try await Shell.run(
            executable: "ffmpeg",
            arguments: [
                "-i", videoPath,
                "-vf", "fps=1/\(intervalSeconds)",
                "-vsync", "vfr",
                "-q:v", "2",
                outputPattern,
            ],
            timeout: 120
        )

        guard result.exitCode == 0 else {
            return [] // Non-fatal, scene detection may still work
        }

        return try collectFrames(
            directory: tempDir,
            prefix: "interval-",
            intervalSeconds: intervalSeconds
        )
    }

    private func extractSceneFrames(
        videoPath: String,
        tempDir: URL,
        threshold: Double
    ) async throws -> [ExtractedFrame] {
        // Use ffmpeg scene detection with showinfo to get timestamps
        let outputPattern = tempDir.appendingPathComponent("scene-%04d.png").path

        let result = try await Shell.run(
            executable: "ffmpeg",
            arguments: [
                "-i", videoPath,
                "-vf", "select='gt(scene,\(threshold))',showinfo",
                "-vsync", "vfr",
                "-q:v", "2",
                outputPattern,
            ],
            timeout: 120
        )

        guard result.exitCode == 0 else {
            return []
        }

        // Parse timestamps from ffmpeg showinfo output in stderr
        return parseSceneFrames(stderr: result.stderr, directory: tempDir)
    }

    private func collectFrames(
        directory: URL,
        prefix: String,
        intervalSeconds: Int
    ) throws -> [ExtractedFrame] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return files.enumerated().map { index, fileURL in
            ExtractedFrame(
                timestamp: TimeInterval(index * intervalSeconds),
                filename: fileURL.lastPathComponent,
                path: fileURL.path
            )
        }
    }

    func parseSceneFrames(stderr: String, directory: URL) -> [ExtractedFrame] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("scene-") && $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? []

        // Parse pts_time from showinfo lines: "pts_time:123.456"
        let timestamps: [TimeInterval] = stderr
            .components(separatedBy: .newlines)
            .compactMap { line -> TimeInterval? in
                guard line.contains("showinfo"),
                      let range = line.range(of: "pts_time:") else { return nil }
                let after = line[range.upperBound...]
                let numStr = after.prefix(while: { $0.isNumber || $0 == "." })
                return TimeInterval(numStr)
            }

        return zip(files, timestamps).map { file, timestamp in
            ExtractedFrame(
                timestamp: timestamp,
                filename: file.lastPathComponent,
                path: file.path
            )
        }
    }

    private func deduplicateFrames(_ frames: [ExtractedFrame], minimumGap: TimeInterval) -> [ExtractedFrame] {
        let sorted = frames.sorted { $0.timestamp < $1.timestamp }
        var result: [ExtractedFrame] = []
        for frame in sorted {
            if let last = result.last, abs(frame.timestamp - last.timestamp) < minimumGap {
                continue
            }
            result.append(frame)
        }
        return result
    }
}
