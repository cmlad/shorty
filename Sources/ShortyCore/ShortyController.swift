import Foundation

public final class ShortyController {
    public typealias StatusHandler = (String) -> Void

    public let options: LaunchOptions
    public var statusHandler: StatusHandler?
    public private(set) var loadedShortcuts: [LoadedShortcut] = []

    private let console: Console
    private let hotKeyCenter: HotKeyCenter
    private let windowActivator: WindowActivator
    private var configWatcher: ConfigWatcher?

    public init(options: LaunchOptions, console: Console = Console()) throws {
        self.options = options
        self.console = console
        self.windowActivator = WindowActivator(console: console)
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

        reloadConfig(reason: "startup")
        startWatchingConfig()
    }

    public func stop() {
        configWatcher?.stop()
        hotKeyCenter.unregisterAll()
    }

    public func reloadConfig(reason: String) {
        do {
            let configuration = try ConfigurationLoader.load(from: options.configURL)
            try hotKeyCenter.replace(with: configuration.shortcuts)
            windowActivator.resetCache()
            loadedShortcuts = configuration.shortcuts

            let message = "Loaded \(configuration.shortcuts.count) shortcut(s) from \(options.configURL.path)."
            console.info("\(message) Reason: \(reason).")
            publishStatus(message)
        } catch {
            let fallback = loadedShortcuts.isEmpty ? "No shortcuts active." : "Keeping \(loadedShortcuts.count) previous shortcut(s)."
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
