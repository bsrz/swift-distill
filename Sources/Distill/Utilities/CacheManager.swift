import Foundation
import CryptoKit

public struct CacheManager: Sendable {
    private static let cacheDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".distill/cache")
    }()

    public enum CacheType: String {
        case metadata
        case transcript
    }

    public static func get<T: Decodable>(type: CacheType, videoID: String) -> T? {
        let path = cachePath(type: type, videoID: videoID)
        guard let data = FileManager.default.contents(atPath: path.path) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func set<T: Encodable>(type: CacheType, videoID: String, value: T) {
        let path = cachePath(type: type, videoID: videoID)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? data.write(to: path)
    }

    public static func clear() throws {
        guard FileManager.default.fileExists(atPath: cacheDir.path) else { return }
        try FileManager.default.removeItem(at: cacheDir)
    }

    public static func status() -> CacheStatus {
        guard FileManager.default.fileExists(atPath: cacheDir.path) else {
            return CacheStatus(entries: 0, totalBytes: 0)
        }

        let enumerator = FileManager.default.enumerator(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey])
        var count = 0
        var totalBytes: Int64 = 0

        while let fileURL = enumerator?.nextObject() as? URL {
            count += 1
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            totalBytes += Int64(attrs?.fileSize ?? 0)
        }

        return CacheStatus(entries: count, totalBytes: totalBytes)
    }

    private static func cachePath(type: CacheType, videoID: String) -> URL {
        cacheDir.appendingPathComponent("\(videoID).\(type.rawValue).json")
    }
}

public struct CacheStatus: Sendable {
    public let entries: Int
    public let totalBytes: Int64

    public var formattedSize: String {
        if totalBytes < 1024 {
            return "\(totalBytes) B"
        } else if totalBytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(totalBytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(totalBytes) / (1024.0 * 1024.0))
        }
    }
}
