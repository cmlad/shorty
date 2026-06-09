import AppKit
import Foundation
import Yams

public enum LaunchMode {
    case run
    case validateConfig
    case listWindows
    case help
}

public enum WindowListFormat {
    case plain
    case verbose
}

public enum LaunchOptionsError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)

    public var description: String {
        switch self {
        case let .missingValue(flag):
            return "Missing value for `\(flag)`."
        case let .unknownArgument(argument):
            return "Unknown argument `\(argument)`."
        }
    }
}

public struct LaunchOptions {
    public let configURL: URL
    public let mode: LaunchMode
    public let windowListFormat: WindowListFormat

    public init(arguments: [String]) throws {
        var configPath: String?
        var mode: LaunchMode = .run
        var windowListFormat: WindowListFormat = .plain

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--config":
                let nextIndex = index + 1
                guard nextIndex < arguments.count else {
                    throw LaunchOptionsError.missingValue(argument)
                }

                configPath = arguments[nextIndex]
                index = nextIndex

            case "--validate-config":
                mode = .validateConfig

            case "--list-windows":
                mode = .listWindows

            case "--verbose":
                windowListFormat = .verbose

            case "--help", "-h":
                mode = .help

            default:
                throw LaunchOptionsError.unknownArgument(argument)
            }

            index += 1
        }

        let resolvedPath = configPath ?? Self.defaultConfigURL.path
        let expandedPath = (resolvedPath as NSString).expandingTildeInPath

        self.configURL = URL(fileURLWithPath: expandedPath)
        self.mode = mode
        self.windowListFormat = windowListFormat
    }

    public static var defaultConfigURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("config")
            .appendingPathComponent("shorty.yaml")
    }

    public static let usage = """
    Usage:
      Shorty [--config /path/to/config.yaml]
      Shorty --validate-config [--config /path/to/config.yaml]
      Shorty --list-windows [--verbose]

    Options:
      --config PATH         Use a specific YAML config file
      --validate-config     Parse and validate config, then exit
      --list-windows        Print accessible windows with bundle ID and title
      --verbose             Print extra window metadata in list mode
      --help                Show this help
    """
}

public struct ConfigurationFile: Decodable {
    public let shortcuts: [ShortcutConfiguration]

    enum CodingKeys: String, CodingKey {
        case shortcuts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyedShortcuts = try container.decodeIfPresent([String: ShortcutConfiguration].self, forKey: .shortcuts) ?? [:]

        self.shortcuts = keyedShortcuts
            .sorted { $0.key < $1.key }
            .map { element in
                element.value.withID(element.key)
            }
    }
}

public struct SnippetGroup: Equatable, Sendable {
    public let title: String
    public let snippets: [Snippet]
}

public struct Snippet: Equatable, Sendable {
    public let title: String
    public let content: String
}

public struct ShortcutConfiguration: Codable {
    public let id: String?
    public let hotkey: String
    public let bundleID: String?
    public let appNameRegex: String?
    public let executablePathPrefix: String?
    public let titleRegex: String?
    public let titleContains: String?
    public let documentRegex: String?
    public let urlRegex: String?
    public let identifierRegex: String?
    public let windowIndex: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case hotkey
        case bundleID = "bundle-id"
        case appNameRegex = "app-name-regex"
        case executablePathPrefix = "executable-path-prefix"
        case titleRegex = "title-regex"
        case titleContains = "title-contains"
        case documentRegex = "document-regex"
        case urlRegex = "url-regex"
        case identifierRegex = "identifier-regex"
        case windowIndex = "window-index"
    }

    fileprivate func withID(_ id: String) -> ShortcutConfiguration {
        ShortcutConfiguration(
            id: id,
            hotkey: hotkey,
            bundleID: bundleID,
            appNameRegex: appNameRegex,
            executablePathPrefix: executablePathPrefix,
            titleRegex: titleRegex,
            titleContains: titleContains,
            documentRegex: documentRegex,
            urlRegex: urlRegex,
            identifierRegex: identifierRegex,
            windowIndex: windowIndex
        )
    }
}

public enum ConfigurationError: Error, CustomStringConvertible {
    case emptyShortcuts
    case emptyConfiguration
    case unsupportedConfigExtension(String)
    case missingMatcher(String)
    case invalidWindowIndex(String, Int)
    case invalidRegex(field: String, shortcutID: String, error: Error)
    case duplicateHotkey(String)
    case reservedHotkey(String, String)
    case invalidSnippets(String)

    public var description: String {
        switch self {
        case .emptyShortcuts:
            return "Config has no shortcuts."
        case .emptyConfiguration:
            return "Config has no shortcuts or snippets."
        case let .unsupportedConfigExtension(fileExtension):
            let description = fileExtension.isEmpty ? "<none>" : ".\(fileExtension)"
            return "Unsupported config extension `\(description)`. Use `.yaml` or `.yml`."
        case let .missingMatcher(shortcutID):
            return "Shortcut `\(shortcutID)` needs at least one matcher field."
        case let .invalidWindowIndex(shortcutID, value):
            return "Shortcut `\(shortcutID)` has invalid window-index `\(value)`. Use 0 or higher."
        case let .invalidRegex(field, shortcutID, error):
            return "Shortcut `\(shortcutID)` has invalid regex for `\(field)`: \(error.localizedDescription)"
        case let .duplicateHotkey(hotkey):
            return "Duplicate hotkey `\(hotkey)` in config."
        case let .reservedHotkey(hotkey, usage):
            return "Shortcut hotkey `\(hotkey)` is reserved for the \(usage)."
        case let .invalidSnippets(message):
            return "Invalid snippets config: \(message)"
        }
    }
}

public struct LoadedConfiguration {
    public let shortcuts: [LoadedShortcut]
    public let snippetGroups: [SnippetGroup]
}

public struct LoadedShortcut {
    public let id: String
    public let hotKey: KeyCombo
    public let matcher: WindowMatcher
}

public struct WindowMatcher {
    public let bundleID: String?
    public let appNameRegex: NSRegularExpression?
    public let executablePathPrefix: String?
    public let titleRegex: NSRegularExpression?
    public let titleContains: String?
    public let documentRegex: NSRegularExpression?
    public let urlRegex: NSRegularExpression?
    public let identifierRegex: NSRegularExpression?
    public let windowIndex: Int

    public func matches(
        app: NSRunningApplication,
        title: String,
        document: String?,
        url: String?,
        identifier: String?,
        executablePath: String?
    ) -> Bool {
        guard matchesApplication(app: app, executablePath: executablePath) else {
            return false
        }

        if let titleRegex, !Self.matches(regex: titleRegex, in: title) {
            return false
        }

        if let titleContains {
            guard title.localizedCaseInsensitiveContains(titleContains) else {
                return false
            }
        }

        if let documentRegex {
            guard let document else {
                return false
            }

            guard Self.matches(regex: documentRegex, in: document) else {
                return false
            }
        }

        if let urlRegex {
            guard let url else {
                return false
            }

            guard Self.matches(regex: urlRegex, in: url) else {
                return false
            }
        }

        if let identifierRegex {
            guard let identifier else {
                return false
            }

            guard Self.matches(regex: identifierRegex, in: identifier) else {
                return false
            }
        }

        return true
    }

    public func matchesApplication(app: NSRunningApplication, executablePath: String?) -> Bool {
        if let bundleID, app.bundleIdentifier != bundleID {
            return false
        }

        if let appNameRegex {
            let appName = app.localizedName ?? ""
            guard Self.matches(regex: appNameRegex, in: appName) else {
                return false
            }
        }

        if let executablePathPrefix {
            guard let executablePath else {
                return false
            }

            guard executablePath.hasPrefix(executablePathPrefix) else {
                return false
            }
        }

        return true
    }

    public var summary: String {
        var parts: [String] = []

        if let bundleID {
            parts.append("bundle-id=\(bundleID)")
        }

        if let titleContains {
            parts.append("title-contains=\(titleContains)")
        }

        if let titleRegex {
            parts.append("title-regex=\(titleRegex.pattern)")
        }

        if let documentRegex {
            parts.append("document-regex=\(documentRegex.pattern)")
        }

        if let urlRegex {
            parts.append("url-regex=\(urlRegex.pattern)")
        }

        if let identifierRegex {
            parts.append("identifier-regex=\(identifierRegex.pattern)")
        }

        if let appNameRegex {
            parts.append("app-name-regex=\(appNameRegex.pattern)")
        }

        if let executablePathPrefix {
            parts.append("executable-path-prefix=\(executablePathPrefix)")
        }

        if windowIndex > 0 {
            parts.append("window-index=\(windowIndex)")
        }

        return parts.joined(separator: ", ")
    }

    private static func matches(regex: NSRegularExpression, in value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}

public enum ConfigurationLoader {
    public static func load(from url: URL) throws -> LoadedConfiguration {
        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension == "yaml" || fileExtension == "yml" else {
            throw ConfigurationError.unsupportedConfigExtension(fileExtension)
        }

        let data = try Data(contentsOf: url)
        let contents = String(decoding: data, as: UTF8.self)
        let configuration = try YAMLDecoder().decode(ConfigurationFile.self, from: contents)
        let snippetGroups = try parseSnippetGroups(from: contents)

        guard !configuration.shortcuts.isEmpty || !snippetGroups.isEmpty else {
            throw ConfigurationError.emptyConfiguration
        }

        var seenHotkeys = Set<String>()
        var loadedShortcuts: [LoadedShortcut] = []

        for (index, shortcut) in configuration.shortcuts.enumerated() {
            let shortcutID = shortcut.id ?? "shortcut-\(index + 1)"

            guard hasMatcher(shortcut) else {
                throw ConfigurationError.missingMatcher(shortcutID)
            }

            let windowIndex = shortcut.windowIndex ?? 0
            guard windowIndex >= 0 else {
                throw ConfigurationError.invalidWindowIndex(shortcutID, windowIndex)
            }

            let hotKey = try KeyCombo.parse(shortcut.hotkey)
            if let reservedUsage = ReservedHotKeys.descriptionsByNormalizedValue[hotKey.normalizedValue] {
                throw ConfigurationError.reservedHotkey(hotKey.normalizedValue, reservedUsage)
            }
            guard seenHotkeys.insert(hotKey.normalizedValue).inserted else {
                throw ConfigurationError.duplicateHotkey(hotKey.normalizedValue)
            }

            let matcher = WindowMatcher(
                bundleID: shortcut.bundleID,
                appNameRegex: try compileRegex(shortcut.appNameRegex, field: "app-name-regex", shortcutID: shortcutID),
                executablePathPrefix: shortcut.executablePathPrefix,
                titleRegex: try compileRegex(shortcut.titleRegex, field: "title-regex", shortcutID: shortcutID),
                titleContains: shortcut.titleContains,
                documentRegex: try compileRegex(shortcut.documentRegex, field: "document-regex", shortcutID: shortcutID),
                urlRegex: try compileRegex(shortcut.urlRegex, field: "url-regex", shortcutID: shortcutID),
                identifierRegex: try compileRegex(shortcut.identifierRegex, field: "identifier-regex", shortcutID: shortcutID),
                windowIndex: windowIndex
            )

            loadedShortcuts.append(
                LoadedShortcut(
                    id: shortcutID,
                    hotKey: hotKey,
                    matcher: matcher
                )
            )
        }

        return LoadedConfiguration(shortcuts: loadedShortcuts, snippetGroups: snippetGroups)
    }

    private static func parseSnippetGroups(from contents: String) throws -> [SnippetGroup] {
        guard let root = try Yams.compose(yaml: contents) else {
            return []
        }

        guard let snippetsNode = root["snippets"] else {
            return []
        }

        guard let snippetsMapping = snippetsNode.mapping else {
            throw ConfigurationError.invalidSnippets("`snippets` must be a mapping of groups.")
        }

        return try snippetsMapping.map { groupPair in
            guard let groupTitle = groupPair.key.string, !groupTitle.isEmpty else {
                throw ConfigurationError.invalidSnippets("Snippet group names must be strings.")
            }

            guard let groupMapping = groupPair.value.mapping else {
                throw ConfigurationError.invalidSnippets("Snippet group `\(groupTitle)` must contain key-value snippets.")
            }

            let snippets = try groupMapping.map { snippetPair in
                guard let title = snippetPair.key.string, !title.isEmpty else {
                    throw ConfigurationError.invalidSnippets("Snippet names in group `\(groupTitle)` must be strings.")
                }

                guard let content = snippetPair.value.string else {
                    throw ConfigurationError.invalidSnippets("Snippet `\(title)` in group `\(groupTitle)` must be a string.")
                }

                return Snippet(title: title, content: content)
            }

            return SnippetGroup(title: groupTitle, snippets: snippets)
        }
    }

    private static func hasMatcher(_ shortcut: ShortcutConfiguration) -> Bool {
            shortcut.bundleID != nil ||
            shortcut.appNameRegex != nil ||
            shortcut.executablePathPrefix != nil ||
            shortcut.titleRegex != nil ||
            shortcut.titleContains != nil ||
            shortcut.documentRegex != nil ||
            shortcut.urlRegex != nil ||
            shortcut.identifierRegex != nil
    }

    private static func compileRegex(
        _ pattern: String?,
        field: String,
        shortcutID: String
    ) throws -> NSRegularExpression? {
        guard let pattern, !pattern.isEmpty else {
            return nil
        }

        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            throw ConfigurationError.invalidRegex(field: field, shortcutID: shortcutID, error: error)
        }
    }
}
