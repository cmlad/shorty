import AppKit
import ShortyCore
import UniformTypeIdentifiers

@MainActor
final class WindowSwitcherPanelController {
    private var panels: [WindowSwitcherPanel] = []
    private var screensSignature = ""

    func show(_ snapshot: WindowSwitcherSnapshot) {
        syncPanels()
        panels.forEach { $0.show(snapshot) }
    }

    func update(_ snapshot: WindowSwitcherSnapshot) {
        if panels.isEmpty {
            syncPanels()
        }

        panels.forEach { $0.update(snapshot) }
    }

    func hide() {
        panels.forEach { $0.hide() }
    }

    private func syncPanels() {
        let screens = NSScreen.screens
        let signature = screens
            .map { "\(NSStringFromRect($0.frame)):\(NSStringFromRect($0.visibleFrame))" }
            .joined(separator: "|")

        guard panels.isEmpty || signature != screensSignature else {
            return
        }

        panels.forEach { $0.hide() }
        panels = screens.map { WindowSwitcherPanel(screen: $0) }
        screensSignature = signature
    }
}

@MainActor
private final class WindowSwitcherPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private enum Column {
        static let appName = NSUserInterfaceItemIdentifier("appName")
        static let icon = NSUserInterfaceItemIdentifier("icon")
        static let title = NSUserInterfaceItemIdentifier("title")
    }

    private enum Metrics {
        static let panelWidth: CGFloat = 760
        static let appNameColumnWidth: CGFloat = 170
        static let iconColumnWidth: CGFloat = 34
        static let titleColumnWidth: CGFloat = 536
        static let rowHeight: CGFloat = 30
        static let maxVisibleRows = 25
        static let horizontalPadding: CGFloat = 8
        static let topPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 12
        static let viewportSlack: CGFloat = 2
        static let bottomMargin: CGFloat = 20
        static let topOffsetRatio: CGFloat = 0.20
    }

    private let screen: NSScreen
    private let panel: NSPanel
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var windows: [SwitchableWindow] = []
    private var selectedIndex = 0
    private var iconCache: [pid_t: NSImage] = [:]

    init(screen: NSScreen) {
        self.screen = screen
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        configureTable()
    }

    func show(_ snapshot: WindowSwitcherSnapshot) {
        apply(snapshot, resetScroll: true)
        positionPanel()
        panel.orderFrontRegardless()
    }

    func update(_ snapshot: WindowSwitcherSnapshot) {
        if canUpdateSelectionOnly(for: snapshot) {
            updateSelection(to: snapshot.selectedIndex)
            return
        }

        apply(snapshot, resetScroll: false)
        positionPanel()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        windows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Metrics.rowHeight
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard windows.indices.contains(row), let tableColumn else {
            return nil
        }

        let window = windows[row]

        switch tableColumn.identifier {
        case Column.appName:
            return makeTextCell(text: window.appName, alignment: .right, color: .secondaryLabelColor)
        case Column.icon:
            return makeIconCell(icon(for: window))
        case Column.title:
            return makeTitleCell(for: window)
        default:
            return nil
        }
    }

    private func configurePanel() {
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
    }

    private func configureTable() {
        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none

        let appNameColumn = NSTableColumn(identifier: Column.appName)
        appNameColumn.width = Metrics.appNameColumnWidth
        appNameColumn.minWidth = Metrics.appNameColumnWidth
        appNameColumn.maxWidth = Metrics.appNameColumnWidth

        let iconColumn = NSTableColumn(identifier: Column.icon)
        iconColumn.width = Metrics.iconColumnWidth
        iconColumn.minWidth = Metrics.iconColumnWidth
        iconColumn.maxWidth = Metrics.iconColumnWidth

        let titleColumn = NSTableColumn(identifier: Column.title)
        titleColumn.width = Metrics.titleColumnWidth
        titleColumn.minWidth = Metrics.titleColumnWidth
        titleColumn.maxWidth = Metrics.titleColumnWidth

        tableView.addTableColumn(appNameColumn)
        tableView.addTableColumn(iconColumn)
        tableView.addTableColumn(titleColumn)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        panel.contentView = container

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.topPadding),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.horizontalPadding),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.horizontalPadding),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Metrics.bottomPadding),
        ])
    }

    private func apply(_ snapshot: WindowSwitcherSnapshot, resetScroll: Bool) {
        windows = snapshot.windows
        selectedIndex = snapshot.selectedIndex

        let visibleRows = visibleRowCount()
        let contentHeight = CGFloat(visibleRows) * Metrics.rowHeight + Metrics.viewportSlack
        let panelHeight = contentHeight + Metrics.topPadding + Metrics.bottomPadding
        let needsScroller = windows.count > visibleRows

        scrollView.hasVerticalScroller = needsScroller
        panel.setContentSize(NSSize(width: Metrics.panelWidth, height: panelHeight))
        panel.contentView?.layoutSubtreeIfNeeded()

        tableView.reloadData()
        tableView.setFrameSize(
            NSSize(
                width: Metrics.appNameColumnWidth + Metrics.iconColumnWidth + Metrics.titleColumnWidth,
                height: max(CGFloat(windows.count) * Metrics.rowHeight + Metrics.viewportSlack, contentHeight)
            )
        )

        if resetScroll || !needsScroller {
            resetScrollPosition()
        }

        if windows.indices.contains(selectedIndex) {
            selectRow(selectedIndex, scrollIfNeeded: needsScroller)
        }

        if !needsScroller {
            resetScrollPosition()
        }
    }

    private func resetScrollPosition() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func canUpdateSelectionOnly(for snapshot: WindowSwitcherSnapshot) -> Bool {
        guard windows.count == snapshot.windows.count else {
            return false
        }

        return zip(windows, snapshot.windows).allSatisfy { current, next in
            current.id == next.id
        }
    }

    private func updateSelection(to index: Int) {
        selectedIndex = index
        guard windows.indices.contains(selectedIndex) else {
            return
        }

        selectRow(selectedIndex, scrollIfNeeded: windows.count > visibleRowCount())
    }

    private func selectRow(_ row: Int, scrollIfNeeded: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)

            if scrollIfNeeded {
                tableView.scrollRowToVisible(row)
            }
        }
    }

    private func visibleRowCount() -> Int {
        let availableHeight = screen.visibleFrame.height * (1 - Metrics.topOffsetRatio) - Metrics.bottomMargin
        let availableRows = Int((availableHeight - Metrics.topPadding - Metrics.bottomPadding - Metrics.viewportSlack) / Metrics.rowHeight)
        let maxRows = max(1, min(Metrics.maxVisibleRows, availableRows))
        return max(1, min(windows.count, maxRows))
    }

    private func positionPanel() {
        let visibleFrame = screen.visibleFrame
        let frame = panel.frame
        let topY = visibleFrame.maxY - visibleFrame.height * Metrics.topOffsetRatio

        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: max(visibleFrame.minY + Metrics.bottomMargin, topY - frame.height)
            )
        )
    }

    private func makeTitleCell(for window: SwitchableWindow) -> NSView {
        let cell = NSTableCellView()
        let textField = NSTextField(labelWithString: "")
        textField.alignment = .left
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let text = NSMutableAttributedString()
        if let shortcutName = window.shortcutName, !shortcutName.isEmpty {
            text.append(
                NSAttributedString(
                    string: shortcutName,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: NSColor.white,
                        .paragraphStyle: paragraphStyle,
                    ]
                )
            )
            text.append(
                NSAttributedString(
                    string: " • ",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )
            )
        }

        text.append(
            NSAttributedString(
                string: window.title.isEmpty ? "<untitled>" : window.title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle,
                ]
            )
        )
        textField.attributedStringValue = text

        cell.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Metrics.horizontalPadding),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Metrics.horizontalPadding),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    private func makeTextCell(text: String, alignment: NSTextAlignment, color: NSColor) -> NSView {
        let cell = NSTableCellView()
        let textField = NSTextField(labelWithString: text)
        textField.alignment = alignment
        textField.textColor = color
        textField.lineBreakMode = .byTruncatingTail
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Metrics.horizontalPadding),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Metrics.horizontalPadding),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    private func makeIconCell(_ image: NSImage) -> NSView {
        let cell = NSTableCellView()
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            imageView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    private func icon(for window: SwitchableWindow) -> NSImage {
        if let cached = iconCache[window.pid] {
            return cached
        }

        let source = NSRunningApplication(processIdentifier: window.pid)?.icon
            ?? NSWorkspace.shared.icon(for: .application)
        let icon = Self.menuIcon(source)
        iconCache[window.pid] = icon
        return icon
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
}
