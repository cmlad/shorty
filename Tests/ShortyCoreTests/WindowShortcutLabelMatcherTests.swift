import XCTest
@testable import ShortyCore

final class WindowShortcutLabelMatcherTests: XCTestCase {
    func testBundleAndTitleShortcutLabelsMatchingWindow() throws {
        let shortcut = try makeShortcut(
            id: "project-a",
            titleRegex: "Project A"
        )
        let candidate = makeCandidate(title: "Project A - Notes")

        let labels = WindowShortcutLabelMatcher.shortcutNames(for: [candidate], shortcuts: [shortcut])

        XCTAssertEqual(labels[candidate.id], "project-a")
    }

    func testNonmatchingShortcutLeavesWindowUnlabeled() throws {
        let shortcut = try makeShortcut(
            id: "project-a",
            titleRegex: "Project A"
        )
        let candidate = makeCandidate(title: "Project B - Notes")

        let labels = WindowShortcutLabelMatcher.shortcutNames(for: [candidate], shortcuts: [shortcut])

        XCTAssertNil(labels[candidate.id])
    }

    func testFirstLoadedShortcutWinsWhenMultipleShortcutsMatch() throws {
        let first = try makeShortcut(id: "first", titleContains: "Project")
        let second = try makeShortcut(id: "second", titleContains: "Project")
        let candidate = makeCandidate(title: "Project A")

        let labels = WindowShortcutLabelMatcher.shortcutNames(for: [candidate], shortcuts: [first, second])

        XCTAssertEqual(labels[candidate.id], "first")
    }

    func testWindowIndexDoesNotLimitDisplayedLabels() throws {
        let shortcut = try makeShortcut(id: "second-window", windowIndex: 1)
        let first = makeCandidate(id: "window-1", title: "Project")
        let second = makeCandidate(id: "window-2", title: "Project")

        let labels = WindowShortcutLabelMatcher.shortcutNames(for: [first, second], shortcuts: [shortcut])

        XCTAssertEqual(labels[first.id], "second-window")
        XCTAssertEqual(labels[second.id], "second-window")
    }

    func testMetadataDependentShortcutDoesNotLabelWithoutMetadata() throws {
        let shortcut = try makeShortcut(
            id: "docs",
            documentRegex: "/src/project-a/"
        )
        let candidate = makeCandidate(title: "Project A", document: nil)

        let labels = WindowShortcutLabelMatcher.shortcutNames(for: [candidate], shortcuts: [shortcut])

        XCTAssertNil(labels[candidate.id])
    }

    func testMetadataDependentShortcutLabelsWhenMetadataIsPresent() throws {
        let shortcut = try makeShortcut(
            id: "docs",
            documentRegex: "/src/project-a/"
        )
        let candidate = makeCandidate(
            title: "Project A",
            document: "/Users/chris/src/project-a/file.swift"
        )

        let labels = WindowShortcutLabelMatcher.shortcutNames(for: [candidate], shortcuts: [shortcut])

        XCTAssertEqual(labels[candidate.id], "docs")
    }

    private func makeShortcut(
        id: String,
        bundleID: String? = "com.example.Editor",
        titleRegex: String? = nil,
        titleContains: String? = nil,
        documentRegex: String? = nil,
        windowIndex: Int = 0
    ) throws -> LoadedShortcut {
        LoadedShortcut(
            id: id,
            hotKey: try KeyCombo.parse("cmd+option+1"),
            matcher: WindowMatcher(
                bundleID: bundleID,
                appNameRegex: nil,
                executablePathPrefix: nil,
                titleRegex: try titleRegex.map { try NSRegularExpression(pattern: $0) },
                titleContains: titleContains,
                documentRegex: try documentRegex.map { try NSRegularExpression(pattern: $0) },
                urlRegex: nil,
                identifierRegex: nil,
                windowIndex: windowIndex
            )
        )
    }

    private func makeCandidate(
        id: String = "window-1",
        title: String,
        document: String? = nil
    ) -> WindowShortcutCandidate {
        WindowShortcutCandidate(
            id: id,
            bundleID: "com.example.Editor",
            appName: "Editor",
            executablePath: "/Applications/Editor.app/Contents/MacOS/Editor",
            title: title,
            document: document,
            url: nil,
            identifier: nil
        )
    }
}
