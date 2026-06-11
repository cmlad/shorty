import Foundation

public struct WindowShortcutCandidate: Equatable, Sendable {
    public let id: String
    public let bundleID: String?
    public let appName: String
    public let executablePath: String?
    public let title: String
    public let document: String?
    public let url: String?
    public let identifier: String?

    public init(
        id: String,
        bundleID: String?,
        appName: String,
        executablePath: String?,
        title: String,
        document: String?,
        url: String?,
        identifier: String?
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.executablePath = executablePath
        self.title = title
        self.document = document
        self.url = url
        self.identifier = identifier
    }
}

public enum WindowShortcutLabelMatcher {
    public static func shortcutNames(
        for candidates: [WindowShortcutCandidate],
        shortcuts: [LoadedShortcut]
    ) -> [String: String] {
        var labels: [String: String] = [:]

        for shortcut in shortcuts {
            let matchingCandidates = candidates.filter { candidate in
                matches(shortcut.matcher, candidate: candidate)
            }

            for candidate in matchingCandidates where labels[candidate.id] == nil {
                labels[candidate.id] = shortcut.id
            }
        }

        return labels
    }

    public static func needsExactMetadata(for shortcuts: [LoadedShortcut]) -> Bool {
        shortcuts.contains { shortcut in
            shortcut.matcher.documentRegex != nil ||
                shortcut.matcher.urlRegex != nil ||
                shortcut.matcher.identifierRegex != nil
        }
    }

    private static func matches(_ matcher: WindowMatcher, candidate: WindowShortcutCandidate) -> Bool {
        if let bundleID = matcher.bundleID, candidate.bundleID != bundleID {
            return false
        }

        if let appNameRegex = matcher.appNameRegex, !matches(regex: appNameRegex, in: candidate.appName) {
            return false
        }

        if let executablePathPrefix = matcher.executablePathPrefix {
            guard let executablePath = candidate.executablePath else {
                return false
            }

            guard executablePath.hasPrefix(executablePathPrefix) else {
                return false
            }
        }

        if let titleRegex = matcher.titleRegex, !matches(regex: titleRegex, in: candidate.title) {
            return false
        }

        if let titleContains = matcher.titleContains {
            guard candidate.title.localizedCaseInsensitiveContains(titleContains) else {
                return false
            }
        }

        if let documentRegex = matcher.documentRegex {
            guard let document = candidate.document else {
                return false
            }

            guard matches(regex: documentRegex, in: document) else {
                return false
            }
        }

        if let urlRegex = matcher.urlRegex {
            guard let url = candidate.url else {
                return false
            }

            guard matches(regex: urlRegex, in: url) else {
                return false
            }
        }

        if let identifierRegex = matcher.identifierRegex {
            guard let identifier = candidate.identifier else {
                return false
            }

            guard matches(regex: identifierRegex, in: identifier) else {
                return false
            }
        }

        return true
    }

    private static func matches(regex: NSRegularExpression, in value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}
