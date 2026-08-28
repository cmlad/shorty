import XCTest
@testable import ShortyCore

final class ClipboardPickerSearchTests: XCTestCase {
    func testRootEntriesUseMenuShapeWithHistoryOverflowAndSnippetFolders() throws {
        let history = (1...45).map { ClipboardItem(plainText: "History \($0)") }
        let groups = [
            SnippetGroup(
                title: "Work",
                snippets: [Snippet(title: "Greeting", content: "Hello")]
            ),
            SnippetGroup(
                title: "Personal",
                snippets: [Snippet(title: "Address", content: "123 Main")]
            ),
        ]

        let entries = ClipboardPickerSearch.rootEntries(
            history: history,
            snippetGroups: groups,
            query: "",
            mode: .all
        )

        XCTAssertEqual(entries[0], .header("History"))
        XCTAssertEqual(entries[1...20].compactMap(\.pasteResult), history.prefix(20).map { .history($0) })
        XCTAssertEqual(entries[21].title, "21 - 40")
        XCTAssertEqual(entries[22].title, "41 - 45")
        XCTAssertEqual(entries[23], .header("Snippets"))
        XCTAssertEqual(entries[24].title, "Work")
        XCTAssertEqual(entries[25].title, "Personal")

        guard case let .folder(firstHistoryFolder) = entries[21] else {
            return XCTFail("Expected first history overflow folder")
        }

        XCTAssertEqual(
            firstHistoryFolder.entries.compactMap(\.pasteResult),
            history[20..<40].map { .history($0) }
        )

        guard case let .folder(workFolder) = entries[24] else {
            return XCTFail("Expected snippet folder")
        }

        XCTAssertEqual(workFolder.entries, [
            .snippet(groupTitle: "Work", snippet: groups[0].snippets[0]),
        ])
    }

    func testRootSearchFlattensMatchingDescendants() throws {
        let history = (1...25).map { index in
            ClipboardItem(plainText: index == 25 ? "Deep needle" : "History \(index)")
        }
        let groups = [
            SnippetGroup(
                title: "Work",
                snippets: [Snippet(title: "Greeting", content: "Hello needle")]
            ),
        ]

        let entries = ClipboardPickerSearch.rootEntries(
            history: history,
            snippetGroups: groups,
            query: "needle",
            mode: .all
        )

        XCTAssertEqual(entries.map(\.title), ["History", "Deep needle", "Snippets", "Greeting"])
        XCTAssertEqual(entries[1].pasteResult, .history(history[24]))
        XCTAssertEqual(entries[3].pasteResult, .snippet(groupTitle: "Work", snippet: groups[0].snippets[0]))
    }

    func testRootSearchKeepsMatchingFoldersOpenable() throws {
        let history = (1...25).map { ClipboardItem(plainText: "History \($0)") }
        let groups = [
            SnippetGroup(
                title: "Infrastructure",
                snippets: [Snippet(title: "Deploy", content: "ship it")]
            ),
        ]

        let entries = ClipboardPickerSearch.rootEntries(
            history: history,
            snippetGroups: groups,
            query: "infra",
            mode: .all
        )

        XCTAssertEqual(entries.map(\.title), ["Snippets", "Infrastructure"])
        XCTAssertNotNil(entries[1].folder)
    }

    func testHistoryTitlesUsePickerCutoffInsteadOfMenuCutoff() {
        let longText = String(repeating: "a", count: ClipboardConstants.maxMenuItemTitleLength + 20)
        let entries = ClipboardPickerSearch.rootEntries(
            history: [ClipboardItem(plainText: longText)],
            snippetGroups: [],
            query: "",
            mode: .all
        )

        XCTAssertEqual(entries[1].title, longText)
    }

    func testHistoryPresentationSeparatesLineCountMarker() throws {
        let item = ClipboardItem(plainText: "First line\nSecond line\nThird line")
        let entries = ClipboardPickerSearch.rootEntries(
            history: [item],
            snippetGroups: [],
            query: "",
            mode: .all
        )
        let presentation = entries[1].presentation

        XCTAssertEqual(presentation.title, "First line")
        XCTAssertEqual(presentation.trailingLineCountLabel, "+2")
        XCTAssertEqual(entries[1].title, "First line")
    }

    func testHistoryPresentationOmitsLineCountMarkerForSingleLineItems() throws {
        let item = ClipboardItem(plainText: "Only line")
        let entries = ClipboardPickerSearch.rootEntries(
            history: [item],
            snippetGroups: [],
            query: "",
            mode: .all
        )
        let presentation = entries[1].presentation

        XCTAssertEqual(presentation.title, "Only line")
        XCTAssertNil(presentation.trailingLineCountLabel)
    }

    func testHistoryPresentationUsesFirstNonBlankLineAndCountsFollowingLines() throws {
        let item = ClipboardItem(plainText: "\n\n  First content line\nSecond line")
        let entries = ClipboardPickerSearch.rootEntries(
            history: [item],
            snippetGroups: [],
            query: "",
            mode: .all
        )
        let presentation = entries[1].presentation

        XCTAssertEqual(presentation.title, "  First content line")
        XCTAssertEqual(presentation.trailingLineCountLabel, "+1")
    }

    func testFolderSearchOnlyFiltersFolderEntries() throws {
        let folder = ClipboardPickerFolder(
            id: "snippets:Work",
            title: "Work",
            kind: .snippets,
            entries: [
                .snippet(groupTitle: "Work", snippet: Snippet(title: "Greeting", content: "Hello")),
                .snippet(groupTitle: "Work", snippet: Snippet(title: "Incident", content: "Status update")),
            ]
        )

        let entries = ClipboardPickerSearch.folderEntries(in: folder, query: "incident")

        XCTAssertEqual(entries, [
            .snippet(groupTitle: "Work", snippet: Snippet(title: "Incident", content: "Status update")),
        ])
    }

    func testSnippetsOnlyRootEntriesExcludeHistory() {
        let history = [ClipboardItem(plainText: "History")]
        let groups = [
            SnippetGroup(title: "Work", snippets: [Snippet(title: "Greeting", content: "Hello")]),
        ]

        let entries = ClipboardPickerSearch.rootEntries(
            history: history,
            snippetGroups: groups,
            query: "",
            mode: .snippetsOnly
        )

        XCTAssertEqual(entries.map(\.title), ["Snippets", "Work"])
    }

    func testEmptyQueryShowsHistoryThenSnippetsInSourceOrder() {
        let firstHistory = ClipboardItem(plainText: "Recent clipboard")
        let secondHistory = ClipboardItem(plainText: "Older clipboard")
        let groups = [
            SnippetGroup(
                title: "Work",
                snippets: [
                    Snippet(title: "Greeting", content: "Hello"),
                    Snippet(title: "Signoff", content: "Thanks"),
                ]
            ),
            SnippetGroup(
                title: "Personal",
                snippets: [
                    Snippet(title: "Address", content: "123 Main"),
                ]
            ),
        ]

        let results = ClipboardPickerSearch.results(
            history: [firstHistory, secondHistory],
            snippetGroups: groups,
            query: "",
            mode: .all
        )

        XCTAssertEqual(results, [
            .history(firstHistory),
            .history(secondHistory),
            .snippet(groupTitle: "Work", snippet: groups[0].snippets[0]),
            .snippet(groupTitle: "Work", snippet: groups[0].snippets[1]),
            .snippet(groupTitle: "Personal", snippet: groups[1].snippets[0]),
        ])
    }

    func testSearchMatchesHistoryFullTextCaseInsensitively() {
        let matching = ClipboardItem(plainText: "First line\nNeedle is on another line")
        let nonmatching = ClipboardItem(plainText: "Other value")

        let results = ClipboardPickerSearch.results(
            history: [matching, nonmatching],
            snippetGroups: [],
            query: "needle",
            mode: .all
        )

        XCTAssertEqual(results, [.history(matching)])
    }

    func testSearchMatchesSnippetGroupTitleSnippetTitleAndContent() {
        let groupMatched = SnippetGroup(
            title: "Infrastructure",
            snippets: [Snippet(title: "Deploy", content: "ship it")]
        )
        let titleMatched = SnippetGroup(
            title: "Work",
            snippets: [Snippet(title: "Incident reply", content: "looking")]
        )
        let contentMatched = SnippetGroup(
            title: "Personal",
            snippets: [Snippet(title: "Note", content: "incident followup")]
        )
        let nonmatching = SnippetGroup(
            title: "Other",
            snippets: [Snippet(title: "Todo", content: "later")]
        )

        let results = ClipboardPickerSearch.results(
            history: [],
            snippetGroups: [groupMatched, titleMatched, contentMatched, nonmatching],
            query: "incident",
            mode: .all
        )

        XCTAssertEqual(results, [
            .snippet(groupTitle: "Work", snippet: titleMatched.snippets[0]),
            .snippet(groupTitle: "Personal", snippet: contentMatched.snippets[0]),
        ])

        let groupResults = ClipboardPickerSearch.results(
            history: [],
            snippetGroups: [groupMatched, titleMatched, contentMatched, nonmatching],
            query: "infra",
            mode: .all
        )

        XCTAssertEqual(groupResults, [
            .snippet(groupTitle: "Infrastructure", snippet: groupMatched.snippets[0]),
        ])
    }

    func testSnippetsOnlyModeExcludesHistory() {
        let item = ClipboardItem(plainText: "Needle")
        let group = SnippetGroup(
            title: "Work",
            snippets: [Snippet(title: "Needle", content: "snippet")]
        )

        let results = ClipboardPickerSearch.results(
            history: [item],
            snippetGroups: [group],
            query: "needle",
            mode: .snippetsOnly
        )

        XCTAssertEqual(results, [
            .snippet(groupTitle: "Work", snippet: group.snippets[0]),
        ])
    }
}
