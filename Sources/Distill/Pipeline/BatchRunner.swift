import Foundation

/// Result for a single video in a batch.
public enum VideoResult: Sendable {
    case success(PipelineResult)
    case failure(url: String, error: String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var title: String {
        switch self {
        case .success(let result): return "\(result.title) (\(result.durationString))"
        case .failure(let url, _): return url
        }
    }

    public var statusString: String {
        switch self {
        case .success: return "Saved"
        case .failure(_, let error): return error
        }
    }

    public var cost: Double {
        switch self {
        case .success(let result): return result.costEstimate
        case .failure: return 0
        }
    }
}

/// Processes multiple YouTube URLs with concurrency control, rate limiting, and fail-fast.
public struct BatchRunner: Sendable {
    private let pipelineFactory: PipelineFactory
    private let concurrency: Int
    private let failFast: Bool
    private let baseDelay: TimeInterval

    public init(
        pipelineFactory: PipelineFactory,
        concurrency: Int = 1,
        failFast: Bool = false,
        baseDelay: TimeInterval = 2
    ) {
        self.pipelineFactory = pipelineFactory
        self.concurrency = concurrency
        self.failFast = failFast
        self.baseDelay = baseDelay
    }

    /// Process all URLs and return results in order.
    public func run(urls: [String]) async throws -> [VideoResult] {
        if concurrency <= 1 {
            return try await runSequential(urls: urls)
        } else {
            return try await runConcurrent(urls: urls)
        }
    }

    private func runSequential(urls: [String]) async throws -> [VideoResult] {
        var results: [VideoResult] = []

        for (index, url) in urls.enumerated() {
            // Rate limiting: base delay between videos (skip before first)
            if index > 0 {
                try await Task.sleep(for: .seconds(baseDelay))
            }

            log("\n[\(index + 1)/\(urls.count)] Processing: \(url)")

            let result = await processURL(url)
            results.append(result)

            if failFast, case .failure = result {
                log("Fail-fast: stopping batch due to error")
                break
            }
        }

        return results
    }

    private func runConcurrent(urls: [String]) async throws -> [VideoResult] {
        // Use indexed results to maintain order
        let indexedResults = try await withThrowingTaskGroup(
            of: (Int, VideoResult).self
        ) { group in
            var submitted = 0
            var collected: [(Int, VideoResult)] = []
            var shouldStop = false

            // Seed the group with initial batch up to concurrency limit
            for i in 0..<min(concurrency, urls.count) {
                let url = urls[i]
                let idx = i
                group.addTask {
                    return (idx, await self.processURL(url))
                }
                submitted = i + 1
            }

            // Collect results and submit more as slots open
            for try await (index, result) in group {
                collected.append((index, result))
                log("[\(collected.count)/\(urls.count)] Completed: \(result.title)")

                if failFast, case .failure = result {
                    shouldStop = true
                    group.cancelAll()
                    break
                }

                // Submit next URL if available
                if !shouldStop, submitted < urls.count {
                    let nextURL = urls[submitted]
                    let nextIdx = submitted
                    group.addTask {
                        // Small delay to avoid hammering
                        try? await Task.sleep(for: .seconds(self.baseDelay))
                        return (nextIdx, await self.processURL(nextURL))
                    }
                    submitted += 1
                }
            }

            return collected
        }

        // Sort by original index to maintain order
        return indexedResults.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func processURL(_ url: String) async -> VideoResult {
        do {
            let pipeline = try pipelineFactory.makePipeline(for: url)
            let result = try await pipeline.run()
            return .success(result)
        } catch {
            let message: String
            if let distillError = error as? DistillError {
                message = distillError.errorDescription ?? error.localizedDescription
            } else {
                message = error.localizedDescription
            }
            return .failure(url: url, error: message)
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}

/// Factory that creates Pipeline instances for different URLs.
/// This allows BatchRunner to create pipelines with shared config but per-URL settings.
public struct PipelineFactory: Sendable {
    private let makeFunc: @Sendable (String) throws -> Pipeline

    public init(_ makeFunc: @escaping @Sendable (String) throws -> Pipeline) {
        self.makeFunc = makeFunc
    }

    public func makePipeline(for url: String) throws -> Pipeline {
        try makeFunc(url)
    }
}
