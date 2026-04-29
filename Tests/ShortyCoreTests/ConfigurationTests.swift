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
