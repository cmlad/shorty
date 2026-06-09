import Carbon
import Foundation

public enum HotKeyCenterError: Error, CustomStringConvertible {
    case installHandlerFailed(OSStatus)
    case registerHotKeyFailed(String, OSStatus)

    public var description: String {
        switch self {
        case let .installHandlerFailed(status):
            return "Failed to install global hotkey handler: \(status)"
        case let .registerHotKeyFailed(hotkey, status):
            return "Failed to register hotkey `\(hotkey)`: \(status)"
        }
    }
}

public final class HotKeyCenter {
    public typealias TriggerHandler = (LoadedShortcut) -> Void

    private let triggerHandler: TriggerHandler
    private var eventHandlerRef: EventHandlerRef?
    private var registeredShortcutRefs: [EventHotKeyRef] = []
    private var registeredActionRefs: [EventHotKeyRef] = []
    private var shortcutsByEventID: [UInt32: LoadedShortcut] = [:]
    private var actionsByEventID: [UInt32: () -> Void] = [:]
    private var nextEventID: UInt32 = 1
    private let signature = fourCharCode("WCut")

    public init(triggerHandler: @escaping TriggerHandler) throws {
        self.triggerHandler = triggerHandler
        try installHandler()
    }

    deinit {
        unregisterAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    public func replace(with shortcuts: [LoadedShortcut]) throws {
        unregisterShortcuts()
        shortcutsByEventID.removeAll(keepingCapacity: true)

        for shortcut in shortcuts {
            let registered = try register(shortcut.hotKey)
            registeredShortcutRefs.append(registered.reference)
            shortcutsByEventID[registered.eventID] = shortcut
        }
    }

    public func replaceActions(with actions: [HotKeyAction]) throws {
        unregisterActions()
        actionsByEventID.removeAll(keepingCapacity: true)

        for action in actions {
            let registered = try register(action.hotKey)
            registeredActionRefs.append(registered.reference)
            actionsByEventID[registered.eventID] = action.handler
        }
    }

    public func unregisterAll() {
        unregisterShortcuts()
        unregisterActions()
        shortcutsByEventID.removeAll()
        actionsByEventID.removeAll()
    }

    private func unregisterShortcuts() {
        unregister(references: &registeredShortcutRefs)
    }

    private func unregisterActions() {
        unregister(references: &registeredActionRefs)
    }

    private func unregister(references: inout [EventHotKeyRef]) {
        for reference in references {
            UnregisterEventHotKey(reference)
        }

        references.removeAll()
    }

    private func installHandler() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                return center.handle(event: event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            throw HotKeyCenterError.installHandlerFailed(status)
        }
    }

    private func handle(event: EventRef?) -> OSStatus {
        guard let event else {
            return noErr
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        if let shortcut = shortcutsByEventID[hotKeyID.id] {
            triggerHandler(shortcut)
        } else if let action = actionsByEventID[hotKeyID.id] {
            action()
        }

        return noErr
    }

    private func register(_ hotKey: KeyCombo) throws -> (eventID: UInt32, reference: EventHotKeyRef) {
        var hotKeyRef: EventHotKeyRef?
        let eventID = nextEventID
        let hotKeyID = EventHotKeyID(signature: signature, id: eventID)

        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw HotKeyCenterError.registerHotKeyFailed(hotKey.normalizedValue, status)
        }

        nextEventID += 1
        return (eventID, hotKeyRef)
    }
}

public struct HotKeyAction {
    public let hotKey: KeyCombo
    fileprivate let handler: () -> Void

    public init(hotKey: KeyCombo, handler: @escaping () -> Void) {
        self.hotKey = hotKey
        self.handler = handler
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { partialResult, byte in
        (partialResult << 8) + OSType(byte)
    }
}
