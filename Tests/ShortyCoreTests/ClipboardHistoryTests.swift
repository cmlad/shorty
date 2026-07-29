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

    func testStoreAddsPlainTextPasteToHistory() throws {
        let store = ClipboardHistoryStore(url: try temporaryHistoryURL(), maxStoredItems: 2)

        store.add(ClipboardItem(plainText: "Existing"))
        store.addPlainText("Snippet content")

        XCTAssertEqual(store.recentItems().map(\.plainText), ["Snippet content", "Existing"])
    }

    func testStoreDoesNotAddWhitespaceOnlyPlainTextPaste() throws {
        let store = ClipboardHistoryStore(url: try temporaryHistoryURL(), maxStoredItems: 2)

        store.addPlainText(" \n\t  ")

        XCTAssertEqual(store.recentItems(), [])
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

    func testCopyTextToPasteboardOmitsRichRepresentations() throws {
        let pasteboard = uniquePasteboard()
        let item = ClipboardItem(
            plainText: "Clean",
            rtfData: try makeRTFData("Clean"),
            additionalRepresentations: [
                ClipboardRepresentation(type: "com.apple.notes.richtext", data: Data("rich".utf8)),
            ]
        )
        let paster = ClipboardPaster(pasteboard: pasteboard)

        paster.copyToPasteboard(item)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))

        paster.copyTextToPasteboard(item.plainText)

        XCTAssertEqual(pasteboard.string(forType: .string), "Clean")
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertNil(pasteboard.data(forType: NSPasteboard.PasteboardType("com.apple.notes.richtext")))
    }

    func testReadsAndRestoresAdditionalRichTextRepresentations() throws {
        let pasteboard = uniquePasteboard()
        let notesType = NSPasteboard.PasteboardType("com.apple.notes.richtext")
        let notesData = Data("notes checklist payload".utf8)

        pasteboard.declareTypes([notesType, .string], owner: nil)
        pasteboard.setData(notesData, forType: notesType)
        pasteboard.setString("Checklist", forType: .string)

        let item = try XCTUnwrap(ClipboardItem.read(from: pasteboard))
        XCTAssertEqual(item.additionalRepresentations, [
            ClipboardRepresentation(type: notesType.rawValue, data: notesData),
        ])

        let restoredPasteboard = uniquePasteboard()
        let paster = ClipboardPaster(pasteboard: restoredPasteboard)
        paster.copyToPasteboard(item)

        XCTAssertEqual(restoredPasteboard.string(forType: .string), "Checklist")
        XCTAssertEqual(restoredPasteboard.data(forType: notesType), notesData)
    }

    func testDecodesLegacyHistoryItemsWithoutAdditionalRepresentations() throws {
        let legacyJSON = """
        [{
          "id": "legacy",
          "plainText": "Legacy",
          "createdAt": 0,
          "updatedAt": 0
        }]
        """.data(using: .utf8)!

        let items = try JSONDecoder().decode([ClipboardItem].self, from: legacyJSON)

        XCTAssertEqual(items.first?.id, "legacy")
        XCTAssertEqual(items.first?.plainText, "Legacy")
        XCTAssertEqual(items.first?.additionalRepresentations, [])
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

    func testMenuTitleUsesFirstNonBlankLineWithoutPrefixWhenFirstLineIsBlank() {
        let item = ClipboardItem(plainText: "\n\n  First content line\nSecond line")

        XCTAssertEqual(item.menuTitle(), "  First content line +1")
    }

    func testMenuTitleShowsAdditionalLineCountAndPreservesCutoffForMultilineText() {
        let item = ClipboardItem(plainText: String(repeating: "a", count: 100) + "\nSecond line")
        let title = item.menuTitle()

        XCTAssertEqual(title.count, ClipboardConstants.maxMenuItemTitleLength)
        XCTAssertTrue(title.hasSuffix("... +1"))
    }

    func testMenuTitleCountsMultipleAdditionalLines() {
        let item = ClipboardItem(plainText: "First\nSecond\nThird\nFourth\nFifth\nSixth")

        XCTAssertEqual(item.menuTitle(), "First +5")
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
