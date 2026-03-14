import Foundation
import Yams

public struct ConfigLoader: Sendable {
    public static let defaultConfigDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".distill")
    public static let defaultConfigPath = defaultConfigDir
        .appendingPathComponent("config.yaml")

    /// Loads and validates the config file. Returns nil if file doesn't exist.
    public static func load(from path: String? = nil) throws -> ConfigFile? {
        let url: URL
        if let path {
            url = URL(fileURLWithPath: path)
        } else {
            url = defaultConfigPath
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw DistillError.configurationError("Cannot read config file at \(url.path): \(error.localizedDescription)")
        }

        return try parse(content, path: url.path)
    }

    /// Parses YAML string into ConfigFile with validation.
    public static func parse(_ yaml: String, path: String = "<string>") throws -> ConfigFile {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ConfigFile()
        }
        do {
            let config = try YAMLDecoder().decode(ConfigFile.self, from: yaml)
            return config
        } catch let error as DecodingError {
            switch error {
            case .typeMismatch(let type, let context):
                let field = context.codingPath.map(\.stringValue).joined(separator: ".")
                throw DistillError.configurationError(
                    "Invalid config at \(path): expected \(type) for \(field)"
                )
            case .dataCorrupted(let context):
                throw DistillError.configurationError(
                    "Invalid config at \(path): \(context.debugDescription)"
                )
            default:
                throw DistillError.configurationError(
                    "Invalid config at \(path): \(error.localizedDescription)"
                )
            }
        } catch {
            throw DistillError.configurationError(
                "Bad YAML syntax in \(path): \(error.localizedDescription)"
            )
        }
    }

    /// Generates a starter config YAML string.
    public static func starterConfig(vault: String? = nil) -> String {
        let vaultPath = vault ?? "~/Documents/Obsidian"
        return """
        # distill configuration
        # See: https://github.com/distill-cli/distill

        obsidian:
          vault: "\(vaultPath)"
          folder: YouTube
          filename_format: "{date}-{slug}"

        tags:
          default:
            - youtube
          auto_tag: true

        summarization:
          provider: claude
          model: claude-sonnet-4-6
          api_key_env: ANTHROPIC_API_KEY
          max_tokens: 8192

        # cookies_from_browser: brave
        """
    }
}
