import AppKit
import Carbon
import ShortyCore
import UniformTypeIdentifiers

@MainActor
final class ClipboardPickerPanelController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum Metrics {
        static let panelWidth: CGFloat = 520
        static let maxVisibleRows = 35
        static let rowHeight: CGFloat = 24
        static let headerRowHeight: CGFloat = 18
        static let topPadding: CGFloat = 8
        static let searchHorizontalPadding: CGFloat = 8
        static let searchHeight: CGFloat = 22
        static let searchBottomSpacing: CGFloat = 6
        static let bottomPadding: CGFloat = 4
        static let nonOverflowSlack: CGFloat = 12
        static let topOffsetRatio: CGFloat = 0.20
        static let bottomMargin: CGFloat = 20
        static let iconSize: CGFloat = 16
        static let iconLeading: CGFloat = 0
        static let textSpacing: CGFloat = 4
        static let trailingPadding: CGFloat = 30
        static let headerLeading: CGFloat = -8
        static let disclosureSize: CGFloat = 12
        static let disclosureTrailing: CGFloat = 24
        static let disclosureSpacing: CGFloat = 8
    }

    private struct HandledKeyEvent {
        let keyCode: UInt16
        let timestamp: TimeInterval

        init(_ event: NSEvent) {
            keyCode = event.keyCode
            timestamp = event.timestamp
        }

        func matches(_ event: NSEvent) -> Bool {
            keyCode == event.keyCode && timestamp == event.timestamp
        }
    }

    private let panel: ClipboardPickerPanelWindow
    private let searchField = ClipboardPickerSearchField(frame: .zero)
    private let tableView = ClipboardPickerTableView()
    private let scrollView = ClipboardPickerScrollView()
    private var mode: ClipboardPickerMode = .all
    private var history: [ClipboardItem] = []
    private var snippetGroups: [SnippetGroup] = []
    private var currentFolder: ClipboardPickerFolder?
    private var query = ""
    private var entries: [ClipboardPickerEntry] = []
    private var selectedIndex = -1
    private var onSelect: ((ClipboardPickerResult, ClipboardPickerActivationMode) -> Void)?
    private var onCancel: (() -> Void)?
    private var keyMonitor: Any?
    private var locallyHandledKeyEvent: HandledKeyEvent?
    private lazy var documentIcon = Self.icon(NSWorkspace.shared.icon(for: UTType.plainText))
    private lazy var folderIcon: NSImage = {
        if let image = NSImage(named: NSImage.folderName) {
            return Self.icon(image)
        }

        return Self.icon(NSWorkspace.shared.icon(for: UTType.folder))
    }()

    override init() {
        panel = ClipboardPickerPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        configureSearchField()
        configureTable()
    }

    func show(
        mode: ClipboardPickerMode,
        history: [ClipboardItem],
        snippetGroups: [SnippetGroup],
        onSelect: @escaping (ClipboardPickerResult, ClipboardPickerActivationMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.history = history
        self.snippetGroups = snippetGroups
        self.currentFolder = nil
        self.query = ""
        self.onSelect = onSelect
        self.onCancel = onCancel
        searchField.stringValue = ""
        searchField.placeholderString = mode == .snippetsOnly ? "Search snippets" : "Search"

        startKeyMonitor()
        applyFilter(resetSelection: true)
        positionPanel()

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        stopKeyMonitor()
        panel.orderOut(nil)
        onSelect = nil
        onCancel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible {
            hide()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard entries.indices.contains(row) else {
            return nil
        }

        return makeCell(for: entries[row])
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard entries.indices.contains(row) else {
            return Metrics.rowHeight
        }

        return height(for: entries[row])
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        entries.indices.contains(row) && entries[row].isSelectable
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ClipboardPickerRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        if entries.indices.contains(selectedRow), entries[selectedRow].isSelectable {
            selectedIndex = selectedRow
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
        panel.delegate = self
        panel.keyEventHandler = { [weak self] event in
            self?.handlePanelKeyEvent(event) ?? false
        }

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        panel.contentView = container

        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.topPadding),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.searchHorizontalPadding),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.searchHorizontalPadding),
            searchField.heightAnchor.constraint(equalToConstant: Metrics.searchHeight),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Metrics.searchBottomSpacing),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Metrics.bottomPadding),
        ])
    }

    private func configureSearchField() {
        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.focusRingType = .none
        searchField.keyHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }

    private func configureTable() {
        scrollView.contentView = ClipboardPickerClipView()

        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.autoresizingMask = [.width]
        tableView.keyHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        tableView.mouseSelectionHandler = { [weak self] row, activationMode in
            self?.activate(row: row, activationMode: activationMode)
        }
        tableView.hoverSelectionHandler = { [weak self] row in
            self?.selectHoveredRow(row)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        column.width = Metrics.panelWidth
        column.minWidth = 0
        column.maxWidth = Metrics.panelWidth
        column.resizingMask = []
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true
    }

    func controlTextDidChange(_ notification: Notification) {
        query = searchField.stringValue
        applyFilter(resetSelection: true)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            if consumeLocallyHandledCurrentEvent() {
                return true
            }

            moveSelection(by: -1)
            return true

        case #selector(NSResponder.moveDown(_:)):
            if consumeLocallyHandledCurrentEvent() {
                return true
            }

            moveSelection(by: 1)
            return true

        case #selector(NSResponder.moveLeft(_:)):
            if consumeLocallyHandledCurrentEvent() {
                return true
            }

            return leaveFolderIfNeeded()

        case #selector(NSResponder.moveRight(_:)):
            if consumeLocallyHandledCurrentEvent() {
                return true
            }

            return enterSelectedFolderIfNeeded()

        case #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            if consumeLocallyHandledCurrentEvent() {
                return true
            }

            activateSelected(activationMode: Self.activationMode())
            return true

        case #selector(NSResponder.cancelOperation(_:)):
            if consumeLocallyHandledCurrentEvent() {
                return true
            }

            if leaveFolderIfNeeded() {
                return true
            }
            cancel()
            return true

        default:
            return false
        }
    }

    private func applyFilter(resetSelection: Bool, preferredEntryID: String? = nil) {
        if let currentFolder {
            entries = ClipboardPickerSearch.folderEntries(in: currentFolder, query: query)
            entries.append(.back(".."))
        } else {
            entries = ClipboardPickerSearch.rootEntries(
                history: history,
                snippetGroups: snippetGroups,
                query: query,
                mode: mode
            )
        }

        if let preferredEntryID,
           let preferredIndex = entries.firstIndex(where: { $0.id == preferredEntryID && $0.isSelectable }) {
            selectedIndex = preferredIndex
        } else if resetSelection || !entries.indices.contains(selectedIndex) || !entries[selectedIndex].isSelectable {
            selectedIndex = firstSelectableIndex() ?? -1
        }

        resizePanelForCurrentEntries()
        tableView.reloadData()
        syncTableWidth()
        if entries.count <= Metrics.maxVisibleRows {
            resetScrollPosition()
        }
        selectCurrentRow()
    }

    private func resizePanelForCurrentEntries() {
        let visibleRows = max(1, min(max(entries.count, 1), Metrics.maxVisibleRows))
        let overflows = entries.count > visibleRows
        let extraHeight = overflows ? 0 : Metrics.nonOverflowSlack
        let tableViewportHeight = entries
            .prefix(visibleRows)
            .reduce(CGFloat(0)) { $0 + height(for: $1) } + extraHeight
        let documentContentHeight = entries.reduce(CGFloat(0)) { $0 + height(for: $1) }
        let documentHeight = max(documentContentHeight + extraHeight, Metrics.rowHeight)
        let panelHeight =
            Metrics.topPadding +
            Metrics.searchHeight +
            Metrics.searchBottomSpacing +
            tableViewportHeight +
            Metrics.bottomPadding

        scrollView.hasVerticalScroller = overflows
        panel.setContentSize(NSSize(width: Metrics.panelWidth, height: panelHeight))
        panel.contentView?.layoutSubtreeIfNeeded()
        tableView.setFrameOrigin(NSPoint(x: 0, y: tableView.frame.origin.y))
        tableView.setFrameSize(NSSize(width: visibleTableWidth(), height: documentHeight))
        syncTableWidth()
    }

    private func syncTableWidth() {
        let tableWidth = visibleTableWidth()
        guard let column = tableView.tableColumns.first else {
            return
        }

        column.maxWidth = tableWidth
        column.width = tableWidth
        tableView.setFrameSize(NSSize(width: tableWidth, height: tableView.frame.height))
    }

    private func visibleTableWidth() -> CGFloat {
        let width = scrollView.contentSize.width
        return max(1, floor(min(Metrics.panelWidth, width > 0 ? width : Metrics.panelWidth)))
    }

    private func resetScrollPosition() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else {
            return
        }

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

    private func handleKeyDown(_ event: NSEvent, consumesLocalDuplicate: Bool = true) -> Bool {
        if consumesLocalDuplicate, consumeLocallyHandledEvent(event) {
            return true
        }

        switch UInt32(event.keyCode) {
        case UInt32(kVK_Escape):
            if leaveFolderIfNeeded() {
                return true
            }
            cancel()
            return true

        case UInt32(kVK_UpArrow):
            moveSelection(by: -1)
            return true

        case UInt32(kVK_DownArrow):
            moveSelection(by: 1)
            return true

        case UInt32(kVK_LeftArrow):
            return leaveFolderIfNeeded()

        case UInt32(kVK_RightArrow):
            return enterSelectedFolderIfNeeded()

        case UInt32(kVK_Delete), UInt32(kVK_ForwardDelete):
            if !query.isEmpty {
                return false
            }

            return leaveFolderIfNeeded()

        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter):
            activateSelected(activationMode: Self.activationMode(event: event))
            return true

        default:
            return false
        }
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKeyDown(event) ?? event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        if consumeLocallyHandledEvent(event) {
            return nil
        }

        guard panel.isVisible,
              event.window === panel || NSApp.keyWindow === panel
        else {
            return event
        }

        guard handleKeyDown(event, consumesLocalDuplicate: false) else {
            return event
        }

        locallyHandledKeyEvent = HandledKeyEvent(event)
        return nil
    }

    private func consumeLocallyHandledCurrentEvent() -> Bool {
        guard let event = NSApp.currentEvent else {
            return false
        }

        return consumeLocallyHandledEvent(event)
    }

    private func consumeLocallyHandledEvent(_ event: NSEvent) -> Bool {
        guard locallyHandledKeyEvent?.matches(event) == true else {
            return false
        }

        locallyHandledKeyEvent = nil
        return true
    }

    private func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return false
        }

        switch UInt32(event.keyCode) {
        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter):
            let activationMode = Self.activationMode(event: event)
            guard activationMode != .standard else {
                return false
            }

            activateSelected(activationMode: activationMode)
            return true

        default:
            return false
        }
    }

    fileprivate static func activationMode(event: NSEvent? = nil) -> ClipboardPickerActivationMode {
        ClipboardPickerActivationMode.fromModifiers(
            command: commandModifierIsActive(event: event),
            shift: shiftModifierIsActive(event: event)
        )
    }

    fileprivate static func shiftModifierIsActive(event: NSEvent? = nil) -> Bool {
        if event?.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift) == true {
            return true
        }

        let appKitShiftIsDown = NSEvent.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift)
        let coreGraphicsShiftIsDown = CGEventSource
            .flagsState(.combinedSessionState)
            .contains(.maskShift)
        let physicalShiftIsDown =
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Shift)) ||
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightShift))

        return appKitShiftIsDown || coreGraphicsShiftIsDown || physicalShiftIsDown
    }

    fileprivate static func commandModifierIsActive(event: NSEvent? = nil) -> Bool {
        if event?.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.command) == true {
            return true
        }

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

    private func moveSelection(by offset: Int) {
        let selectableIndices = entries.indices.filter { entries[$0].isSelectable }
        guard !selectableIndices.isEmpty else {
            return
        }

        guard let currentPosition = selectableIndices.firstIndex(of: selectedIndex) else {
            selectedIndex = offset < 0 ? selectableIndices.last! : selectableIndices.first!
            selectCurrentRow()
            return
        }

        let lastPosition = selectableIndices.index(before: selectableIndices.endIndex)
        let nextPosition: Int

        if offset < 0, currentPosition == selectableIndices.startIndex {
            nextPosition = lastPosition
        } else if offset > 0, currentPosition == lastPosition {
            nextPosition = selectableIndices.startIndex
        } else {
            nextPosition = min(max(currentPosition + offset, selectableIndices.startIndex), lastPosition)
        }

        selectedIndex = selectableIndices[nextPosition]
        selectCurrentRow()
    }

    private func selectHoveredRow(_ row: Int) {
        guard entries.indices.contains(row), entries[row].isSelectable, selectedIndex != row else {
            return
        }

        selectedIndex = row
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func activateSelected(activationMode: ClipboardPickerActivationMode) {
        activate(row: selectedIndex, activationMode: activationMode)
    }

    private func enterSelectedFolderIfNeeded() -> Bool {
        enterFolder(at: selectedIndex)
    }

    private func enterFolder(at row: Int) -> Bool {
        guard entries.indices.contains(row), let folder = entries[row].folder else {
            return false
        }

        currentFolder = folder
        query = ""
        searchField.stringValue = ""
        applyFilter(resetSelection: true)
        return true
    }

    private func activate(row: Int, activationMode: ClipboardPickerActivationMode) {
        guard entries.indices.contains(row), entries[row].isSelectable else {
            NSSound.beep()
            return
        }

        let entry = entries[row]

        if enterFolder(at: row) {
            return
        }

        if case .back = entry {
            _ = leaveFolderIfNeeded()
            return
        }

        guard let result = entry.pasteResult else {
            NSSound.beep()
            return
        }

        let handler = onSelect
        hide()
        handler?(result, activationMode)
    }

    private func leaveFolderIfNeeded() -> Bool {
        guard let folder = currentFolder else {
            return false
        }

        let parentEntryID = ClipboardPickerEntry.folder(folder).id
        currentFolder = nil
        query = ""
        searchField.stringValue = ""
        applyFilter(resetSelection: true, preferredEntryID: parentEntryID)
        return true
    }

    private func cancel() {
        let handler = onCancel
        hide()
        handler?()
    }

    private func firstSelectableIndex() -> Int? {
        entries.indices.first { entries[$0].isSelectable }
    }

    private func selectCurrentRow() {
        guard entries.indices.contains(selectedIndex), entries[selectedIndex].isSelectable else {
            tableView.deselectAll(nil)
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)

        if entries.count > Metrics.maxVisibleRows {
            tableView.scrollRowToVisible(selectedIndex)
        } else {
            resetScrollPosition()
        }
    }

    private func makeCell(for entry: ClipboardPickerEntry) -> NSView {
        let presentation = entry.presentation
        return ClipboardPickerCellView(
            title: presentation.title,
            trailingLabel: presentation.trailingLineCountLabel,
            textColor: textColor(for: entry),
            icon: image(for: entry),
            showsDisclosure: showsDisclosure(for: entry),
            layoutWidthLimit: Metrics.panelWidth
        )
    }

    private func showsDisclosure(for entry: ClipboardPickerEntry) -> Bool {
        switch entry {
        case .folder:
            return true
        case .header, .history, .snippet, .back, .empty:
            return false
        }
    }

    private func height(for entry: ClipboardPickerEntry) -> CGFloat {
        switch entry {
        case .header:
            return Metrics.headerRowHeight
        case .folder, .history, .snippet, .back, .empty:
            return Metrics.rowHeight
        }
    }

    private func image(for entry: ClipboardPickerEntry) -> NSImage? {
        switch entry {
        case .folder, .back:
            return folderIcon
        case .history, .snippet:
            return documentIcon
        case .header, .empty:
            return nil
        }
    }

    private func textColor(for entry: ClipboardPickerEntry) -> NSColor {
        switch entry {
        case .header, .empty:
            return .secondaryLabelColor
        case .folder, .history, .snippet, .back:
            return .labelColor
        }
    }

    private static func icon(_ source: NSImage, size: CGFloat = Metrics.iconSize) -> NSImage {
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

@MainActor
private final class ClipboardPickerRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else {
            return
        }

        NSColor.systemBlue.setFill()
        bounds.insetBy(dx: 0, dy: 1).fill()
    }
}

@MainActor
private final class ClipboardPickerCellView: NSTableCellView {
    private enum Metrics {
        static let iconSize: CGFloat = 16
        static let iconLeading: CGFloat = 0
        static let textSpacing: CGFloat = 4
        static let trailingPadding: CGFloat = 30
        static let headerLeading: CGFloat = -8
        static let disclosureSize: CGFloat = 12
        static let disclosureTrailing: CGFloat = 24
        static let disclosureSpacing: CGFloat = 8
    }

    private let title: String
    private let trailingLabel: String?
    private let textColor: NSColor
    private let font = NSFont.systemFont(ofSize: 13)
    private let iconView: NSImageView?
    private let showsDisclosure: Bool
    private let layoutWidthLimit: CGFloat

    init(
        title: String,
        trailingLabel: String?,
        textColor: NSColor,
        icon: NSImage?,
        showsDisclosure: Bool,
        layoutWidthLimit: CGFloat
    ) {
        self.title = title
        self.trailingLabel = trailingLabel
        self.textColor = textColor
        self.showsDisclosure = showsDisclosure
        self.layoutWidthLimit = layoutWidthLimit

        if let icon {
            let iconView = NSImageView(image: icon)
            iconView.imageScaling = .scaleProportionallyDown
            self.iconView = iconView
        } else {
            iconView = nil
        }

        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let textHeight = ceil(font.ascender - font.descender + font.leading)
        let textY = floor((bounds.height - textHeight) / 2)
        let visibleWidth = enclosingScrollView?.contentSize.width
        let layoutWidth = max(
            1,
            min(
                layoutWidthLimit,
                bounds.width,
                visibleWidth.flatMap { $0 > 0 ? $0 : nil } ?? layoutWidthLimit
            )
        )
        let textStart: CGFloat
        var textEnd = layoutWidth - Metrics.trailingPadding

        if let iconView {
            let iconRect = NSRect(
                x: Metrics.iconLeading,
                y: floor((bounds.height - Metrics.iconSize) / 2),
                width: Metrics.iconSize,
                height: Metrics.iconSize
            )
            iconView.image?.draw(
                in: iconRect,
                from: NSRect(origin: .zero, size: iconView.image?.size ?? .zero),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            textStart = iconRect.maxX + Metrics.textSpacing
        } else {
            textStart = Metrics.headerLeading
        }

        if showsDisclosure {
            let rect = NSRect(
                x: layoutWidth - Metrics.disclosureTrailing - Metrics.disclosureSize,
                y: floor((bounds.height - Metrics.disclosureSize) / 2),
                width: Metrics.disclosureSize,
                height: Metrics.disclosureSize
            )
            drawDisclosure(in: rect)
            textEnd = rect.minX - Metrics.disclosureSpacing
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
        if let trailingLabel {
            let marker = trailingLabel as NSString
            let markerWidth = ceil(marker.size(withAttributes: attributes).width)
            let markerX = max(textStart, textEnd - markerWidth)
            let markerRect = NSRect(
                x: markerX,
                y: textY,
                width: markerWidth,
                height: textHeight
            )
            marker.draw(at: markerRect.origin, withAttributes: attributes)
            textEnd = markerRect.minX - Metrics.textSpacing
        }

        let textRect = NSRect(
            x: textStart,
            y: textY,
            width: max(0, textEnd - textStart),
            height: textHeight
        )
        let renderedTitle = truncatedTitle(forWidth: textRect.width, attributes: attributes)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: textRect).setClip()
        renderedTitle.draw(at: textRect.origin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawDisclosure(in rect: NSRect) {
        NSColor.labelColor.setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX - 3, y: rect.midY - 5))
        path.line(to: NSPoint(x: rect.midX + 4, y: rect.midY))
        path.line(to: NSPoint(x: rect.midX - 3, y: rect.midY + 5))
        path.close()
        path.fill()
    }

    private func truncatedTitle(
        forWidth width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSString {
        guard width > 0 else {
            return ""
        }

        let fullTitle = title as NSString
        guard fullTitle.size(withAttributes: attributes).width > width else {
            return fullTitle
        }

        let ellipsis = "..." as NSString
        guard ellipsis.size(withAttributes: attributes).width <= width else {
            return ""
        }

        var low = 0
        var high = title.count

        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = String(title.prefix(mid)) + "..."
            if (candidate as NSString).size(withAttributes: attributes).width <= width {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return (String(title.prefix(low)) + "...") as NSString
    }
}

@MainActor
private final class ClipboardPickerPanelWindow: NSPanel {
    var keyEventHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        if keyEventHandler?(event) == true {
            return
        }

        super.sendEvent(event)
    }
}

@MainActor
private final class ClipboardPickerSearchField: NSSearchField {
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}

@MainActor
private final class ClipboardPickerScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y))
        reflectScrolledClipView(contentView)
    }
}

@MainActor
private final class ClipboardPickerClipView: NSClipView {
    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: 0, y: newOrigin.y))
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }
}

@MainActor
private final class ClipboardPickerTableView: NSTableView {
    var keyHandler: ((NSEvent) -> Bool)?
    var mouseSelectionHandler: ((Int, ClipboardPickerActivationMode) -> Void)?
    var hoverSelectionHandler: ((Int) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: localPoint)
        let activationMode = ClipboardPickerPanelController.activationMode(event: event)

        super.mouseDown(with: event)

        if clickedRow >= 0 {
            mouseSelectionHandler?(clickedRow, activationMode)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let hoveredRow = row(at: localPoint)

        if hoveredRow >= 0 {
            hoverSelectionHandler?(hoveredRow)
        }
    }
}
