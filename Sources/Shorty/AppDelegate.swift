import AppKit
import ShortyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: ShortyController

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let stateMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let pathMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let shortcutsHeaderItem = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
    private let emptyShortcutsItem = NSMenuItem(title: "No shortcuts loaded", action: nil, keyEquivalent: "")
    private var dynamicShortcutItems: [NSMenuItem] = []

    init(controller: ShortyController) {
        self.controller = controller
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        controller.statusHandler = { [weak self] message in
            DispatchQueue.main.async {
                self?.updateStatus(message)
                self?.reloadShortcutItems()
            }
        }

        controller.start()
        reloadShortcutItems()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.title = "S"
            button.toolTip = "Shorty"
        }

        stateMenuItem.isEnabled = false
        pathMenuItem.isEnabled = false
        pathMenuItem.title = controller.options.configURL.path
        shortcutsHeaderItem.isEnabled = false
        emptyShortcutsItem.isEnabled = false

        menu.addItem(stateMenuItem)
        menu.addItem(pathMenuItem)
        menu.addItem(.separator())
        menu.addItem(shortcutsHeaderItem)
        menu.addItem(emptyShortcutsItem)
        menu.addItem(.separator())

        let reloadItem = NSMenuItem(
            title: "Reload Config",
            action: #selector(reloadConfig),
            keyEquivalent: "r"
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        let revealItem = NSMenuItem(
            title: "Reveal Config",
            action: #selector(revealConfig),
            keyEquivalent: ""
        )
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateStatus(_ message: String) {
        stateMenuItem.title = message
        statusItem?.button?.toolTip = message
    }

    private func reloadShortcutItems() {
        for item in dynamicShortcutItems {
            menu.removeItem(item)
        }

        dynamicShortcutItems.removeAll()

        let summaries = controller.shortcutSummaries()

        if summaries.isEmpty {
            emptyShortcutsItem.isHidden = false
            return
        }

        emptyShortcutsItem.isHidden = true

        guard let insertionIndex = menu.items.firstIndex(of: emptyShortcutsItem) else {
            return
        }

        for (offset, summary) in summaries.enumerated() {
            let item = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
            item.isEnabled = false
            dynamicShortcutItems.append(item)
            menu.insertItem(item, at: insertionIndex + offset)
        }
    }

    @objc
    private func reloadConfig() {
        controller.reloadConfig(reason: "manual reload")
    }

    @objc
    private func revealConfig() {
        let configURL = controller.options.configURL
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: configURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
        } else {
            NSWorkspace.shared.open(configURL.deletingLastPathComponent())
        }
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
