import AppKit
import ShortyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: ShortyController

    private var statusItem: NSStatusItem?
    private var windowsWindow: NSWindow?
    private weak var windowsTextView: NSTextView?
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

        let windowsItem = NSMenuItem(
            title: "Show Windows",
            action: #selector(showWindows),
            keyEquivalent: "w"
        )
        windowsItem.target = self
        menu.addItem(windowsItem)
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
            let directoryURL = configURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directoryURL)
        }
    }

    @objc
    private func showWindows() {
        let window = windowsWindow ?? makeWindowsWindow()
        windowsWindow = window

        refreshWindowsWindow()

        if !window.isVisible {
            window.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc
    private func refreshWindowsWindow() {
        windowsTextView?.string = Self.windowListText(controller.currentWindows())
    }

    private func makeWindowsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shorty Windows"
        window.isReleasedWhenClosed = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshWindowsWindow))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyWindowsText))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 860, height: 520))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width, .height]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        windowsTextView = textView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(refreshButton)
        contentView.addSubview(copyButton)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            refreshButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            refreshButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            copyButton.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        return window
    }

    @objc
    private func copyWindowsText() {
        let text = windowsTextView?.string ?? Self.windowListText(controller.currentWindows())
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func windowListText(_ windows: [WindowDescriptor]) -> String {
        guard !windows.isEmpty else {
            return "No windows found."
        }

        return windows.enumerated().map { index, window in
            windowText(window, number: index + 1)
        }.joined(separator: "\n\n")
    }

    private static func windowText(_ window: WindowDescriptor, number: Int) -> String {
        var lines = [
            "Window \(number)",
            "Bundle ID: \(window.bundleID ?? "<no bundle id>")",
            "Window title: \(window.title.isEmpty ? "<untitled>" : window.title)",
            "App name: \(window.appName)",
            "PID: \(window.pid)",
            "App window index: \(window.appWindowIndex)",
        ]

        if let executablePath = window.executablePath {
            lines.append("Executable path: \(executablePath)")
        }

        if let document = window.document {
            lines.append("Document: \(document)")
        }

        if let url = window.url {
            lines.append("URL: \(url)")
        }

        if let identifier = window.identifier {
            lines.append("Identifier: \(identifier)")
        }

        if let role = window.role {
            lines.append("Role: \(role)")
        }

        if let subrole = window.subrole {
            lines.append("Subrole: \(subrole)")
        }

        if let minimized = window.minimized {
            lines.append("Minimized: \(minimized)")
        }

        if let position = window.position {
            lines.append("Position: x=\(Int(position.x)) y=\(Int(position.y))")
        }

        if let size = window.size {
            lines.append("Size: width=\(Int(size.width)) height=\(Int(size.height))")
        }

        return lines.joined(separator: "\n")
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
