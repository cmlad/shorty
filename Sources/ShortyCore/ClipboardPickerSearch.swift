import Foundation

public enum ClipboardPickerMode: Sendable {
    case all
    case snippetsOnly
}

public struct ClipboardPickerFolder: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable {
        case history
        case snippets
    }

    public let id: String
    public let title: String
    public let kind: Kind
    public let entries: [ClipboardPickerEntry]

    public init(id: String, title: String, kind: Kind, entries: [ClipboardPickerEntry]) {
        self.id = id
        self.title = title
        self.kind = kind
        self.entries = entries
    }
}

public struct ClipboardPickerEntryPresentation: Equatable, Sendable {
    public let title: String
    public let trailingLineCountLabel: String?

    public init(title: String, trailingLineCountLabel: String? = nil) {
        self.title = title
        self.trailingLineCountLabel = trailingLineCountLabel
    }
}

public indirect enum ClipboardPickerEntry: Equatable, Identifiable, Sendable {
    case header(String)
    case folder(ClipboardPickerFolder)
    case history(ClipboardItem)
    case snippet(groupTitle: String, snippet: Snippet)
    case back(String)
    case empty(String)

    public var id: String {
        switch self {
        case let .header(title):
            return "header:\(title)"
        case let .folder(folder):
            return "folder:\(folder.id)"
        case let .history(item):
            return "history:\(item.id)"
        case let .snippet(groupTitle, snippet):
            return "snippet:\(groupTitle):\(snippet.title):\(snippet.content)"
        case let .back(title):
            return "back:\(title)"
        case let .empty(title):
            return "empty:\(title)"
        }
    }

    public var title: String {
        presentation.title
    }

    public var presentation: ClipboardPickerEntryPresentation {
        switch self {
        case let .header(title), let .back(title), let .empty(title):
            return ClipboardPickerEntryPresentation(title: title)
        case let .folder(folder):
            return ClipboardPickerEntryPresentation(title: folder.title)
        case let .history(item):
            let preview = item.pickerLinePreview()
            return ClipboardPickerEntryPresentation(
                title: preview.title,
                trailingLineCountLabel: preview.trailingLineCountLabel
            )
        case let .snippet(_, snippet):
            return ClipboardPickerEntryPresentation(title: snippet.title)
        }
    }

    public var isSelectable: Bool {
        switch self {
        case .folder, .history, .snippet, .back:
            return true
        case .header, .empty:
            return false
        }
    }

    public var pasteResult: ClipboardPickerResult? {
        switch self {
        case let .history(item):
            return .history(item)
        case let .snippet(groupTitle, snippet):
            return .snippet(groupTitle: groupTitle, snippet: snippet)
        case .header, .folder, .back, .empty:
            return nil
        }
    }

    public var folder: ClipboardPickerFolder? {
        switch self {
        case let .folder(folder):
            return folder
        case .header, .history, .snippet, .back, .empty:
            return nil
        }
    }
}

public enum ClipboardPickerResult: Equatable, Identifiable, Sendable {
    case history(ClipboardItem)
    case snippet(groupTitle: String, snippet: Snippet)

    public var id: String {
        switch self {
        case let .history(item):
            return "history:\(item.id)"
        case let .snippet(groupTitle, snippet):
            return "snippet:\(groupTitle):\(snippet.title):\(snippet.content)"
        }
    }
}

public enum ClipboardPickerSearch {
    public static func rootEntries(
        history: [ClipboardItem],
        snippetGroups: [SnippetGroup],
        query: String,
        mode: ClipboardPickerMode
    ) -> [ClipboardPickerEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries: [ClipboardPickerEntry] = []

        if mode == .all {
            let historyEntries = rootEntriesMatching(
                rootHistoryEntries(history),
                query: normalizedQuery
            )

            if !historyEntries.isEmpty || normalizedQuery.isEmpty {
                entries.append(.header("History"))
                entries.append(contentsOf: historyEntries.isEmpty ? [.empty("No clipboard history")] : historyEntries)
            }
        }

        let snippetEntries = rootEntriesMatching(
            rootSnippetEntries(snippetGroups),
            query: normalizedQuery
        )

        if !snippetEntries.isEmpty || normalizedQuery.isEmpty {
            entries.append(.header("Snippets"))
            entries.append(contentsOf: snippetEntries.isEmpty ? [.empty("No snippets configured")] : snippetEntries)
        }

        return entries.isEmpty ? [.empty("No matches")] : entries
    }

    public static func folderEntries(
        in folder: ClipboardPickerFolder,
        query: String
    ) -> [ClipboardPickerEntry] {
        let entries = filtered(
            folder.entries,
            query: query.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        return entries.isEmpty ? [.empty("No matches")] : entries
    }

    public static func results(
        history: [ClipboardItem],
        snippetGroups: [SnippetGroup],
        query: String,
        mode: ClipboardPickerMode
    ) -> [ClipboardPickerResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let historyResults: [ClipboardPickerResult]

        switch mode {
        case .all:
            historyResults = history
                .filter { item in matches(normalizedQuery, in: [item.plainText]) }
                .map { .history($0) }
        case .snippetsOnly:
            historyResults = []
        }

        let snippetResults = snippetGroups.flatMap { group in
            group.snippets.compactMap { snippet -> ClipboardPickerResult? in
                guard matches(normalizedQuery, in: [group.title, snippet.title, snippet.content]) else {
                    return nil
                }

                return .snippet(groupTitle: group.title, snippet: snippet)
            }
        }

        return historyResults + snippetResults
    }

    private static func rootHistoryEntries(_ history: [ClipboardItem]) -> [ClipboardPickerEntry] {
        let items = Array(history.prefix(ClipboardConstants.maxVisibleItems))
        var entries = items
            .prefix(ClipboardConstants.maxDirectMenuItems)
            .map { ClipboardPickerEntry.history($0) }

        let overflowStart = ClipboardConstants.maxDirectMenuItems
        guard items.count > overflowStart else {
            return entries
        }

        let maxOverflowItems = ClipboardConstants.overflowSubmenuSize * ClipboardConstants.maxOverflowSubmenus
        let overflowEnd = min(items.count, overflowStart + maxOverflowItems)
        var rangeStart = overflowStart

        while rangeStart < overflowEnd {
            let rangeEnd = min(rangeStart + ClipboardConstants.overflowSubmenuSize, overflowEnd)
            let folderEntries = items[rangeStart..<rangeEnd].map { ClipboardPickerEntry.history($0) }
            entries.append(
                .folder(
                    ClipboardPickerFolder(
                        id: "history:\(rangeStart):\(rangeEnd)",
                        title: "\(rangeStart + 1) - \(rangeEnd)",
                        kind: .history,
                        entries: folderEntries
                    )
                )
            )
            rangeStart = rangeEnd
        }

        return entries
    }

    private static func rootSnippetEntries(_ snippetGroups: [SnippetGroup]) -> [ClipboardPickerEntry] {
        snippetGroups.compactMap { group in
            guard !group.snippets.isEmpty else {
                return nil
            }

            return .folder(
                ClipboardPickerFolder(
                    id: "snippets:\(group.title)",
                    title: group.title,
                    kind: .snippets,
                    entries: group.snippets.map { .snippet(groupTitle: group.title, snippet: $0) }
                )
            )
        }
    }

    private static func filtered(
        _ entries: [ClipboardPickerEntry],
        query: String
    ) -> [ClipboardPickerEntry] {
        guard !query.isEmpty else {
            return entries
        }

        return entries.filter { matches($0, query: query) }
    }

    private static func rootEntriesMatching(
        _ entries: [ClipboardPickerEntry],
        query: String
    ) -> [ClipboardPickerEntry] {
        guard !query.isEmpty else {
            return entries
        }

        return entries.flatMap { entry in
            switch entry {
            case let .folder(folder):
                var matches: [ClipboardPickerEntry] = []
                if self.matches(query, in: [folder.title]) {
                    matches.append(.folder(folder))
                }
                matches.append(contentsOf: folder.entries.filter { matchesOwnContent($0, query: query) })
                return matches
            case .header, .back, .empty:
                return []
            case .history, .snippet:
                return matchesOwnContent(entry, query: query) ? [entry] : []
            }
        }
    }

    private static func matches(_ entry: ClipboardPickerEntry, query: String) -> Bool {
        switch entry {
        case .header, .back, .empty:
            return false
        case let .folder(folder):
            return matches(query, in: [folder.title]) ||
                folder.entries.contains { matches($0, query: query) }
        case let .history(item):
            return matches(query, in: [item.plainText])
        case let .snippet(groupTitle, snippet):
            return matches(query, in: [groupTitle, snippet.title, snippet.content])
        }
    }

    private static func matchesOwnContent(_ entry: ClipboardPickerEntry, query: String) -> Bool {
        switch entry {
        case .header, .folder, .back, .empty:
            return false
        case let .history(item):
            return matches(query, in: [item.plainText])
        case let .snippet(_, snippet):
            return matches(query, in: [snippet.title, snippet.content])
        }
    }

    private static func matches(_ query: String, in values: [String]) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        return values.contains { value in
            value.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }
}
