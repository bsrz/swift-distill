import Foundation

/// Represents the YAML config file at `~/.distill/config.yaml`.
/// All fields are optional — missing fields fall back to defaults.
public struct ConfigFile: Codable, Sendable {
    public var obsidian: ObsidianConfig?
    public var tags: TagsConfig?
    public var summarization: SummarizationConfig?
    public var frames: FramesConfig?
    public var cookies_from_browser: String?

    public init(
        obsidian: ObsidianConfig? = nil,
        tags: TagsConfig? = nil,
        summarization: SummarizationConfig? = nil,
        frames: FramesConfig? = nil,
        cookies_from_browser: String? = nil
    ) {
        self.obsidian = obsidian
        self.tags = tags
        self.summarization = summarization
        self.frames = frames
        self.cookies_from_browser = cookies_from_browser
    }

    public struct ObsidianConfig: Codable, Sendable {
        public var vault: String?
        public var folder: String?
        public var attachments: String?
        public var filename_format: String?
        public var image_syntax: String?

        public init(vault: String? = nil, folder: String? = nil, attachments: String? = nil, filename_format: String? = nil, image_syntax: String? = nil) {
            self.vault = vault
            self.folder = folder
            self.attachments = attachments
            self.filename_format = filename_format
            self.image_syntax = image_syntax
        }
    }

    public struct TagsConfig: Codable, Sendable {
        public var `default`: [String]?
        public var auto_tag: Bool?

        public init(default: [String]? = nil, auto_tag: Bool? = nil) {
            self.default = `default`
            self.auto_tag = auto_tag
        }
    }

    public struct SummarizationConfig: Codable, Sendable {
        public var provider: String?
        public var model: String?
        public var api_key_env: String?
        public var max_tokens: Int?

        public init(provider: String? = nil, model: String? = nil, api_key_env: String? = nil, max_tokens: Int? = nil) {
            self.provider = provider
            self.model = model
            self.api_key_env = api_key_env
            self.max_tokens = max_tokens
        }
    }

    public struct FramesConfig: Codable, Sendable {
        public var max_frames: Int?
        public var interval_seconds: Int?
        public var scene_detection: Bool?
        public var scene_threshold: Double?

        public init(max_frames: Int? = nil, interval_seconds: Int? = nil, scene_detection: Bool? = nil, scene_threshold: Double? = nil) {
            self.max_frames = max_frames
            self.interval_seconds = interval_seconds
            self.scene_detection = scene_detection
            self.scene_threshold = scene_threshold
        }
    }
}
