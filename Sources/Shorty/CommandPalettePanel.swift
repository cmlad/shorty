import AppKit
import Carbon
import ShortyCore

@MainActor
final class CommandPalettePanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private enum Metrics {
        static let panelWidth: CGFloat = 760
        static let topPadding: CGFloat = 9
        static let emptyBottomPadding: CGFloat = 10
        static let resultBottomPadding: CGFloat = 5
        static let horizontalPadding: CGFloat = 10
        static let searchHeight: CGFloat = 30
        static let searchFontSize: CGFloat = 18
        static let resultTopSpacing: CGFloat = 6
        static let rowSpacing: CGFloat = 2
        static let topOffsetRatio: CGFloat = 0.20
        static let bottomMargin: CGFloat = 20
    }

    private let panel: CommandPalettePanelWindow
    private let searchField = CommandPaletteTextField(frame: .zero)
    private let stackView = NSStackView()
    private var entries: [CommandTransformerEvaluation] = []
    private var rowHeights: [CGFloat] = []
    private var isPresentingNestedPicker = false
    private var pendingInsertionRange: NSRange?
    private var selectionRangeAfterRefocus: NSRange?
    var pickerRequestHandler: ((ClipboardMenuKind) -> Void)?

    override init() {
        panel = CommandPalettePanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        configureSearchField()
        configureStackView()
    }

    func show() {
        searchField.stringValue = ""
        selectionRangeAfterRefocus = nil
        updateResults()
        resizePanel()
        positionPanel()

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        isPresentingNestedPicker = false
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPresentingNestedPicker else {
            return
        }

        if panel.isVisible {
            hide()
        }
    }

    func insertTextFromPicker(_ text: String) {
        replaceSelectedText(with: text, fallbackRange: pendingInsertionRange)
        pendingInsertionRange = nil
        refocusAfterNestedPicker()
    }

    func cancelNestedPicker() {
        pendingInsertionRange = nil
        refocusAfterNestedPicker()
    }

    func requestNestedPickerFromHotKey(_ kind: ClipboardMenuKind) -> Bool {
        if isPresentingNestedPicker {
            return true
        }

        guard panel.isVisible else {
            return false
        }

        requestNestedPicker(kind)
        return true
    }

    func controlTextDidChange(_ notification: Notification) {
        updateResults()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            copyFirstCompleteResult()
            return true

        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true

        default:
            return false
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
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchField)
        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.topPadding),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.horizontalPadding),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.horizontalPadding),
            searchField.heightAnchor.constraint(equalToConstant: Metrics.searchHeight),

            stackView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Metrics.resultTopSpacing),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.horizontalPadding),
        ])
    }

    private func configureSearchField() {
        searchField.placeholderString = "Command"
        searchField.delegate = self
        searchField.font = NSFont.systemFont(ofSize: Metrics.searchFontSize)
        searchField.cell?.font = searchField.font
        searchField.textColor = .labelColor
        searchField.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1)
        searchField.drawsBackground = true
        searchField.isBezeled = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.keyHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }

    private func configureStackView() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .gravityAreas
        stackView.spacing = Metrics.rowSpacing
    }

    private func updateResults() {
        entries = CommandTransformerEngine.evaluate(searchField.stringValue)
        rowHeights = entries.map {
            CommandPaletteResultRowView.height(for: $0, width: Metrics.panelWidth - Metrics.horizontalPadding * 2)
        }

        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (entry, rowHeight) in zip(entries, rowHeights) {
            let row = CommandPaletteResultRowView(evaluation: entry)
            row.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: stackView.widthAnchor),
                row.heightAnchor.constraint(equalToConstant: rowHeight),
            ])
        }

        resizePanel()
        positionPanel()
    }

    private func resizePanel() {
        let rowsHeight = rowHeights.reduce(CGFloat(0), +) + CGFloat(max(0, rowHeights.count - 1)) * Metrics.rowSpacing
        let resultsHeight = entries.isEmpty
            ? 0
            : Metrics.resultTopSpacing + rowsHeight
        let bottomPadding = entries.isEmpty ? Metrics.emptyBottomPadding : Metrics.resultBottomPadding
        let panelHeight = Metrics.topPadding + Metrics.searchHeight + resultsHeight + bottomPadding

        panel.setContentSize(NSSize(width: Metrics.panelWidth, height: panelHeight))
        panel.contentView?.layoutSubtreeIfNeeded()
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

    private func copyFirstCompleteResult() {
        guard let result = entries.first(where: \.isComplete)?.resultText else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result, forType: .string)
        hide()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if handleCommandKey(event) {
            return true
        }

        switch UInt32(event.keyCode) {
        case UInt32(kVK_Escape):
            hide()
            return true

        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter):
            copyFirstCompleteResult()
            return true

        default:
            return false
        }
    }

    private func handleCommandKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else {
            return false
        }

        switch UInt32(event.keyCode) {
        case UInt32(kVK_ANSI_A):
            searchField.selectText(nil)
            return true

        case UInt32(kVK_ANSI_C):
            copySelection()
            return true

        case UInt32(kVK_ANSI_V):
            if flags.contains(.shift) {
                requestNestedPicker(.combined)
            } else {
                pasteFromSystemClipboard()
            }
            return true

        case UInt32(kVK_ANSI_B):
            requestNestedPicker(.snippets)
            return true

        default:
            return false
        }
    }

    private func pasteFromSystemClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            NSSound.beep()
            return
        }

        replaceSelectedText(with: text, fallbackRange: nil)
    }

    private func copySelection() {
        let range = selectedRange()
        let currentValue = searchField.stringValue as NSString
        guard range.length > 0, NSMaxRange(range) <= currentValue.length else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentValue.substring(with: range), forType: .string)
    }

    private func requestNestedPicker(_ kind: ClipboardMenuKind) {
        guard let pickerRequestHandler else {
            return
        }

        pendingInsertionRange = selectedRange()
        isPresentingNestedPicker = true
        panel.orderOut(nil)
        pickerRequestHandler(kind)
    }

    private func replaceSelectedText(with text: String, fallbackRange: NSRange?) {
        let currentValue = searchField.stringValue as NSString
        let range = validRange(fallbackRange ?? selectedRange(), in: currentValue)
        let replacement = currentValue.replacingCharacters(in: range, with: text)
        let cursorLocation = range.location + (text as NSString).length

        searchField.stringValue = replacement
        updateResults()
        let newSelectionRange = NSRange(location: cursorLocation, length: 0)
        if searchField.currentEditor() == nil {
            selectionRangeAfterRefocus = newSelectionRange
        }
        setSelectedRange(newSelectionRange)
    }

    private func selectedRange() -> NSRange {
        if let editor = searchField.currentEditor() {
            return editor.selectedRange
        }

        return NSRange(location: (searchField.stringValue as NSString).length, length: 0)
    }

    private func setSelectedRange(_ range: NSRange) {
        searchField.currentEditor()?.selectedRange = range
    }

    private func validRange(_ range: NSRange, in value: NSString) -> NSRange {
        guard range.location >= 0, range.location <= value.length else {
            return NSRange(location: value.length, length: 0)
        }

        let maxLength = value.length - range.location
        return NSRange(location: range.location, length: min(range.length, maxLength))
    }

    private func refocusAfterNestedPicker() {
        isPresentingNestedPicker = false
        resizePanel()
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        if let selectionRangeAfterRefocus {
            setSelectedRange(selectionRangeAfterRefocus)
            self.selectionRangeAfterRefocus = nil
        }
    }

    private func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return false
        }

        return handleKeyDown(event)
    }
}

@MainActor
private final class CommandPaletteResultRowView: NSView {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 8
        static let topPadding: CGFloat = 6
        static let valueTopSpacing: CGFloat = 4
        static let bottomPadding: CGFloat = 4
        static let nameFontSize: CGFloat = 12
        static let valueFontSize: CGFloat = 15
        static let lineHeight: CGFloat = 19
    }

    init(evaluation: CommandTransformerEvaluation) {
        super.init(frame: .zero)

        wantsLayer = true

        let nameField = NSTextField(labelWithString: evaluation.transformerName)
        nameField.font = Self.nameFont
        nameField.textColor = .secondaryLabelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let valueField = NSTextField(labelWithAttributedString: Self.valueString(for: evaluation))
        valueField.font = Self.valueFont
        valueField.lineBreakMode = .byTruncatingTail
        valueField.maximumNumberOfLines = 0
        valueField.usesSingleLineMode = false
        valueField.isSelectable = true
        valueField.isEditable = false
        valueField.isBordered = false
        valueField.drawsBackground = false
        valueField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nameField)
        addSubview(valueField)

        NSLayoutConstraint.activate([
            nameField.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.topPadding),
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),

            valueField.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: Metrics.valueTopSpacing),
            valueField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            valueField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Metrics.bottomPadding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func height(for evaluation: CommandTransformerEvaluation, width: CGFloat) -> CGFloat {
        let value = evaluation.resultText ?? evaluation.displayText
        let lineCount = max(1, value.components(separatedBy: .newlines).count)
        return Metrics.topPadding +
            ceil(Self.nameFont.ascender - Self.nameFont.descender + Self.nameFont.leading) +
            Metrics.valueTopSpacing +
            CGFloat(lineCount) * Metrics.lineHeight +
            Metrics.bottomPadding
    }

    private static func valueString(for evaluation: CommandTransformerEvaluation) -> NSAttributedString {
        if let resultText = evaluation.resultText {
            return NSAttributedString(
                string: resultText,
                attributes: [
                    .font: Self.valueFont,
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        }

        let attributed = NSMutableAttributedString()
        for segment in evaluation.segments {
            attributed.append(
                NSAttributedString(
                    string: segment.text,
                    attributes: [
                        .font: Self.valueFont,
                        .foregroundColor: color(for: segment.kind),
                    ]
                )
            )
        }

        return attributed
    }

    private static func color(for kind: CommandDisplaySegmentKind) -> NSColor {
        switch kind {
        case .matched:
            return .labelColor
        case .placeholder:
            return .secondaryLabelColor
        }
    }

    private static let nameFont = NSFont.systemFont(ofSize: Metrics.nameFontSize, weight: .medium)
    private static let valueFont = NSFont.monospacedSystemFont(ofSize: Metrics.valueFontSize, weight: .regular)
}

@MainActor
private final class CommandPalettePanelWindow: NSPanel {
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
private final class CommandPaletteTextField: NSTextField {
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}
