import Foundation

public final class ShortyController {
    public typealias StatusHandler = (String) -> Void

    public let options: LaunchOptions
    public var statusHandler: StatusHandler?
    public var clipboardMenuHandler: ((ClipboardMenuKind) -> Void)?
    public private(set) var loadedShortcuts: [LoadedShortcut] = []
    public private(set) var loadedSnippetGroups: [SnippetGroup] = []

    private let console: Console
    private let hotKeyCenter: HotKeyCenter
    private let windowActivator: WindowActivator
    private let clipboardHistoryStore: ClipboardHistoryStore
    private let clipboardMonitor: ClipboardMonitor
    private let clipboardPaster: ClipboardPaster
    private var configWatcher: ConfigWatcher?

    public init(
        options: LaunchOptions,
        console: Console = Console(),
        clipboardHistoryStore: ClipboardHistoryStore = ClipboardHistoryStore()
    ) throws {
        self.options = options
        self.console = console
        self.windowActivator = WindowActivator(console: console)
        self.clipboardHistoryStore = clipboardHistoryStore
        let clipboardMonitor = ClipboardMonitor(store: clipboardHistoryStore)
        self.clipboardMonitor = clipboardMonitor
        self.clipboardPaster = ClipboardPaster(monitor: clipboardMonitor)
        self.hotKeyCenter = try HotKeyCenter { [windowActivator] shortcut in
            let result = windowActivator.activate(shortcut)
            if !result.succeeded {
                console.error(result.message)
            }
        }
    }

    public func start() {
        if !WindowActivator.requestAccessibilityIfNeeded() {
            publishStatus("Accessibility permission required")
        }

        registerClipboardHotKeys()
        clipboardMonitor.start()
        reloadConfig(reason: "startup")
        startWatchingConfig()
    }

    public func stop() {
        configWatcher?.stop()
        clipboardMonitor.stop()
        hotKeyCenter.unregisterAll()
    }

    public func reloadConfig(reason: String) {
        do {
            let configuration = try ConfigurationLoader.load(from: options.configURL)
            try hotKeyCenter.replace(with: configuration.shortcuts)
            windowActivator.resetCache()
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
        clipboardPaster.paste(item)
    }

    public func pasteSnippet(_ snippet: Snippet) {
        clipboardPaster.pasteText(snippet.content)
    }

    private func registerClipboardHotKeys() {
        do {
            try hotKeyCenter.replaceActions(with: [
                HotKeyAction(hotKey: ReservedHotKeys.clipboardMenu) { [weak self] in
                    self?.clipboardMenuHandler?(.combined)
                },
                HotKeyAction(hotKey: ReservedHotKeys.snippetsMenu) { [weak self] in
                    self?.clipboardMenuHandler?(.snippets)
                },
            ])
        } catch {
            let message = "Clipboard hotkey registration failed: \(error)"
            console.error(message)
            publishStatus(message)
        }
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
}
