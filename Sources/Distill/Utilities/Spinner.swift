import Foundation

public actor Spinner {
    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var message: String
    private var isRunning = false
    private var task: Task<Void, Never>?

    public init(message: String) {
        self.message = message
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self = Optional(self)] in
            var frameIndex = 0
            while let spinner = self, await spinner.getIsRunning() {
                let frame = Spinner.frames[frameIndex % Spinner.frames.count]
                let msg = await spinner.getMessage()
                FileHandle.standardError.write(
                    Data("\r\u{001B}[K\(frame) \(msg)".utf8)
                )
                frameIndex += 1
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    public func succeed(_ text: String) {
        stop()
        FileHandle.standardError.write(
            Data("\r\u{001B}[K✓ \(text)\n".utf8)
        )
    }

    public func fail(_ text: String) {
        stop()
        FileHandle.standardError.write(
            Data("\r\u{001B}[K✗ \(text)\n".utf8)
        )
    }

    public func stop() {
        isRunning = false
        task?.cancel()
        task = nil
        FileHandle.standardError.write(
            Data("\r\u{001B}[K".utf8)
        )
    }

    func getIsRunning() -> Bool { isRunning }
    func getMessage() -> String { message }
}
