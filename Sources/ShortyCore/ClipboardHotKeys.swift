import Foundation

public enum ClipboardMenuKind: Sendable {
    case combined
    case snippets
}

public enum ReservedHotKeys {
    public static let clipboardMenu = try! KeyCombo.parse("cmd+shift+v")
    public static let snippetsMenu = try! KeyCombo.parse("cmd+shift+b")

    public static let descriptionsByNormalizedValue: [String: String] = [
        clipboardMenu.normalizedValue: "clipboard menu",
        snippetsMenu.normalizedValue: "snippets menu",
    ]
}
