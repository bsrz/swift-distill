import Foundation

public struct RetryHandler: Sendable {
    public static func withRetry<T: Sendable>(
        maxAttempts: Int = 3,
        backoff: [TimeInterval] = [1, 2, 4],
        operation: @Sendable () async throws -> T,
        onRetry: (@Sendable (Error, Int) -> Void)? = nil
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Only retry if error is transient
                if let distillError = error as? DistillError, !distillError.isTransient {
                    throw error
                }

                // Don't retry after the last attempt
                if attempt == maxAttempts - 1 {
                    break
                }

                onRetry?(error, attempt + 1)

                let delay = backoff.indices.contains(attempt)
                    ? backoff[attempt]
                    : backoff.last ?? 1
                try await Task.sleep(for: .seconds(delay))
            }
        }

        throw lastError!
    }
}
