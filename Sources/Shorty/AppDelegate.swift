import AppKit
import Carbon
import ShortyCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    private var popupClipboardMenu: NSMenu?
    private var popupAnchorWindow: NSWindow?
    private lazy var popupModifierTracker = PopupModifierTracker { [weak self] in
        self?.pasteHighlightedClipboardItemAsPlainText() ?? false
    }
    private let clipboardPickerPanel = ClipboardPickerPanelController()
    private let commandPalettePanel = CommandPalettePanelController()
    private let windowSwitcherPanel = WindowSwitcherPanelController()
    private lazy var historyMenuIcon = Self.menuIcon(NSWorkspace.shared.icon(for: UTType.plainText))
    private lazy var snippetFolderMenuIcon: NSImage = {
        if let folderIcon = NSImage(named: NSImage.folderName) {
            return Self.menuIcon(folderIcon)
        }

        return Self.menuIcon(NSWorkspace.shared.icon(for: UTType.folder))
    }()

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
        controller.clipboardMenuHandler = { [weak self] kind in
            DispatchQueue.main.async {
                self?.handleClipboardMenuHotKey(kind)
            }
        }
        controller.textCommandHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.showCommandPalette()
            }
        }
        commandPalettePanel.pickerRequestHandler = { [weak self] kind in
            self?.showCommandInsertionPicker(kind)
        }
        controller.windowSwitcherHandler = { [weak self] update in
            DispatchQueue.main.async {
                self?.handleWindowSwitcherUpdate(update)
            }
        }
        controller.permissionRequestHandler = { [weak self] pane in
            DispatchQueue.main.async {
                self?.openPermissionSettings(pane)
            }
        }

        controller.start()
        reloadShortcutItems()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardPickerPanel.hide()
        commandPalettePanel.hide()
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

        let accessibilityItem = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

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
    private func openAccessibilitySettings() {
        openPermissionSettings(.accessibility)
    }

    private func openPermissionSettings(_ pane: ShortyPermissionPane) {
        let urlString: String
        switch pane {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func showCommandPalette() {
        commandPalettePanel.show()
    }

    private func handleClipboardMenuHotKey(_ kind: ClipboardMenuKind) {
        if commandPalettePanel.requestNestedPickerFromHotKey(kind) {
            return
        }

        showClipboardPicker(kind)
    }

    private func showCommandInsertionPicker(_ kind: ClipboardMenuKind) {
        let mode: ClipboardPickerMode
        switch kind {
        case .combined:
            mode = .all
        case .snippets:
            mode = .snippetsOnly
        }

        clipboardPickerPanel.show(
            mode: mode,
            history: controller.recentClipboardItems(),
            snippetGroups: controller.currentSnippetGroups(),
            onSelect: { [weak self] result, _ in
                self?.commandPalettePanel.insertTextFromPicker(Self.text(for: result))
            },
            onCancel: { [weak self] in
                self?.commandPalettePanel.cancelNestedPicker()
            }
        )
    }

    private static func text(for result: ClipboardPickerResult) -> String {
        switch result {
        case let .history(item):
            return item.plainText
        case let .snippet(_, snippet):
            return snippet.content
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

    private func showClipboardMenu(_ kind: ClipboardMenuKind) {
        guard popupClipboardMenu == nil else {
            return
        }

        let popupMenu = NSMenu(title: "Shorty")
        popupMenu.autoenablesItems = false
        popupMenu.delegate = self

        switch kind {
        case .combined:
            addHistoryItems(to: popupMenu)
            popupMenu.addItem(.separator())
            addSnippetItems(to: popupMenu, includeEmptyItem: true)
        case .snippets:
            addSnippetItems(to: popupMenu, includeEmptyItem: true)
        }

        popupClipboardMenu = popupMenu
        popupModifierTracker.start()
        let anchorView = makePopupAnchorView(at: NSEvent.mouseLocation)
        popupMenu.popUp(positioning: Self.firstSelectableItem(in: popupMenu), at: .zero, in: anchorView)
    }

    private func showClipboardPicker(_ kind: ClipboardMenuKind) {
        let mode: ClipboardPickerMode
        switch kind {
        case .combined:
            mode = .all
        case .snippets:
            mode = .snippetsOnly
        }

        let targetApplication = Self.currentPasteTargetApplication()
        clipboardPickerPanel.show(
            mode: mode,
            history: controller.recentClipboardItems(),
            snippetGroups: controller.currentSnippetGroups(),
            onSelect: { [weak self] result, activationMode in
                self?.pastePickerResult(
                    result,
                    activationMode: activationMode,
                    targetApplication: targetApplication
                )
            },
            onCancel: {
                Self.reactivate(targetApplication)
            }
        )
    }

    private func pastePickerResult(
        _ result: ClipboardPickerResult,
        activationMode: ClipboardPickerActivationMode,
        targetApplication: NSRunningApplication?
    ) {
        Self.reactivate(targetApplication)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else {
                return
            }

            switch result {
            case let .history(item):
                switch activationMode {
                case .joinedLines:
                    controller.pasteClipboardItemByJoiningTrimmedNonEmptyLines(item)
                case .plainText:
                    controller.pasteClipboardItemAsPlainText(item)
                case .standard:
                    controller.pasteClipboardItem(item)
                }
            case let .snippet(_, snippet):
                controller.pasteSnippet(snippet)
            }
        }
    }

    private static func currentPasteTargetApplication() -> NSRunningApplication? {
        let currentApplication = NSWorkspace.shared.frontmostApplication

        guard currentApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        return currentApplication
    }

    private static func reactivate(_ application: NSRunningApplication?) {
        application?.activate(options: [.activateIgnoringOtherApps])
    }

    private func handleWindowSwitcherUpdate(_ update: WindowSwitcherUpdate) {
        switch update {
        case let .show(snapshot):
            windowSwitcherPanel.show(snapshot)
        case let .update(snapshot):
            windowSwitcherPanel.update(snapshot)
        case .hide:
            windowSwitcherPanel.hide()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === popupClipboardMenu {
            popupAnchorWindow?.orderOut(nil)
            popupAnchorWindow = nil
            popupClipboardMenu = nil
            popupModifierTracker.stop()
        }
    }

    private func makePopupAnchorView(at point: NSPoint) -> NSView {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        let window = NSWindow(
            contentRect: NSRect(x: point.x, y: point.y, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.contentView = contentView
        window.orderFrontRegardless()
        popupAnchorWindow = window
        return contentView
    }

    private func addHistoryItems(to menu: NSMenu) {
        addDisabledHeader("History", to: menu)

        let items = controller.recentClipboardItems()
        guard !items.isEmpty else {
            let emptyItem = NSMenuItem(title: "No clipboard history", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for item in items.prefix(ClipboardConstants.maxDirectMenuItems) {
            menu.addItem(makeClipboardMenuItem(for: item))
        }

        let overflowStart = ClipboardConstants.maxDirectMenuItems
        guard items.count > overflowStart else {
            return
        }

        let maxOverflowItems = ClipboardConstants.overflowSubmenuSize * ClipboardConstants.maxOverflowSubmenus
        let overflowEnd = min(items.count, overflowStart + maxOverflowItems)
        var rangeStart = overflowStart

        while rangeStart < overflowEnd {
            let rangeEnd = min(rangeStart + ClipboardConstants.overflowSubmenuSize, overflowEnd)
            let submenu = NSMenu(title: "")
            submenu.autoenablesItems = false
            let submenuItem = NSMenuItem(title: "\(rangeStart + 1) - \(rangeEnd)", action: nil, keyEquivalent: "")
            submenuItem.image = snippetFolderMenuIcon
            submenuItem.submenu = submenu

            for item in items[rangeStart..<rangeEnd] {
                submenu.addItem(makeClipboardMenuItem(for: item))
            }

            menu.addItem(submenuItem)
            rangeStart = rangeEnd
        }
    }

    private func makeClipboardMenuItem(for item: ClipboardItem) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: item.menuTitle(),
            action: #selector(selectClipboardMenuItem(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.representedObject = ClipboardMenuPayload(item: item)
        menuItem.toolTip = Self.truncated(item.plainText, maxLength: ClipboardConstants.maxTooltipLength)
        menuItem.image = historyMenuIcon
        return menuItem
    }

    private func addSnippetItems(to menu: NSMenu, includeEmptyItem: Bool) {
        addDisabledHeader("Snippets", to: menu)

        let groups = controller.currentSnippetGroups().filter { !$0.snippets.isEmpty }

        guard !groups.isEmpty else {
            if includeEmptyItem {
                let emptyItem = NSMenuItem(title: "No snippets configured", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
            }
            return
        }

        for group in groups {
            let groupItem = NSMenuItem(
                title: Self.truncated(group.title, maxLength: ClipboardConstants.maxMenuItemTitleLength),
                action: nil,
                keyEquivalent: ""
            )
            groupItem.image = snippetFolderMenuIcon
            let submenu = NSMenu(title: group.title)
            submenu.autoenablesItems = false

            for snippet in group.snippets {
                let snippetItem = NSMenuItem(
                    title: Self.truncated(snippet.title, maxLength: ClipboardConstants.maxMenuItemTitleLength),
                    action: #selector(selectSnippetMenuItem(_:)),
                    keyEquivalent: ""
                )
                snippetItem.target = self
                snippetItem.representedObject = SnippetMenuPayload(snippet: snippet)
                snippetItem.toolTip = Self.truncated(snippet.content, maxLength: ClipboardConstants.maxTooltipLength)
                snippetItem.image = historyMenuIcon
                submenu.addItem(snippetItem)
            }

            groupItem.submenu = submenu
            menu.addItem(groupItem)
        }
    }

    private func addDisabledHeader(_ title: String, to menu: NSMenu) {
        let headerItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
    }

    private static func menuIcon(_ source: NSImage, size: CGFloat = 18) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = source.isTemplate
        return image
    }

    private static func firstSelectableItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { item in
            !item.isSeparatorItem && item.isEnabled && item.action != nil
        } ?? menu.items.first { item in
            !item.isSeparatorItem && item.isEnabled
        }
    }

    private func pasteHighlightedClipboardItemAsPlainText() -> Bool {
        guard let payload = highlightedClipboardPayload(in: popupClipboardMenu) else {
            return false
        }

        popupClipboardMenu?.cancelTracking()

        DispatchQueue.main.async { [weak self] in
            self?.controller.pasteClipboardItemAsPlainText(payload.item)
        }

        return true
    }

    private func highlightedClipboardPayload(in menu: NSMenu?) -> ClipboardMenuPayload? {
        guard let menu else {
            return nil
        }

        let highlightedSearch = highlightedClipboardPayloadSearch(in: menu)
        if highlightedSearch.foundHighlight {
            return highlightedSearch.payload
        }

        return firstClipboardPayload(in: menu)
    }

    private func highlightedClipboardPayloadSearch(
        in menu: NSMenu
    ) -> (foundHighlight: Bool, payload: ClipboardMenuPayload?) {
        if let highlightedItem = menu.highlightedItem {
            return (true, highlightedItem.representedObject as? ClipboardMenuPayload)
        }

        for item in menu.items {
            guard let submenu = item.submenu else {
                continue
            }

            let result = highlightedClipboardPayloadSearch(in: submenu)
            if result.foundHighlight {
                return result
            }
        }

        return (false, nil)
    }

    private func firstClipboardPayload(in menu: NSMenu) -> ClipboardMenuPayload? {
        for item in menu.items {
            if let payload = item.representedObject as? ClipboardMenuPayload {
                return payload
            }

            if let submenu = item.submenu, let payload = firstClipboardPayload(in: submenu) {
                return payload
            }
        }

        return nil
    }

    @objc
    private func selectClipboardMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ClipboardMenuPayload else {
            NSSound.beep()
            return
        }

        if popupModifierTracker.shouldPasteAsPlainText(triggeringEvent: NSApp.currentEvent) {
            controller.pasteClipboardItemAsPlainText(payload.item)
        } else {
            controller.pasteClipboardItem(payload.item)
        }
    }

    @objc
    private func selectSnippetMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SnippetMenuPayload else {
            NSSound.beep()
            return
        }

        controller.pasteSnippet(payload.snippet)
    }

    private static func truncated(_ value: String, maxLength: Int) -> String {
        let symbol = "..."
        guard maxLength > symbol.count, value.count > maxLength else {
            return value
        }

        let endIndex = value.index(value.startIndex, offsetBy: maxLength - symbol.count)
        return String(value[..<endIndex]) + symbol
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

private final class ClipboardMenuPayload: NSObject {
    let item: ClipboardItem

    init(item: ClipboardItem) {
        self.item = item
    }
}

private final class PopupModifierTracker {
    private let commandReturnHandler: () -> Bool
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var commandIsDown = false
    private var plainTextPasteIntentDeadline: Date?

    init(commandReturnHandler: @escaping () -> Bool) {
        self.commandReturnHandler = commandReturnHandler
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        commandIsDown = false
        plainTextPasteIntentDeadline = nil

        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
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
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        commandIsDown = false
        plainTextPasteIntentDeadline = nil
    }

    func shouldPasteAsPlainText(triggeringEvent: NSEvent?) -> Bool {
        if let deadline = plainTextPasteIntentDeadline {
            plainTextPasteIntentDeadline = nil
            if deadline >= Date() {
                return true
            }
        }

        guard let triggeringEvent else {
            return false
        }

        return Self.isCommandMenuSelection(triggeringEvent)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let tracker = Unmanaged<PopupModifierTracker>.fromOpaque(userInfo).takeUnretainedValue()
        return tracker.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let eventCommandIsDown = event.flags.contains(.maskCommand) || Self.isCommandPressed()

        switch type {
        case .flagsChanged:
            commandIsDown = eventCommandIsDown
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if eventCommandIsDown {
                plainTextPasteIntentDeadline = Date().addingTimeInterval(1.0)
            }
        case .keyDown:
            let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
            if Self.isReturnKey(keyCode), eventCommandIsDown || commandIsDown {
                plainTextPasteIntentDeadline = Date().addingTimeInterval(1.0)
                if handleCommandReturn() {
                    return nil
                }
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleCommandReturn() -> Bool {
        guard Thread.isMainThread else {
            return false
        }

        return commandReturnHandler()
    }

    private static func isCommandPressed() -> Bool {
        let appKitCommandIsDown = NSEvent.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.command)
        let coreGraphicsCommandIsDown = CGEventSource
            .flagsState(.combinedSessionState)
            .contains(.maskCommand)
        let physicalCommandIsDown =
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Command)) ||
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightCommand))

        return appKitCommandIsDown || coreGraphicsCommandIsDown || physicalCommandIsDown
    }

    private static func isCommandMenuSelection(_ event: NSEvent) -> Bool {
        guard event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.command)
        else {
            return false
        }

        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            return true
        case .keyDown, .keyUp:
            return isReturnKey(UInt32(event.keyCode))
        default:
            return false
        }
    }

    private static func isReturnKey(_ keyCode: UInt32) -> Bool {
        keyCode == UInt32(kVK_Return) || keyCode == UInt32(kVK_ANSI_KeypadEnter)
    }
}

private final class SnippetMenuPayload: NSObject {
    let snippet: Snippet

    init(snippet: Snippet) {
        self.snippet = snippet
    }
}
