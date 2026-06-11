import AppKit
@preconcurrency import ApplicationServices
import Foundation

public enum WindowMoveCommand: Sendable {
    case cycleHalf(WindowMoveDirection)
    case maximize
    case moveToMonitor(WindowMoveDirection)
}

public final class WindowMover {
    private let console: Console

    public init(console: Console) {
        self.console = console
    }

    @discardableResult
    public func moveFocusedWindow(_ command: WindowMoveCommand) -> ActivationResult {
        guard let focusedWindow = focusedWindow() else {
            let message = "No focused window found for window move."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        guard let currentFrame = frame(of: focusedWindow) else {
            let message = "Could not read focused window frame."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        let screens = Self.accessibilityVisibleFrames()
        guard !screens.isEmpty else {
            let message = "No screens found for window move."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        let targetFrame: CGRect?
        switch command {
        case let .cycleHalf(direction):
            targetFrame = WindowGeometryPlanner.halfCycleFrame(
                for: currentFrame,
                screens: screens,
                direction: direction
            )
        case .maximize:
            let orderedScreens = WindowGeometryPlanner.orderedScreens(screens)
            if let screenIndex = WindowGeometryPlanner.screenIndex(containing: currentFrame, screens: orderedScreens) {
                targetFrame = WindowGeometryPlanner.maximizeFrame(on: orderedScreens[screenIndex])
            } else {
                targetFrame = nil
            }
        case let .moveToMonitor(direction):
            targetFrame = WindowGeometryPlanner.monitorMoveFrame(
                for: currentFrame,
                screens: screens,
                direction: direction
            )
        }

        guard let targetFrame else {
            let message = "Could not determine target frame for focused window."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        guard setFrame(targetFrame, on: focusedWindow) else {
            let message = "Focused window refused move or resize."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        let message = "Moved focused window to \(Self.describe(targetFrame))."
        console.info(message)
        return ActivationResult(succeeded: true, message: message)
    }

    private static func accessibilityVisibleFrames() -> [CGRect] {
        let screens = NSScreen.screens
        let convertedFrames = screens.compactMap { screen -> CGRect? in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            return WindowGeometryPlanner.accessibilityFrame(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                displayBounds: CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
            )
        }

        return convertedFrames.isEmpty ? screens.map(\.visibleFrame) : convertedFrames
    }

    private func focusedWindow() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()

        if let window = elementAttribute(kAXFocusedWindowAttribute as CFString, on: systemWideElement) {
            return window
        }

        guard let focusedApplication = elementAttribute(kAXFocusedApplicationAttribute as CFString, on: systemWideElement) else {
            return nil
        }

        if let window = elementAttribute(kAXFocusedWindowAttribute as CFString, on: focusedApplication) {
            return window
        }

        return elementAttribute(kAXMainWindowAttribute as CFString, on: focusedApplication)
    }

    private func elementAttribute(_ attribute: CFString, on element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard status == .success, let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, on: window),
              let size = sizeAttribute(kAXSizeAttribute as CFString, on: window) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, on window: AXUIElement) -> Bool {
        let positioned = setPoint(frame.origin, attribute: kAXPositionAttribute as CFString, on: window)
        let sized = setSize(frame.size, attribute: kAXSizeAttribute as CFString, on: window)
        let repositioned = setPoint(frame.origin, attribute: kAXPositionAttribute as CFString, on: window)

        return positioned && sized && repositioned
    }

    private func pointAttribute(_ attribute: CFString, on element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeAttribute(_ attribute: CFString, on element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func setPoint(_ point: CGPoint, attribute: CFString, on element: AXUIElement) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            return false
        }

        return AXUIElementSetAttributeValue(element, attribute, value) == .success
    }

    private func setSize(_ size: CGSize, attribute: CFString, on element: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            return false
        }

        return AXUIElementSetAttributeValue(element, attribute, value) == .success
    }

    private static func describe(_ frame: CGRect) -> String {
        "x=\(Int(frame.minX)), y=\(Int(frame.minY)), width=\(Int(frame.width)), height=\(Int(frame.height))"
    }
}
