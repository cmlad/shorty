import AppKit
import Carbon
import CryptoKit
import Foundation

public struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var plainText: String
    public var rtfData: Data?
    public var rtfdData: Data?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        plainText: String,
        rtfData: Data? = nil,
        rtfdData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = Self.makeID(plainText: plainText, rtfData: rtfData, rtfdData: rtfdData)
        self.plainText = plainText
        self.rtfData = rtfData
        self.rtfdData = rtfdData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func read(from pasteboard: NSPasteboard, now: Date = Date()) -> ClipboardItem? {
        let rtfData = firstData(from: pasteboard, types: PasteboardTypes.rtf)
        let rtfdData = firstData(from: pasteboard, types: PasteboardTypes.rtfd)
        let plainText = firstString(from: pasteboard, types: PasteboardTypes.string)
            ?? plainText(fromRTFDData: rtfdData)
            ?? plainText(fromRTFData: rtfData)
            ?? ""

        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rtfData != nil || rtfdData != nil else {
            return nil
        }

        return ClipboardItem(
            plainText: plainText,
            rtfData: rtfData,
            rtfdData: rtfdData,
            createdAt: now,
            updatedAt: now
        )
    }

    public func menuTitle(maxLength: Int = ClipboardConstants.maxMenuItemTitleLength) -> String {
        let lines = plainText.components(separatedBy: .newlines)
        let firstLine = lines.first ?? ""
        let title: String

        if firstLine.isEmpty {
            if let firstNonBlankLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                title = "> \(firstNonBlankLine)"
            } else {
                title = "> "
            }
        } else {
            title = firstLine
        }

        return title.shortyTruncated(maxLength: maxLength)
    }

    private static func firstString(from pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> String? {
        types.compactMap { pasteboard.string(forType: $0) }.first { !$0.isEmpty }
    }

    private static func firstData(from pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Data? {
        types.compactMap { pasteboard.data(forType: $0) }.first
    }

    private static func plainText(fromRTFData data: Data?) -> String? {
        guard let data, let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else {
            return nil
        }

        return attributed.string
    }

    private static func plainText(fromRTFDData data: Data?) -> String? {
        guard let data, let attributed = NSAttributedString(rtfd: data, documentAttributes: nil) else {
            return nil
        }

        return attributed.string
    }

    private static func makeID(plainText: String, rtfData: Data?, rtfdData: Data?) -> String {
        var data = Data()
        data.appendUTF8("plainText:")
        data.appendUTF8(plainText)

        if let rtfData {
            data.appendUTF8("\nrtf:")
            data.append(rtfData)
        }

        if let rtfdData {
            data.appendUTF8("\nrtfd:")
            data.append(rtfdData)
        }

        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum ClipboardConstants {
    public static let maxStoredItems = 200
    public static let maxVisibleItems = 200
    public static let maxDirectMenuItems = 20
    public static let overflowSubmenuSize = 20
    public static let maxOverflowSubmenus = 9
    public static let maxMenuItemTitleLength = 60
    public static let maxTooltipLength = 500
    public static let pollInterval: TimeInterval = 0.75
}

public final class ClipboardHistoryStore {
    private let url: URL
    private let maxStoredItems: Int
    private let lock = NSRecursiveLock()
    private var items: [ClipboardItem]

    public init(
        url: URL = ClipboardHistoryStore.defaultURL,
        maxStoredItems: Int = ClipboardConstants.maxStoredItems
    ) {
        self.url = url
        self.maxStoredItems = maxStoredItems
        self.items = Self.loadItems(from: url)
    }

    public static var defaultURL: URL {
        let applicationSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser

        return applicationSupportURL
            .appendingPathComponent("Shorty", isDirectory: true)
            .appendingPathComponent("ClipboardHistory.json")
    }

    public func add(_ item: ClipboardItem) {
        lock.lock()
        defer { lock.unlock() }

        var savedItem = item
        if let existingIndex = items.firstIndex(where: { $0.id == item.id }) {
            savedItem.createdAt = items[existingIndex].createdAt
            items.remove(at: existingIndex)
        }

        savedItem.updatedAt = Date()
        items.insert(savedItem, at: 0)

        if items.count > maxStoredItems {
            items.removeSubrange(maxStoredItems..<items.count)
        }

        save()
    }

    public func recentItems(limit: Int = ClipboardConstants.maxVisibleItems) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }

        return Array(items.prefix(limit))
    }

    private static func loadItems(from url: URL) -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }

        return (try? JSONDecoder().decode([ClipboardItem].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Clipboard history is best effort; runtime paste behavior should keep working.
        }
    }
}

public final class ClipboardMonitor: NSObject {
    private let pasteboard: NSPasteboard
    private let store: ClipboardHistoryStore
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var cachedChangeCount: Int

    public init(
        store: ClipboardHistoryStore,
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = ClipboardConstants.pollInterval
    ) {
        self.store = store
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.cachedChangeCount = pasteboard.changeCount
        super.init()
    }

    public func start() {
        stop()
        cachedChangeCount = pasteboard.changeCount

        timer = Timer.scheduledTimer(
            timeInterval: pollInterval,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )

        timer?.tolerance = pollInterval / 3
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func notePasteboardChangeHandled() {
        cachedChangeCount = pasteboard.changeCount
    }

    @objc
    private func timerDidFire() {
        poll()
    }

    private func poll() {
        guard pasteboard.changeCount != cachedChangeCount else {
            return
        }

        cachedChangeCount = pasteboard.changeCount

        guard let item = ClipboardItem.read(from: pasteboard) else {
            return
        }

        store.add(item)
    }
}

public final class ClipboardPaster {
    private let pasteboard: NSPasteboard
    private weak var monitor: ClipboardMonitor?

    public init(pasteboard: NSPasteboard = .general, monitor: ClipboardMonitor? = nil) {
        self.pasteboard = pasteboard
        self.monitor = monitor
    }

    public func paste(_ item: ClipboardItem) {
        copyToPasteboard(item)
        sendPasteCommand()
    }

    public func pasteText(_ text: String) {
        copyTextToPasteboard(text)
        sendPasteCommand()
    }

    public func copyToPasteboard(_ item: ClipboardItem) {
        var types: [NSPasteboard.PasteboardType] = []

        if item.rtfdData != nil {
            types.append(contentsOf: PasteboardTypes.rtfd)
        }

        if item.rtfData != nil {
            types.append(contentsOf: PasteboardTypes.rtf)
        }

        types.append(contentsOf: PasteboardTypes.string)

        pasteboard.declareTypes(types, owner: nil)

        if let rtfdData = item.rtfdData {
            PasteboardTypes.rtfd.forEach { pasteboard.setData(rtfdData, forType: $0) }
        }

        if let rtfData = item.rtfData {
            PasteboardTypes.rtf.forEach { pasteboard.setData(rtfData, forType: $0) }
        }

        PasteboardTypes.string.forEach { pasteboard.setString(item.plainText, forType: $0) }
        monitor?.notePasteboardChangeHandled()
    }

    public func copyTextToPasteboard(_ text: String) {
        pasteboard.declareTypes(PasteboardTypes.string, owner: nil)
        PasteboardTypes.string.forEach { pasteboard.setString(text, forType: $0) }
        monitor?.notePasteboardChangeHandled()
    }

    private func sendPasteCommand() {
        guard WindowActivator.requestAccessibilityIfNeeded() else {
            return
        }

        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .combinedSessionState)
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval
            )

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
            keyDown?.flags = .maskCommand

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
            keyUp?.flags = .maskCommand

            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

private enum PasteboardTypes {
    static let string: [NSPasteboard.PasteboardType] = [.string, .deprecatedString]
    static let rtf: [NSPasteboard.PasteboardType] = [.rtf, .deprecatedRTF]
    static let rtfd: [NSPasteboard.PasteboardType] = [.rtfd, .deprecatedRTFD]
}

private extension NSPasteboard.PasteboardType {
    static var deprecatedString: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(rawValue: "NSStringPboardType")
    }

    static var deprecatedRTF: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(rawValue: "NSRTFPboardType")
    }

    static var deprecatedRTFD: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(rawValue: "NSRTFDPboardType")
    }
}

private extension String {
    func shortyTruncated(maxLength: Int, symbol: String = "...") -> String {
        guard maxLength > symbol.count, count > maxLength else {
            return self
        }

        let endIndex = index(startIndex, offsetBy: maxLength - symbol.count)
        return String(self[..<endIndex]) + symbol
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
