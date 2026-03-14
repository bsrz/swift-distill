import Foundation

/// Represents the YAML config file at `~/.distill/config.yaml`.
/// All fields are optional — missing fields fall back to defaults.
public struct ConfigFile: Codable, Sendable {
    public var obsidian: ObsidianConfig?
    public var tags: TagsConfig?
    public var summarization: SummarizationConfig?
    public var cookies_from_browser: String?

    public struct ObsidianConfig: Codable, Sendable {
        public var vault: String?
        public var folder: String?
        public var filename_format: String?
    }

    public struct TagsConfig: Codable, Sendable {
        public var `default`: [String]?
        public var auto_tag: Bool?
    }

    public struct SummarizationConfig: Codable, Sendable {
        public var provider: String?
        public var model: String?
        public var api_key_env: String?
        public var max_tokens: Int?
    }
}
