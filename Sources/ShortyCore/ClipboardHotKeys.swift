import Foundation

public enum ClipboardMenuKind: Sendable {
    case combined
    case snippets
}

public enum ReservedHotKeys {
    public static let clipboardMenu = try! KeyCombo.parse("cmd+shift+v")
    public static let snippetsMenu = try! KeyCombo.parse("cmd+shift+b")
    public static let textCommand = try! KeyCombo.parse("option+space")
    public static let windowSwitcher = try! KeyCombo.parse("cmd+tab")
    public static let currentAppWindowSwitcher = try! KeyCombo.parse("cmd+grave")
    public static let moveWindowLeftHalf = try! KeyCombo.parse("ctrl+option+left")
    public static let moveWindowRightHalf = try! KeyCombo.parse("ctrl+option+right")
    public static let maximizeWindow = try! KeyCombo.parse("ctrl+option+cmd+up")
    public static let moveWindowToLeftMonitor = try! KeyCombo.parse("ctrl+option+cmd+left")
    public static let moveWindowToRightMonitor = try! KeyCombo.parse("ctrl+option+cmd+right")

    public static let descriptionsByNormalizedValue: [String: String] = [
        clipboardMenu.normalizedValue: "clipboard menu",
        snippetsMenu.normalizedValue: "snippets menu",
        textCommand.normalizedValue: "text command palette",
        windowSwitcher.normalizedValue: "window switcher",
        currentAppWindowSwitcher.normalizedValue: "current-app window switcher",
        moveWindowLeftHalf.normalizedValue: "move-window-left-half action",
        moveWindowRightHalf.normalizedValue: "move-window-right-half action",
        maximizeWindow.normalizedValue: "maximize-window action",
        moveWindowToLeftMonitor.normalizedValue: "move-window-to-left-monitor action",
        moveWindowToRightMonitor.normalizedValue: "move-window-to-right-monitor action",
    ]
}
