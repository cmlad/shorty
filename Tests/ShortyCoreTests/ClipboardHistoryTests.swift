import AppKit
import XCTest
@testable import ShortyCore

final class ClipboardHistoryTests: XCTestCase {
    func testStoreDeduplicatesAndEnforcesMaxCount() throws {
        let store = ClipboardHistoryStore(url: try temporaryHistoryURL(), maxStoredItems: 2)

        store.add(ClipboardItem(plainText: "A"))
        store.add(ClipboardItem(plainText: "B"))
        store.add(ClipboardItem(plainText: "A"))

        XCTAssertEqual(store.recentItems().map(\.plainText), ["A", "B"])

        store.add(ClipboardItem(plainText: "C"))

        XCTAssertEqual(store.recentItems().map(\.plainText), ["C", "A"])
    }

    func testStorePersistsItems() throws {
        let url = try temporaryHistoryURL()
        let store = ClipboardHistoryStore(url: url)

        store.add(ClipboardItem(plainText: "Persisted"))

        let reloadedStore = ClipboardHistoryStore(url: url)
        XCTAssertEqual(reloadedStore.recentItems().map(\.plainText), ["Persisted"])
    }

    func testReadsAndRestoresRTFClipboardItem() throws {
        let pasteboard = uniquePasteboard()
        let rtfData = try makeRTFData("Rich text")

        pasteboard.declareTypes([.rtf, .string], owner: nil)
        pasteboard.setData(rtfData, forType: .rtf)
        pasteboard.setString("Rich text", forType: .string)

        let item = try XCTUnwrap(ClipboardItem.read(from: pasteboard))
        XCTAssertEqual(item.plainText, "Rich text")
        XCTAssertEqual(item.rtfData, rtfData)

        let restoredPasteboard = uniquePasteboard()
        let paster = ClipboardPaster(pasteboard: restoredPasteboard)
        paster.copyToPasteboard(item)

        XCTAssertEqual(restoredPasteboard.string(forType: .string), "Rich text")
        XCTAssertEqual(restoredPasteboard.data(forType: .rtf), rtfData)
    }

    func testIgnoresEmptyTextOnlyPasteboardItem() {
        let pasteboard = uniquePasteboard()

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("", forType: .string)

        XCTAssertNil(ClipboardItem.read(from: pasteboard))
    }

    func testIgnoresWhitespaceOnlyTextPasteboardItem() {
        let pasteboard = uniquePasteboard()

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(" \n\t  ", forType: .string)

        XCTAssertNil(ClipboardItem.read(from: pasteboard))
    }

    func testMenuTitlePreservesLeadingSpacesAndUsesConfiguredCutoff() {
        let item = ClipboardItem(plainText: "  " + String(repeating: "a", count: 100))
        let title = item.menuTitle()

        XCTAssertTrue(title.hasPrefix("  "))
        XCTAssertEqual(title.count, ClipboardConstants.maxMenuItemTitleLength)
        XCTAssertTrue(title.hasSuffix("..."))
    }

    func testMenuTitleUsesFirstNonBlankLineWhenFirstLineIsBlank() {
        let item = ClipboardItem(plainText: "\n\n  First content line\nSecond line")

        XCTAssertEqual(item.menuTitle(), ">   First content line")
    }

    private func uniquePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    }

    private func makeRTFData(_ string: String) throws -> Data {
        let attributed = NSAttributedString(
            string: string,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]
        )
        return try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private func temporaryHistoryURL() throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ClipboardHistory.json")
    }
}
