import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Foundation

public enum WindowSwitcherMode: Sendable {
    case allWindows
    case currentApplication
}

public enum WindowSwitcherEvent: Sendable {
    case advanceAllWindows
    case advanceCurrentApplication
    case reverseActiveWindowSwitcher
    case moveFocusedWindow(WindowMoveCommand, String)
    case commandReleased
    case cancel
}

public enum WindowSwitcherDirection: Sendable {
    case forward
    case reverse
}

public enum WindowSwitcherUpdate {
    case show(WindowSwitcherSnapshot)
    case update(WindowSwitcherSnapshot)
    case hide
}

public struct WindowSwitcherSnapshot {
    public let windows: [SwitchableWindow]
    public let selectedIndex: Int
    public let mode: WindowSwitcherMode

    public var selectedWindow: SwitchableWindow? {
        guard windows.indices.contains(selectedIndex) else {
            return nil
        }

        return windows[selectedIndex]
    }
}

public final class SwitchableWindow {
    public let id: String
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    public let executablePath: String?
    public let title: String
    public let document: String?
    public let url: String?
    public let identifier: String?
    public let shortcutName: String?
    public let axWindow: AXUIElement

    init(
        id: String,
        pid: pid_t,
        bundleID: String?,
        appName: String,
        executablePath: String?,
        title: String,
        document: String?,
        url: String?,
        identifier: String?,
        shortcutName: String?,
        axWindow: AXUIElement
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.executablePath = executablePath
        self.title = title
        self.document = document
        self.url = url
        self.identifier = identifier
        self.shortcutName = shortcutName
        self.axWindow = axWindow
    }
}

private struct WindowShortcutMetadata: Sendable {
    let document: String?
    let url: String?
    let identifier: String?
}

private struct WindowMetadataRefreshRequest: @unchecked Sendable {
    let id: String
    let window: AXUIElement
}

private struct SwitchableWindowRecord {
    let id: String
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let executablePath: String?
    let title: String
    let document: String?
    let url: String?
    let identifier: String?
    let axWindow: AXUIElement

    var shortcutCandidate: WindowShortcutCandidate {
        WindowShortcutCandidate(
            id: id,
            bundleID: bundleID,
            appName: appName,
            executablePath: executablePath,
            title: title,
            document: document,
            url: url,
            identifier: identifier
        )
    }
}

public final class WindowSwitchingIndex: @unchecked Sendable {
    private static let shortcutMetadataRefreshInterval: TimeInterval = 300

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var cachedWindows: [SwitchableWindow] = []
    private var mruWindowIDs: [String] = []
    private var loadedShortcuts: [LoadedShortcut] = []
    private var exactMetadataByWindowID: [String: WindowShortcutMetadata] = [:]
    private var lastShortcutMetadataRefresh = Date.distantPast
    private var isRefreshingShortcutMetadata = false
    private var iconWarmupPIDs = Set<pid_t>()
    private var nextWindowID: UInt64 = 1
    private var refreshTimer: Timer?
    private var focusedWindowTimer: Timer?

    public init() {}

    public func start() {
        stop()
        refreshFast()
        sampleFocusedWindow()

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(refreshTimerDidFire),
            userInfo: nil,
            repeats: true
        )
        refreshTimer?.tolerance = 0.25

        focusedWindowTimer = Timer.scheduledTimer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(focusedWindowTimerDidFire),
            userInfo: nil,
            repeats: true
        )
        focusedWindowTimer?.tolerance = 0.1
    }

    public func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        focusedWindowTimer?.invalidate()
        focusedWindowTimer = nil
        isRefreshingShortcutMetadata = false
    }

    public func replaceShortcuts(_ shortcuts: [LoadedShortcut]) {
        loadedShortcuts = shortcuts
        lastShortcutMetadataRefresh = Date.distantPast
        relabelCachedWindows()
    }

    public func allWindowsInMRUOrder() -> [SwitchableWindow] {
        refreshFastIfEmpty()
        sampleFocusedWindow()
        scheduleShortcutMetadataRefreshIfNeeded()
        return ordered(cachedWindows)
    }

    public func windowsForFrontmostApplicationInMRUOrder() -> [SwitchableWindow] {
        refreshFastIfEmpty()
        sampleFocusedWindow()
        scheduleShortcutMetadataRefreshIfNeeded()

        guard let pid = frontmostApplicationPID() else {
            return []
        }

        return ordered(cachedWindows.filter { $0.pid == pid })
    }

    public func frontmostApplicationPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        guard app.processIdentifier != ownPID, !app.isTerminated, app.activationPolicy != .prohibited else {
            return nil
        }

        return app.processIdentifier
    }

    public func markFocused(_ window: SwitchableWindow) {
        promote(windowID: window.id)
    }

    @objc
    private func refreshTimerDidFire() {
        refreshFast()
    }

    @objc
    private func focusedWindowTimerDidFire() {
        sampleFocusedWindow()
    }

    private func refreshFastIfEmpty() {
        guard cachedWindows.isEmpty else {
            return
        }

        refreshFast()
    }

    private func refreshFast() {
        let windows = fastWindowSnapshot()
        cachedWindows = windows

        let liveIDs = Set(windows.map(\.id))
        mruWindowIDs.removeAll { !liveIDs.contains($0) }
        exactMetadataByWindowID = exactMetadataByWindowID.filter { liveIDs.contains($0.key) }

        for window in windows where !mruWindowIDs.contains(window.id) {
            mruWindowIDs.append(window.id)
        }
    }

    private func sampleFocusedWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return
        }

        guard app.processIdentifier != ownPID, !app.isTerminated, app.activationPolicy != .prohibited else {
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value else {
            return
        }

        let focusedWindow = value as! AXUIElement

        if let matchingWindow = cachedWindows.first(where: { CFEqual($0.axWindow, focusedWindow) }) {
            promote(windowID: matchingWindow.id)
            return
        }

        let title = Self.textAttribute(kAXTitleAttribute as CFString, on: focusedWindow) ?? ""
        guard let matchingWindow = cachedWindows.first(where: { $0.pid == app.processIdentifier && $0.title == title }) else {
            return
        }

        promote(windowID: matchingWindow.id)
    }

    private func promote(windowID: String) {
        mruWindowIDs.removeAll { $0 == windowID }
        mruWindowIDs.insert(windowID, at: 0)
    }

    private func ordered(_ windows: [SwitchableWindow]) -> [SwitchableWindow] {
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        var orderedWindows: [SwitchableWindow] = []
        var seenIDs = Set<String>()

        for id in mruWindowIDs {
            guard let window = byID[id], seenIDs.insert(id).inserted else {
                continue
            }

            orderedWindows.append(window)
        }

        for window in windows where seenIDs.insert(window.id).inserted {
            orderedWindows.append(window)
        }

        return orderedWindows
    }

    private func fastWindowSnapshot() -> [SwitchableWindow] {
        let applications = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated &&
            $0.activationPolicy != .prohibited &&
            $0.processIdentifier != ownPID
        }

        var windows: [SwitchableWindow] = []
        var candidates: [WindowShortcutCandidate] = []
        var records: [SwitchableWindowRecord] = []
        var claimedPreviousWindowIDs = Set<String>()

        for app in applications {
            warmIconCache(for: app)

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            for window in axWindows(for: appElement) {
                let title = Self.textAttribute(kAXTitleAttribute as CFString, on: window) ?? ""
                guard !Self.isFinderDesktopWindow(app: app, title: title) else {
                    continue
                }

                let id = stableWindowID(
                    for: window,
                    pid: app.processIdentifier,
                    claimedPreviousWindowIDs: &claimedPreviousWindowIDs
                )
                let metadata = exactMetadataByWindowID[id]
                let record = SwitchableWindowRecord(
                    id: id,
                    pid: app.processIdentifier,
                    bundleID: app.bundleIdentifier,
                    appName: app.localizedName ?? "<unknown>",
                    executablePath: app.executableURL?.path,
                    title: title,
                    document: metadata?.document,
                    url: metadata?.url,
                    identifier: metadata?.identifier,
                    axWindow: window
                )
                records.append(record)
                candidates.append(record.shortcutCandidate)
            }
        }

        let labels = WindowShortcutLabelMatcher.shortcutNames(for: candidates, shortcuts: loadedShortcuts)

        for record in records {
            windows.append(makeSwitchableWindow(from: record, shortcutName: labels[record.id]))
        }

        return windows
    }

    private func relabelCachedWindows() {
        guard !cachedWindows.isEmpty else {
            return
        }

        let candidates = cachedWindows.map { window in
            WindowShortcutCandidate(
                id: window.id,
                bundleID: window.bundleID,
                appName: window.appName,
                executablePath: window.executablePath,
                title: window.title,
                document: window.document,
                url: window.url,
                identifier: window.identifier
            )
        }
        let labels = WindowShortcutLabelMatcher.shortcutNames(for: candidates, shortcuts: loadedShortcuts)

        cachedWindows = cachedWindows.map { window in
            SwitchableWindow(
                id: window.id,
                pid: window.pid,
                bundleID: window.bundleID,
                appName: window.appName,
                executablePath: window.executablePath,
                title: window.title,
                document: window.document,
                url: window.url,
                identifier: window.identifier,
                shortcutName: labels[window.id],
                axWindow: window.axWindow
            )
        }
    }

    private func makeSwitchableWindow(from record: SwitchableWindowRecord, shortcutName: String?) -> SwitchableWindow {
        SwitchableWindow(
            id: record.id,
            pid: record.pid,
            bundleID: record.bundleID,
            appName: record.appName,
            executablePath: record.executablePath,
            title: record.title,
            document: record.document,
            url: record.url,
            identifier: record.identifier,
            shortcutName: shortcutName,
            axWindow: record.axWindow
        )
    }

    private func scheduleShortcutMetadataRefreshIfNeeded() {
        guard WindowShortcutLabelMatcher.needsExactMetadata(for: loadedShortcuts) else {
            return
        }

        guard !isRefreshingShortcutMetadata else {
            return
        }

        guard Date().timeIntervalSince(lastShortcutMetadataRefresh) >= Self.shortcutMetadataRefreshInterval else {
            return
        }

        let requests = cachedWindows.map { window in
            WindowMetadataRefreshRequest(id: window.id, window: window.axWindow)
        }
        guard !requests.isEmpty else {
            return
        }

        let needsDocument = loadedShortcuts.contains { $0.matcher.documentRegex != nil }
        let needsURL = loadedShortcuts.contains { $0.matcher.urlRegex != nil }
        let needsIdentifier = loadedShortcuts.contains { $0.matcher.identifierRegex != nil }

        isRefreshingShortcutMetadata = true
        lastShortcutMetadataRefresh = Date()

        DispatchQueue.global(qos: .utility).async {
            let metadata = Self.fetchShortcutMetadata(
                requests: requests,
                needsDocument: needsDocument,
                needsURL: needsURL,
                needsIdentifier: needsIdentifier
            )

            DispatchQueue.main.async { [weak self] in
                self?.finishShortcutMetadataRefresh(metadata)
            }
        }
    }

    private static func fetchShortcutMetadata(
        requests: [WindowMetadataRefreshRequest],
        needsDocument: Bool,
        needsURL: Bool,
        needsIdentifier: Bool
    ) -> [String: WindowShortcutMetadata] {
        var metadataByWindowID: [String: WindowShortcutMetadata] = [:]

        for request in requests {
            metadataByWindowID[request.id] = WindowShortcutMetadata(
                document: needsDocument ? textAttribute(kAXDocumentAttribute as CFString, on: request.window) : nil,
                url: needsURL ? textAttribute(kAXURLAttribute as CFString, on: request.window) : nil,
                identifier: needsIdentifier ? textAttribute(kAXIdentifierAttribute as CFString, on: request.window) : nil
            )
        }

        return metadataByWindowID
    }

    private func finishShortcutMetadataRefresh(_ metadata: [String: WindowShortcutMetadata]) {
        isRefreshingShortcutMetadata = false

        let liveIDs = Set(cachedWindows.map(\.id))
        for (id, windowMetadata) in metadata where liveIDs.contains(id) {
            exactMetadataByWindowID[id] = windowMetadata
        }

        relabelCachedWindows()
    }

    private func warmIconCache(for app: NSRunningApplication) {
        guard iconWarmupPIDs.insert(app.processIdentifier).inserted else {
            return
        }

        _ = app.icon
    }

    private func axWindows(for appElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        guard status == .success else {
            return []
        }

        if let windows = value as? [AXUIElement] {
            return windows
        }

        if let array = value as? [Any] {
            return array.compactMap { $0 as! AXUIElement? }
        }

        return []
    }

    private static func textAttribute(_ attribute: CFString, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard status == .success, let value else {
            return nil
        }

        if let string = value as? String {
            return string
        }

        if let url = value as? URL {
            return url.absoluteString
        }

        return nil
    }

    private func stableWindowID(
        for window: AXUIElement,
        pid: pid_t,
        claimedPreviousWindowIDs: inout Set<String>
    ) -> String {
        if let previousWindow = cachedWindows.first(where: { cachedWindow in
            cachedWindow.pid == pid &&
                !claimedPreviousWindowIDs.contains(cachedWindow.id) &&
                CFEqual(cachedWindow.axWindow, window)
        }) {
            claimedPreviousWindowIDs.insert(previousWindow.id)
            return previousWindow.id
        }

        let id = "window:\(pid):\(nextWindowID)"
        nextWindowID += 1
        return id
    }

    private static func isFinderDesktopWindow(app: NSRunningApplication, title: String) -> Bool {
        app.bundleIdentifier == "com.apple.finder" &&
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public final class WindowSwitcherSessionState {
    public private(set) var selectedIndex: Int
    public let candidateCount: Int

    public init(candidateCount: Int, initialDirection: WindowSwitcherDirection = .forward) {
        self.candidateCount = candidateCount

        if candidateCount <= 1 {
            self.selectedIndex = 0
        } else {
            self.selectedIndex = initialDirection == .forward ? 1 : candidateCount - 1
        }
    }

    public func advance(_ direction: WindowSwitcherDirection = .forward) {
        guard candidateCount > 0 else {
            selectedIndex = 0
            return
        }

        switch direction {
        case .forward:
            selectedIndex = (selectedIndex + 1) % candidateCount
        case .reverse:
            selectedIndex = (selectedIndex + candidateCount - 1) % candidateCount
        }
    }
}

public final class WindowSwitcherEventTap {
    public typealias Handler = (WindowSwitcherEvent) -> Void

    private let handler: Handler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isSwitching = false

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() -> Bool {
        stop()

        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        return true
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        isSwitching = false
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let eventTap = Unmanaged<WindowSwitcherEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        return eventTap.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            if isSwitching && !event.flags.contains(.maskCommand) {
                isSwitching = false
                handler(.commandReleased)
                return nil
            }

            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let hasCommand = flags.contains(.maskCommand)

        if let moveEvent = movementEvent(for: keyCode, flags: flags) {
            handler(moveEvent)
            return nil
        }

        if isSwitching && keyCode == UInt32(kVK_Escape) {
            isSwitching = false
            handler(.cancel)
            return nil
        }

        guard hasCommand else {
            return Unmanaged.passUnretained(event)
        }

        if keyCode == UInt32(kVK_Tab) {
            isSwitching = true
            handler(flags.contains(.maskShift) ? .reverseActiveWindowSwitcher : .advanceAllWindows)
            return nil
        }

        if keyCode == UInt32(kVK_ANSI_Grave) {
            isSwitching = true
            handler(.advanceCurrentApplication)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func movementEvent(for keyCode: UInt32, flags: CGEventFlags) -> WindowSwitcherEvent? {
        guard flags.contains(.maskControl),
              flags.contains(.maskAlternate),
              !flags.contains(.maskShift) else {
            return nil
        }

        if flags.contains(.maskCommand) {
            switch keyCode {
            case UInt32(kVK_UpArrow):
                return .moveFocusedWindow(.maximize, ReservedHotKeys.maximizeWindow.normalizedValue)
            case UInt32(kVK_LeftArrow):
                return .moveFocusedWindow(.moveToMonitor(.left), ReservedHotKeys.moveWindowToLeftMonitor.normalizedValue)
            case UInt32(kVK_RightArrow):
                return .moveFocusedWindow(.moveToMonitor(.right), ReservedHotKeys.moveWindowToRightMonitor.normalizedValue)
            default:
                return nil
            }
        }

        switch keyCode {
        case UInt32(kVK_LeftArrow):
            return .moveFocusedWindow(.cycleHalf(.left), ReservedHotKeys.moveWindowLeftHalf.normalizedValue)
        case UInt32(kVK_RightArrow):
            return .moveFocusedWindow(.cycleHalf(.right), ReservedHotKeys.moveWindowRightHalf.normalizedValue)
        default:
            return nil
        }
    }
}
