import AppKit
import Foundation

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
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Shorty")
            .appendingPathComponent("config.json")
    }

    public static let usage = """
    Usage:
      Shorty [--config /path/to/config.json]
      Shorty --validate-config [--config /path/to/config.json]
      Shorty --list-windows [--verbose]

    Options:
      --config PATH         Use a specific JSON config file
      --validate-config     Parse and validate config, then exit
      --list-windows        Print accessible windows with bundle ID and title
      --verbose             Print extra window metadata in list mode
      --help                Show this help
    """
}

public struct ConfigurationFile: Codable {
    public let shortcuts: [ShortcutConfiguration]
}

public struct ShortcutConfiguration: Codable {
    public let id: String?
    public let hotkey: String
    public let bundleID: String?
    public let appNameRegex: String?
    public let executablePathRegex: String?
    public let titleRegex: String?
    public let titleContains: String?
    public let documentRegex: String?
    public let urlRegex: String?
    public let identifierRegex: String?
    public let windowIndex: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case hotkey
        case bundleID = "bundleId"
        case appNameRegex
        case executablePathRegex
        case titleRegex
        case titleContains
        case documentRegex
        case urlRegex
        case identifierRegex
        case windowIndex
    }
}

public enum ConfigurationError: Error, CustomStringConvertible {
    case emptyShortcuts
    case missingMatcher(String)
    case invalidWindowIndex(String, Int)
    case invalidRegex(field: String, shortcutID: String, error: Error)
    case duplicateHotkey(String)

    public var description: String {
        switch self {
        case .emptyShortcuts:
            return "Config has no shortcuts."
        case let .missingMatcher(shortcutID):
            return "Shortcut `\(shortcutID)` needs at least one matcher field."
        case let .invalidWindowIndex(shortcutID, value):
            return "Shortcut `\(shortcutID)` has invalid windowIndex `\(value)`. Use 0 or higher."
        case let .invalidRegex(field, shortcutID, error):
            return "Shortcut `\(shortcutID)` has invalid regex for `\(field)`: \(error.localizedDescription)"
        case let .duplicateHotkey(hotkey):
            return "Duplicate hotkey `\(hotkey)` in config."
        }
    }
}

public struct LoadedConfiguration {
    public let shortcuts: [LoadedShortcut]
}

public struct LoadedShortcut {
    public let id: String
    public let hotKey: KeyCombo
    public let matcher: WindowMatcher
}

public struct WindowMatcher {
    public let bundleID: String?
    public let appNameRegex: NSRegularExpression?
    public let executablePathRegex: NSRegularExpression?
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

        if let executablePathRegex {
            guard let executablePath else {
                return false
            }

            guard Self.matches(regex: executablePathRegex, in: executablePath) else {
                return false
            }
        }

        return true
    }

    public var summary: String {
        var parts: [String] = []

        if let bundleID {
            parts.append("bundleId=\(bundleID)")
        }

        if let titleContains {
            parts.append("titleContains=\(titleContains)")
        }

        if let titleRegex {
            parts.append("titleRegex=\(titleRegex.pattern)")
        }

        if let documentRegex {
            parts.append("documentRegex=\(documentRegex.pattern)")
        }

        if let urlRegex {
            parts.append("urlRegex=\(urlRegex.pattern)")
        }

        if let identifierRegex {
            parts.append("identifierRegex=\(identifierRegex.pattern)")
        }

        if let appNameRegex {
            parts.append("appNameRegex=\(appNameRegex.pattern)")
        }

        if let executablePathRegex {
            parts.append("executablePathRegex=\(executablePathRegex.pattern)")
        }

        if windowIndex > 0 {
            parts.append("windowIndex=\(windowIndex)")
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
        let data = try Data(contentsOf: url)
        let configuration = try JSONDecoder().decode(ConfigurationFile.self, from: data)

        guard !configuration.shortcuts.isEmpty else {
            throw ConfigurationError.emptyShortcuts
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
            guard seenHotkeys.insert(hotKey.normalizedValue).inserted else {
                throw ConfigurationError.duplicateHotkey(hotKey.normalizedValue)
            }

            let matcher = WindowMatcher(
                bundleID: shortcut.bundleID,
                appNameRegex: try compileRegex(shortcut.appNameRegex, field: "appNameRegex", shortcutID: shortcutID),
                executablePathRegex: try compileRegex(shortcut.executablePathRegex, field: "executablePathRegex", shortcutID: shortcutID),
                titleRegex: try compileRegex(shortcut.titleRegex, field: "titleRegex", shortcutID: shortcutID),
                titleContains: shortcut.titleContains,
                documentRegex: try compileRegex(shortcut.documentRegex, field: "documentRegex", shortcutID: shortcutID),
                urlRegex: try compileRegex(shortcut.urlRegex, field: "urlRegex", shortcutID: shortcutID),
                identifierRegex: try compileRegex(shortcut.identifierRegex, field: "identifierRegex", shortcutID: shortcutID),
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

        return LoadedConfiguration(shortcuts: loadedShortcuts)
    }

    private static func hasMatcher(_ shortcut: ShortcutConfiguration) -> Bool {
        shortcut.bundleID != nil ||
            shortcut.appNameRegex != nil ||
            shortcut.executablePathRegex != nil ||
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
