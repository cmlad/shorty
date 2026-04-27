import Carbon
import Foundation

public enum KeyComboError: Error, CustomStringConvertible {
    case missingKey(String)
    case duplicateKey(String)
    case unknownModifier(String)
    case unknownKey(String)

    public var description: String {
        switch self {
        case let .missingKey(rawValue):
            return "Hotkey `\(rawValue)` is missing a key."
        case let .duplicateKey(rawValue):
            return "Hotkey `\(rawValue)` defines more than one key."
        case let .unknownModifier(modifier):
            return "Unknown hotkey modifier `\(modifier)`."
        case let .unknownKey(key):
            return "Unknown hotkey key `\(key)`."
        }
    }
}

public struct KeyCombo: Hashable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let normalizedValue: String

    public static func parse(_ rawValue: String) throws -> KeyCombo {
        let tokens = rawValue
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        var modifiers: UInt32 = 0
        var key: (name: String, code: UInt32)?

        for token in tokens {
            if let modifier = modifierMask(for: token) {
                modifiers |= modifier
                continue
            }

            guard key == nil else {
                throw KeyComboError.duplicateKey(rawValue)
            }

            guard let resolved = keyCode(for: token) else {
                throw KeyComboError.unknownKey(token)
            }

            key = resolved
        }

        guard let key else {
            throw KeyComboError.missingKey(rawValue)
        }

        var parts: [String] = []

        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("cmd")
        }

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("ctrl")
        }

        if modifiers & UInt32(optionKey) != 0 {
            parts.append("option")
        }

        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("shift")
        }

        parts.append(key.name)

        return KeyCombo(
            keyCode: key.code,
            modifiers: modifiers,
            normalizedValue: parts.joined(separator: "+")
        )
    }

    private static func modifierMask(for token: String) -> UInt32? {
        switch token {
        case "cmd", "command":
            return UInt32(cmdKey)
        case "ctrl", "control":
            return UInt32(controlKey)
        case "alt", "option":
            return UInt32(optionKey)
        case "shift":
            return UInt32(shiftKey)
        default:
            return nil
        }
    }

    private static func keyCode(for token: String) -> (String, UInt32)? {
        keyMap[token]
    }

    private static let keyMap: [String: (String, UInt32)] = [
        "a": ("a", UInt32(kVK_ANSI_A)),
        "b": ("b", UInt32(kVK_ANSI_B)),
        "c": ("c", UInt32(kVK_ANSI_C)),
        "d": ("d", UInt32(kVK_ANSI_D)),
        "e": ("e", UInt32(kVK_ANSI_E)),
        "f": ("f", UInt32(kVK_ANSI_F)),
        "g": ("g", UInt32(kVK_ANSI_G)),
        "h": ("h", UInt32(kVK_ANSI_H)),
        "i": ("i", UInt32(kVK_ANSI_I)),
        "j": ("j", UInt32(kVK_ANSI_J)),
        "k": ("k", UInt32(kVK_ANSI_K)),
        "l": ("l", UInt32(kVK_ANSI_L)),
        "m": ("m", UInt32(kVK_ANSI_M)),
        "n": ("n", UInt32(kVK_ANSI_N)),
        "o": ("o", UInt32(kVK_ANSI_O)),
        "p": ("p", UInt32(kVK_ANSI_P)),
        "q": ("q", UInt32(kVK_ANSI_Q)),
        "r": ("r", UInt32(kVK_ANSI_R)),
        "s": ("s", UInt32(kVK_ANSI_S)),
        "t": ("t", UInt32(kVK_ANSI_T)),
        "u": ("u", UInt32(kVK_ANSI_U)),
        "v": ("v", UInt32(kVK_ANSI_V)),
        "w": ("w", UInt32(kVK_ANSI_W)),
        "x": ("x", UInt32(kVK_ANSI_X)),
        "y": ("y", UInt32(kVK_ANSI_Y)),
        "z": ("z", UInt32(kVK_ANSI_Z)),
        "0": ("0", UInt32(kVK_ANSI_0)),
        "1": ("1", UInt32(kVK_ANSI_1)),
        "2": ("2", UInt32(kVK_ANSI_2)),
        "3": ("3", UInt32(kVK_ANSI_3)),
        "4": ("4", UInt32(kVK_ANSI_4)),
        "5": ("5", UInt32(kVK_ANSI_5)),
        "6": ("6", UInt32(kVK_ANSI_6)),
        "7": ("7", UInt32(kVK_ANSI_7)),
        "8": ("8", UInt32(kVK_ANSI_8)),
        "9": ("9", UInt32(kVK_ANSI_9)),
        "minus": ("minus", UInt32(kVK_ANSI_Minus)),
        "equal": ("equal", UInt32(kVK_ANSI_Equal)),
        "comma": ("comma", UInt32(kVK_ANSI_Comma)),
        "period": ("period", UInt32(kVK_ANSI_Period)),
        "slash": ("slash", UInt32(kVK_ANSI_Slash)),
        "backslash": ("backslash", UInt32(kVK_ANSI_Backslash)),
        "semicolon": ("semicolon", UInt32(kVK_ANSI_Semicolon)),
        "quote": ("quote", UInt32(kVK_ANSI_Quote)),
        "grave": ("grave", UInt32(kVK_ANSI_Grave)),
        "leftbracket": ("leftbracket", UInt32(kVK_ANSI_LeftBracket)),
        "rightbracket": ("rightbracket", UInt32(kVK_ANSI_RightBracket)),
        "space": ("space", UInt32(kVK_Space)),
        "tab": ("tab", UInt32(kVK_Tab)),
        "enter": ("enter", UInt32(kVK_Return)),
        "return": ("return", UInt32(kVK_Return)),
        "escape": ("escape", UInt32(kVK_Escape)),
        "esc": ("esc", UInt32(kVK_Escape)),
        "delete": ("delete", UInt32(kVK_Delete)),
        "forwarddelete": ("forwarddelete", UInt32(kVK_ForwardDelete)),
        "home": ("home", UInt32(kVK_Home)),
        "end": ("end", UInt32(kVK_End)),
        "pageup": ("pageup", UInt32(kVK_PageUp)),
        "pagedown": ("pagedown", UInt32(kVK_PageDown)),
        "left": ("left", UInt32(kVK_LeftArrow)),
        "right": ("right", UInt32(kVK_RightArrow)),
        "up": ("up", UInt32(kVK_UpArrow)),
        "down": ("down", UInt32(kVK_DownArrow)),
        "f1": ("f1", UInt32(kVK_F1)),
        "f2": ("f2", UInt32(kVK_F2)),
        "f3": ("f3", UInt32(kVK_F3)),
        "f4": ("f4", UInt32(kVK_F4)),
        "f5": ("f5", UInt32(kVK_F5)),
        "f6": ("f6", UInt32(kVK_F6)),
        "f7": ("f7", UInt32(kVK_F7)),
        "f8": ("f8", UInt32(kVK_F8)),
        "f9": ("f9", UInt32(kVK_F9)),
        "f10": ("f10", UInt32(kVK_F10)),
        "f11": ("f11", UInt32(kVK_F11)),
        "f12": ("f12", UInt32(kVK_F12)),
        "f13": ("f13", UInt32(kVK_F13)),
        "f14": ("f14", UInt32(kVK_F14)),
        "f15": ("f15", UInt32(kVK_F15)),
        "f16": ("f16", UInt32(kVK_F16)),
        "f17": ("f17", UInt32(kVK_F17)),
        "f18": ("f18", UInt32(kVK_F18)),
        "f19": ("f19", UInt32(kVK_F19)),
        "f20": ("f20", UInt32(kVK_F20)),
    ]
}
