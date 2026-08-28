import Foundation

public enum ClipboardPickerActivationMode: Equatable, Sendable {
    case standard
    case plainText
    case joinedLines

    public static func fromModifiers(command: Bool, shift: Bool) -> ClipboardPickerActivationMode {
        if shift {
            return .joinedLines
        }

        if command {
            return .plainText
        }

        return .standard
    }
}
