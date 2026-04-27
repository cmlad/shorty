import XCTest
@testable import ShortyCore

final class ConfigurationTests: XCTestCase {
    func testParsesHotkey() throws {
        let combo = try KeyCombo.parse("cmd+option+1")
        XCTAssertEqual(combo.normalizedValue, "cmd+option+1")
    }

    func testLoadsValidConfiguration() throws {
        let url = try temporaryConfigURL(
            contents: """
            {
              "shortcuts": [
                {
                  "id": "project-a",
                  "hotkey": "cmd+option+1",
                  "bundleId": "com.microsoft.VSCode",
                  "titleRegex": "project-a"
                }
              ]
            }
            """
        )

        let configuration = try ConfigurationLoader.load(from: url)
        XCTAssertEqual(configuration.shortcuts.count, 1)
        XCTAssertEqual(configuration.shortcuts.first?.id, "project-a")
        XCTAssertEqual(configuration.shortcuts.first?.hotKey.normalizedValue, "cmd+option+1")
    }

    func testLoadsExecutablePathMatcherConfiguration() throws {
        let url = try temporaryConfigURL(
            contents: """
            {
              "shortcuts": [
                {
                  "id": "portable-vscode",
                  "hotkey": "cmd+option+1",
                  "executablePathRegex": "/Applications/VSCode-Portable/.*/Code"
                }
              ]
            }
            """
        )

        let configuration = try ConfigurationLoader.load(from: url)
        XCTAssertEqual(configuration.shortcuts.count, 1)
        XCTAssertEqual(configuration.shortcuts.first?.id, "portable-vscode")
        XCTAssertEqual(configuration.shortcuts.first?.matcher.executablePathRegex?.pattern, "/Applications/VSCode-Portable/.*/Code")
    }

    func testRejectsDuplicateHotkeys() throws {
        let url = try temporaryConfigURL(
            contents: """
            {
              "shortcuts": [
                {
                  "id": "a",
                  "hotkey": "cmd+option+1",
                  "bundleId": "com.microsoft.VSCode"
                },
                {
                  "id": "b",
                  "hotkey": "cmd+option+1",
                  "bundleId": "com.apple.Terminal"
                }
              ]
            }
            """
        )

        XCTAssertThrowsError(try ConfigurationLoader.load(from: url))
    }

    func testRejectsInvalidRegex() throws {
        let url = try temporaryConfigURL(
            contents: """
            {
              "shortcuts": [
                {
                  "id": "broken",
                  "hotkey": "cmd+option+1",
                  "bundleId": "com.microsoft.VSCode",
                  "titleRegex": "("
                }
              ]
            }
            """
        )

        XCTAssertThrowsError(try ConfigurationLoader.load(from: url))
    }

    private func temporaryConfigURL(contents: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("config.json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
