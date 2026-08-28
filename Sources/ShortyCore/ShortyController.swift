import Foundation

public enum ShortyPermissionPane: Hashable, Sendable {
    case accessibility
}

public final class ShortyController {
    public typealias StatusHandler = (String) -> Void

    public let options: LaunchOptions
    public var statusHandler: StatusHandler?
    public var clipboardMenuHandler: ((ClipboardMenuKind) -> Void)?
    public var textCommandHandler: (() -> Void)?
    public var windowSwitcherHandler: ((WindowSwitcherUpdate) -> Void)?
    public var permissionRequestHandler: ((ShortyPermissionPane) -> Void)?
    public private(set) var loadedShortcuts: [LoadedShortcut] = []
    public private(set) var loadedSnippetGroups: [SnippetGroup] = []

    private let console: Console
    private let hotKeyCenter: HotKeyCenter
    private let windowActivator: WindowActivator
    private let windowMover: WindowMover
    private let clipboardHistoryStore: ClipboardHistoryStore
    private let clipboardMonitor: ClipboardMonitor
    private let clipboardPaster: ClipboardPaster
    private let windowSwitchingIndex: WindowSwitchingIndex
    private lazy var windowSwitcherEventTap = WindowSwitcherEventTap { [weak self] event in
        self?.handleWindowSwitcherEvent(event)
    }
    private var configWatcher: ConfigWatcher?
    private var activeWindowSwitcherMode: WindowSwitcherMode?
    private var activeWindowSwitcherWindows: [SwitchableWindow] = []
    private var activeWindowSwitcherSelection: WindowSwitcherSessionState?
    private var requestedPermissionPanes: Set<ShortyPermissionPane> = []
    private var lastWindowMoveAction: (hotKey: String, date: Date)?

    public init(
        options: LaunchOptions,
        console: Console = Console(),
        clipboardHistoryStore: ClipboardHistoryStore = ClipboardHistoryStore()
    ) throws {
        self.options = options
        self.console = console
        self.windowActivator = WindowActivator(console: console)
        self.windowMover = WindowMover(console: console)
        self.clipboardHistoryStore = clipboardHistoryStore
        let clipboardMonitor = ClipboardMonitor(store: clipboardHistoryStore)
        self.clipboardMonitor = clipboardMonitor
        self.clipboardPaster = ClipboardPaster(monitor: clipboardMonitor)
        self.windowSwitchingIndex = WindowSwitchingIndex()
        self.hotKeyCenter = try HotKeyCenter { [windowActivator] shortcut in
            let result = windowActivator.activate(shortcut)
            if !result.succeeded {
                console.error(result.message)
            }
        }
    }

    public func start() {
        console.info("Starting Shorty with config \(options.configURL.path).")

        if !WindowActivator.requestAccessibilityIfNeeded() {
            publishStatus("Accessibility permission required")
            requestPermissionPane(.accessibility)
        }

        registerReservedHotKeys()
        clipboardMonitor.start()
        windowSwitchingIndex.start()
        startWindowSwitcherEventTap()
        reloadConfig(reason: "startup")
        startWatchingConfig()
    }

    public func stop() {
        configWatcher?.stop()
        clipboardMonitor.stop()
        windowSwitchingIndex.stop()
        windowSwitcherEventTap.stop()
        hotKeyCenter.unregisterAll()
    }

    public func reloadConfig(reason: String) {
        do {
            let configuration = try ConfigurationLoader.load(from: options.configURL)
            try hotKeyCenter.replace(with: configuration.shortcuts)
            windowActivator.resetCache()
            windowSwitchingIndex.replaceShortcuts(configuration.shortcuts)
            loadedShortcuts = configuration.shortcuts
            loadedSnippetGroups = configuration.snippetGroups

            let snippetCount = configuration.snippetGroups.reduce(0) { $0 + $1.snippets.count }
            let message = "Loaded \(configuration.shortcuts.count) shortcut(s) and \(snippetCount) snippet(s) from \(options.configURL.path)."
            console.info("\(message) Reason: \(reason).")
            publishStatus(message)
        } catch {
            let snippetCount = loadedSnippetGroups.reduce(0) { $0 + $1.snippets.count }
            let fallback = loadedShortcuts.isEmpty && snippetCount == 0
                ? "No shortcuts or snippets active."
                : "Keeping \(loadedShortcuts.count) previous shortcut(s) and \(snippetCount) previous snippet(s)."
            let message = "Config reload failed: \(error). \(fallback)"
            console.error(message)
            publishStatus(message)
        }
    }

    public func shortcutSummaries() -> [String] {
        loadedShortcuts.map { shortcut in
            "\(shortcut.hotKey.normalizedValue) -> \(shortcut.id)"
        }
    }

    public func currentWindows() -> [WindowDescriptor] {
        windowActivator.listWindows()
    }

    public func recentClipboardItems() -> [ClipboardItem] {
        clipboardHistoryStore.recentItems()
    }

    public func currentSnippetGroups() -> [SnippetGroup] {
        loadedSnippetGroups
    }

    public func pasteClipboardItem(_ item: ClipboardItem) {
        console.info("Pasting clipboard history item with rich representations.")
        clipboardHistoryStore.add(item)
        clipboardPaster.paste(item)
    }

    public func pasteClipboardItemAsPlainText(_ item: ClipboardItem) {
        console.info("Pasting clipboard history item as plain text.")
        clipboardHistoryStore.add(item)
        clipboardPaster.pasteText(item.plainText)
    }

    public func pasteClipboardItemByJoiningTrimmedNonEmptyLines(_ item: ClipboardItem) {
        console.info("Pasting clipboard history item with trimmed lines joined.")
        let text = clipboardHistoryStore.addJoinedTrimmedNonEmptyLines(from: item)
        clipboardPaster.pasteText(text)
    }

    public func pasteSnippet(_ snippet: Snippet) {
        clipboardHistoryStore.addPlainText(snippet.content)
        clipboardPaster.pasteText(snippet.content)
    }

    private func registerReservedHotKeys() {
        do {
            try hotKeyCenter.replaceActions(with: [
                HotKeyAction(hotKey: ReservedHotKeys.clipboardMenu) { [weak self] in
                    self?.console.info("Reserved hotkey `\(ReservedHotKeys.clipboardMenu.normalizedValue)` triggered clipboard menu.")
                    self?.clipboardMenuHandler?(.combined)
                },
                HotKeyAction(hotKey: ReservedHotKeys.snippetsMenu) { [weak self] in
                    self?.console.info("Reserved hotkey `\(ReservedHotKeys.snippetsMenu.normalizedValue)` triggered snippets menu.")
                    self?.clipboardMenuHandler?(.snippets)
                },
                HotKeyAction(hotKey: ReservedHotKeys.textCommand) { [weak self] in
                    self?.console.info("Reserved hotkey `\(ReservedHotKeys.textCommand.normalizedValue)` triggered text command palette.")
                    self?.textCommandHandler?()
                },
                HotKeyAction(hotKey: ReservedHotKeys.moveWindowLeftHalf) { [weak self] in
                    self?.moveFocusedWindow(.cycleHalf(.left), hotKey: ReservedHotKeys.moveWindowLeftHalf.normalizedValue)
                },
                HotKeyAction(hotKey: ReservedHotKeys.moveWindowRightHalf) { [weak self] in
                    self?.moveFocusedWindow(.cycleHalf(.right), hotKey: ReservedHotKeys.moveWindowRightHalf.normalizedValue)
                },
                HotKeyAction(hotKey: ReservedHotKeys.maximizeWindow) { [weak self] in
                    self?.moveFocusedWindow(.maximize, hotKey: ReservedHotKeys.maximizeWindow.normalizedValue)
                },
                HotKeyAction(hotKey: ReservedHotKeys.moveWindowToLeftMonitor) { [weak self] in
                    self?.moveFocusedWindow(.moveToMonitor(.left), hotKey: ReservedHotKeys.moveWindowToLeftMonitor.normalizedValue)
                },
                HotKeyAction(hotKey: ReservedHotKeys.moveWindowToRightMonitor) { [weak self] in
                    self?.moveFocusedWindow(.moveToMonitor(.right), hotKey: ReservedHotKeys.moveWindowToRightMonitor.normalizedValue)
                },
            ])
            console.info("Registered Carbon reserved hotkeys: \(Self.carbonReservedHotKeySummary()).")
        } catch {
            let message = "Reserved hotkey registration failed: \(error)"
            console.error(message)
            publishStatus(message)
        }
    }

    private func startWindowSwitcherEventTap() {
        guard windowSwitcherEventTap.start() else {
            let message = "Window switcher unavailable. Allow Accessibility for Shorty, then restart."
            console.error(message)
            publishStatus(message)
            requestPermissionPane(.accessibility)
            return
        }

        console.info("Window switcher event tap installed.")
    }

    private func handleWindowSwitcherEvent(_ event: WindowSwitcherEvent) {
        switch event {
        case .advanceAllWindows:
            advanceWindowSwitcher(mode: .allWindows, direction: .forward)
        case .advanceCurrentApplication:
            advanceWindowSwitcher(mode: .currentApplication, direction: .forward)
        case .reverseActiveWindowSwitcher:
            advanceWindowSwitcher(mode: activeWindowSwitcherMode ?? .allWindows, direction: .reverse)
        case .reverseCurrentApplication:
            advanceWindowSwitcher(mode: .currentApplication, direction: .reverse)
        case let .moveFocusedWindow(command, hotKey):
            moveFocusedWindow(command, hotKey: hotKey)
        case .commandReleased:
            commitWindowSwitcher()
        case .cancel:
            cancelWindowSwitcher()
        }
    }

    private func moveFocusedWindow(_ command: WindowMoveCommand, hotKey: String) {
        let now = Date()
        if let lastWindowMoveAction,
           lastWindowMoveAction.hotKey == hotKey,
           now.timeIntervalSince(lastWindowMoveAction.date) < 0.08 {
            return
        }

        lastWindowMoveAction = (hotKey, now)
        console.info("Reserved hotkey `\(hotKey)` triggered window move action.")
        let result = windowMover.moveFocusedWindow(command)
        publishStatus(result.message)
    }

    private func advanceWindowSwitcher(mode: WindowSwitcherMode, direction: WindowSwitcherDirection) {
        if activeWindowSwitcherMode != mode || activeWindowSwitcherSelection == nil {
            startWindowSwitcher(mode: mode, initialDirection: direction)
            return
        }

        activeWindowSwitcherSelection?.advance(direction)
        publishWindowSwitcherUpdate(.update)
    }

    private func startWindowSwitcher(mode: WindowSwitcherMode, initialDirection: WindowSwitcherDirection) {
        let windows: [SwitchableWindow]

        switch mode {
        case .allWindows:
            windows = windowSwitchingIndex.allWindowsInMRUOrder()
        case .currentApplication:
            windows = windowSwitchingIndex.windowsForFrontmostApplicationInMRUOrder()
        }

        guard !windows.isEmpty else {
            cancelWindowSwitcher()
            return
        }

        activeWindowSwitcherMode = mode
        activeWindowSwitcherWindows = windows
        activeWindowSwitcherSelection = WindowSwitcherSessionState(
            candidateCount: windows.count,
            initialDirection: initialDirection
        )
        publishWindowSwitcherUpdate(.show)
    }

    private func commitWindowSwitcher() {
        defer {
            resetWindowSwitcher()
            windowSwitcherHandler?(.hide)
        }

        guard let selectedWindow = currentWindowSwitcherSnapshot()?.selectedWindow else {
            return
        }

        windowSwitchingIndex.markFocused(selectedWindow)
        let result = windowActivator.activate(selectedWindow)
        if !result.succeeded {
            console.error(result.message)
        }
    }

    private func cancelWindowSwitcher() {
        resetWindowSwitcher()
        windowSwitcherHandler?(.hide)
    }

    private enum WindowSwitcherPublishKind {
        case show
        case update
    }

    private func publishWindowSwitcherUpdate(_ kind: WindowSwitcherPublishKind) {
        guard let snapshot = currentWindowSwitcherSnapshot() else {
            return
        }

        switch kind {
        case .show:
            windowSwitcherHandler?(.show(snapshot))
        case .update:
            windowSwitcherHandler?(.update(snapshot))
        }
    }

    private func currentWindowSwitcherSnapshot() -> WindowSwitcherSnapshot? {
        guard let mode = activeWindowSwitcherMode, let selection = activeWindowSwitcherSelection else {
            return nil
        }

        return WindowSwitcherSnapshot(
            windows: activeWindowSwitcherWindows,
            selectedIndex: selection.selectedIndex,
            mode: mode
        )
    }

    private func resetWindowSwitcher() {
        activeWindowSwitcherMode = nil
        activeWindowSwitcherWindows = []
        activeWindowSwitcherSelection = nil
    }

    private func startWatchingConfig() {
        configWatcher?.stop()
        configWatcher = ConfigWatcher(url: options.configURL) { [weak self] in
            self?.reloadConfig(reason: "config file changed")
        }
        configWatcher?.start()
    }

    private func publishStatus(_ message: String) {
        statusHandler?(message)
    }

    private func requestPermissionPane(_ pane: ShortyPermissionPane) {
        guard requestedPermissionPanes.insert(pane).inserted else {
            return
        }

        permissionRequestHandler?(pane)
    }

    private static func carbonReservedHotKeySummary() -> String {
        [
            ReservedHotKeys.clipboardMenu,
            ReservedHotKeys.snippetsMenu,
            ReservedHotKeys.textCommand,
            ReservedHotKeys.moveWindowLeftHalf,
            ReservedHotKeys.moveWindowRightHalf,
            ReservedHotKeys.maximizeWindow,
            ReservedHotKeys.moveWindowToLeftMonitor,
            ReservedHotKeys.moveWindowToRightMonitor,
        ]
        .map { hotKey in
            let description = ReservedHotKeys.descriptionsByNormalizedValue[hotKey.normalizedValue] ?? "reserved action"
            return "\(hotKey.normalizedValue) (\(description))"
        }
        .joined(separator: ", ")
    }
}
