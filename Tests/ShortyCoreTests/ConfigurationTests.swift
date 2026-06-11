import AppKit
import XCTest
@testable import ShortyCore

final class ConfigurationTests: XCTestCase {
    func testParsesHotkey() throws {
        let combo = try KeyCombo.parse("cmd+option+1")
        XCTAssertEqual(combo.normalizedValue, "cmd+option+1")
    }

    func testLoadsValidYAMLDictionaryConfiguration() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              project-a:
                hotkey: cmd+option+1
                bundle-id: com.microsoft.VSCode
                title-regex: project-a
            """
        )

        let configuration = try ConfigurationLoader.load(from: url)
        XCTAssertEqual(configuration.shortcuts.count, 1)
        XCTAssertEqual(configuration.shortcuts.first?.id, "project-a")
        XCTAssertEqual(configuration.shortcuts.first?.hotKey.normalizedValue, "cmd+option+1")
    }

    func testLoadsYMLConfiguration() throws {
        let url = try temporaryConfigURL(
            extension: "yml",
            contents: """
            shortcuts:
              project-a:
                hotkey: cmd+option+1
                bundle-id: com.microsoft.VSCode
            """
        )

        let configuration = try ConfigurationLoader.load(from: url)
        XCTAssertEqual(configuration.shortcuts.count, 1)
        XCTAssertEqual(configuration.shortcuts.first?.id, "project-a")
    }

    func testLoadsGroupedSnippets() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              project-a:
                hotkey: cmd+option+1
                bundle-id: com.microsoft.VSCode
            snippets:
              Work:
                Zebra: Last alphabetically but first in config
                Greeting: Hello there
                Rich Example: Plain fallback text
              Personal:
                Address: 123 Example St
            """
        )

        let configuration = try ConfigurationLoader.load(from: url)
        XCTAssertEqual(configuration.snippetGroups.count, 2)
        XCTAssertEqual(configuration.snippetGroups.map(\.title), ["Work", "Personal"])
        XCTAssertEqual(configuration.snippetGroups[0].snippets.map(\.title), ["Zebra", "Greeting", "Rich Example"])
        XCTAssertEqual(configuration.snippetGroups[0].snippets[1].content, "Hello there")
    }

    func testAllowsSnippetOnlyConfiguration() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            snippets:
              Work:
                Greeting: Hello there
            """
        )

        let configuration = try ConfigurationLoader.load(from: url)
        XCTAssertTrue(configuration.shortcuts.isEmpty)
        XCTAssertEqual(configuration.snippetGroups.first?.snippets.first?.title, "Greeting")
    }

    func testRejectsArrayConfiguration() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              - id: project-a
                hotkey: cmd+option+1
                bundle-id: com.microsoft.VSCode
                title-regex: project-a
            """
        )

        XCTAssertThrowsError(try ConfigurationLoader.load(from: url))
    }

    func testRejectsReservedClipboardMenuHotkey() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              reserved:
                hotkey: cmd+shift+v
                bundle-id: com.microsoft.VSCode
            """
        )

        XCTAssertThrowsError(try ConfigurationLoader.load(from: url)) { error in
            XCTAssertTrue(String(describing: error).contains("reserved"))
        }
    }

    func testRejectsReservedSnippetMenuHotkey() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              reserved:
                hotkey: cmd+shift+b
                bundle-id: com.microsoft.VSCode
            """
        )

        XCTAssertThrowsError(try ConfigurationLoader.load(from: url)) { error in
            XCTAssertTrue(String(describing: error).contains("reserved"))
        }
    }

    func testRejectsReservedWindowSwitcherHotkey() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              reserved:
                hotkey: cmd+tab
                bundle-id: com.microsoft.VSCode
            """
        )

        XCTAssertThrowsError(try ConfigurationLoader.load(from: url)) { error in
            XCTAssertTrue(String(describing: error).contains("reserved"))
        }
    }

    func testRejectsReservedCurrentAppWindowSwitcherHotkey() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              reserved:
                hotkey: cmd+grave
                bundle-id: com.microsoft.VSCode
            """
        )

        XCTAssertThrowsError(try ConfigurationLoader.load(from: url)) { error in
            XCTAssertTrue(String(describing: error).contains("reserved"))
        }
    }

    func testRejectsReservedWindowMovementHotkeys() throws {
        let hotkeys = [
            "ctrl+option+left",
            "ctrl+option+right",
            "ctrl+option+cmd+up",
            "ctrl+option+cmd+left",
            "ctrl+option+cmd+right",
        ]

        for hotkey in hotkeys {
            let url = try temporaryConfigURL(
                extension: "yaml",
                contents: """
                shortcuts:
                  reserved:
                    hotkey: \(hotkey)
                    bundle-id: com.microsoft.VSCode
                """
            )

            XCTAssertThrowsError(try ConfigurationLoader.load(from: url), "Expected \(hotkey) to be reserved") { error in
                XCTAssertTrue(String(describing: error).contains("reserved"))
            }
        }
    }

    func testLoadsExecutablePathPrefixMatcherConfiguration() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              portable-vscode:
                hotkey: cmd+option+1
                executable-path-prefix: /Applications/VSCode-Portable.app/
            """
        )

        let configuration = try ConfigurationLoader.load(from: url)
        XCTAssertEqual(configuration.shortcuts.count, 1)
        XCTAssertEqual(configuration.shortcuts.first?.id, "portable-vscode")
        XCTAssertEqual(configuration.shortcuts.first?.matcher.executablePathPrefix, "/Applications/VSCode-Portable.app/")
    }

    func testExecutablePathPrefixUsesLiteralPrefix() {
        let matcher = WindowMatcher(
            bundleID: nil,
            appNameRegex: nil,
            executablePathPrefix: "/Applications/Cursor.app/",
            titleRegex: nil,
            titleContains: nil,
            documentRegex: nil,
            urlRegex: nil,
            identifierRegex: nil,
            windowIndex: 0
        )

        XCTAssertTrue(
            matcher.matchesApplication(
                app: NSRunningApplication.current,
                executablePath: "/Applications/Cursor.app/Contents/MacOS/Cursor"
            )
        )
        XCTAssertFalse(
            matcher.matchesApplication(
                app: NSRunningApplication.current,
                executablePath: "/Applications/CursorXapp/Contents/MacOS/Cursor"
            )
        )
    }

    func testRejectsDuplicateHotkeys() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              a:
                hotkey: cmd+option+1
                bundle-id: com.microsoft.VSCode
              b:
                hotkey: cmd+option+1
                bundle-id: com.apple.Terminal
            """
        )

        XCTAssertThrowsError(try ConfigurationLoader.load(from: url))
    }

    func testRejectsInvalidRegex() throws {
        let url = try temporaryConfigURL(
            extension: "yaml",
            contents: """
            shortcuts:
              broken:
                hotkey: cmd+option+1
                bundle-id: com.microsoft.VSCode
                title-regex: (
            """
        )

        XCTAssertThrowsError(try ConfigurationLoader.load(from: url))
    }

    private func temporaryConfigURL(extension fileExtension: String, contents: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("config.\(fileExtension)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
