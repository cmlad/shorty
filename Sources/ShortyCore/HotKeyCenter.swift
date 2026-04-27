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
    private var registeredRefs: [EventHotKeyRef] = []
    private var shortcutsByEventID: [UInt32: LoadedShortcut] = [:]
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
        unregisterAll()
        shortcutsByEventID.removeAll(keepingCapacity: true)
        nextEventID = 1

        for shortcut in shortcuts {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: nextEventID)

            let status = RegisterEventHotKey(
                shortcut.hotKey.keyCode,
                shortcut.hotKey.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            guard status == noErr, let hotKeyRef else {
                throw HotKeyCenterError.registerHotKeyFailed(shortcut.hotKey.normalizedValue, status)
            }

            registeredRefs.append(hotKeyRef)
            shortcutsByEventID[nextEventID] = shortcut
            nextEventID += 1
        }
    }

    public func unregisterAll() {
        for reference in registeredRefs {
            UnregisterEventHotKey(reference)
        }

        registeredRefs.removeAll()
        shortcutsByEventID.removeAll()
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
        }

        return noErr
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { partialResult, byte in
        (partialResult << 8) + OSType(byte)
    }
}
