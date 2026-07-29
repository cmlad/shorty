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
        let context = focusedWindowContext()
        let candidates = prioritizedCandidates(context.candidates, focusedPID: context.pid)
        guard !candidates.isEmpty else {
            let message = "No focused window found for window move."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        let screens = Self.accessibilityVisibleFrames()
        guard !screens.isEmpty else {
            let message = "No screens found for window move."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        var readableWindowCount = 0
        for candidate in candidates {
            guard let currentFrame = frame(of: candidate.window) else {
                continue
            }

            readableWindowCount += 1
            console.info("Trying window move candidate `\(candidate.source)` at \(Self.describe(currentFrame)).")

            guard let targetFrame = targetFrame(for: command, currentFrame: currentFrame, screens: screens) else {
                continue
            }

            let fullScreenAttribute = "AXFullScreen" as CFString
            if boolAttribute(fullScreenAttribute, on: candidate.window) == true {
                _ = setBool(false, attribute: fullScreenAttribute, on: candidate.window)
            }

            if let appliedFrame = setFrame(targetFrame, on: candidate.window, screens: screens) {
                let message = "Moved focused window to \(Self.describe(appliedFrame))."
                console.info(message)
                return ActivationResult(succeeded: true, message: message)
            }

            console.info("Window move candidate `\(candidate.source)` did not apply target \(Self.describe(targetFrame)).")
        }

        guard readableWindowCount > 0 else {
            let message = "Could not read focused window frame."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        let message = "Focused window refused move or resize after trying \(readableWindowCount) candidate(s)."
        console.error(message)
        return ActivationResult(succeeded: false, message: message)
    }

    private func targetFrame(
        for command: WindowMoveCommand,
        currentFrame: CGRect,
        screens: [CGRect]
    ) -> CGRect? {
        switch command {
        case let .cycleHalf(direction):
            return WindowGeometryPlanner.halfCycleFrame(
                for: currentFrame,
                screens: screens,
                direction: direction
            )
        case .maximize:
            let orderedScreens = WindowGeometryPlanner.orderedScreens(screens)
            guard let screenIndex = WindowGeometryPlanner.screenIndex(containing: currentFrame, screens: orderedScreens) else {
                return nil
            }

            return WindowGeometryPlanner.maximizeFrame(on: orderedScreens[screenIndex])
        case let .moveToMonitor(direction):
            return WindowGeometryPlanner.monitorMoveFrame(
                for: currentFrame,
                screens: screens,
                direction: direction
            )
        }
    }

    private func focusedWindowContext() -> (pid: pid_t?, candidates: [WindowCandidate]) {
        let systemWideElement = AXUIElementCreateSystemWide()
        var candidates: [WindowCandidate] = []
        var focusedPID: pid_t?

        append(
            elementAttribute(kAXFocusedWindowAttribute as CFString, on: systemWideElement),
            source: "system focused window",
            to: &candidates
        )

        if let focusedElement = elementAttribute(kAXFocusedUIElementAttribute as CFString, on: systemWideElement) {
            append(
                elementAttribute(kAXWindowAttribute as CFString, on: focusedElement),
                source: "focused element window",
                to: &candidates
            )
        }

        if let focusedApplication = elementAttribute(kAXFocusedApplicationAttribute as CFString, on: systemWideElement) {
            focusedPID = pid(of: focusedApplication)
            appendApplicationWindows(from: focusedApplication, sourcePrefix: "focused app", to: &candidates)
        } else {
            console.info("System-wide focused application unavailable for window move.")
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           !frontmostApplication.isTerminated,
           frontmostApplication.activationPolicy != .prohibited {
            let pid = frontmostApplication.processIdentifier
            focusedPID = pid
            appendApplicationWindows(
                from: AXUIElementCreateApplication(pid),
                sourcePrefix: "frontmost app",
                to: &candidates
            )
        }

        if candidates.isEmpty,
           let visiblePID = topmostVisibleWindowOwnerPID(excluding: ProcessInfo.processInfo.processIdentifier) {
            focusedPID = visiblePID
            appendApplicationWindows(
                from: AXUIElementCreateApplication(visiblePID),
                sourcePrefix: "topmost visible app",
                to: &candidates
            )
        }

        return (focusedPID, candidates)
    }

    private func appendApplicationWindows(
        from application: AXUIElement,
        sourcePrefix: String,
        to candidates: inout [WindowCandidate]
    ) {
        append(
            elementAttribute(kAXFocusedWindowAttribute as CFString, on: application),
            source: "\(sourcePrefix) focused window",
            to: &candidates
        )
        append(
            elementAttribute(kAXMainWindowAttribute as CFString, on: application),
            source: "\(sourcePrefix) main window",
            to: &candidates
        )

        for (index, window) in windowsAttribute(on: application).enumerated() {
            append(window, source: "\(sourcePrefix) windows[\(index)]", to: &candidates)
        }
    }

    private func append(_ candidate: AXUIElement?, source: String, to candidates: inout [WindowCandidate]) {
        guard let candidate else {
            return
        }

        guard !candidates.contains(where: { CFEqual($0.window, candidate) }) else {
            return
        }

        candidates.append(WindowCandidate(window: candidate, source: source))
    }

    private func prioritizedCandidates(_ candidates: [WindowCandidate], focusedPID: pid_t?) -> [WindowCandidate] {
        guard let focusedPID,
              let visibleFrame = topmostVisibleWindowFrame(for: focusedPID) else {
            return candidates
        }

        let scoredCandidates = candidates.map { candidate in
            (candidate: candidate, score: visibleWindowMatchScore(candidate.window, visibleFrame: visibleFrame))
        }
        let visibleCandidates = scoredCandidates.filter { $0.score > 0.2 }
        let prioritized = visibleCandidates.isEmpty ? scoredCandidates : visibleCandidates

        return prioritized
            .sorted { first, second in
                if first.score == second.score {
                    return first.candidate.source < second.candidate.source
                }

                return first.score > second.score
            }
            .map(\.candidate)
    }

    private func visibleWindowMatchScore(_ window: AXUIElement, visibleFrame: CGRect) -> CGFloat {
        guard let candidateFrame = frame(of: window) else {
            return 0
        }

        let intersection = candidateFrame.standardized.intersection(visibleFrame.standardized)
        guard !intersection.isNull else {
            return 0
        }

        let intersectionArea = intersection.width * intersection.height
        let unionArea =
            candidateFrame.width * candidateFrame.height +
            visibleFrame.width * visibleFrame.height -
            intersectionArea

        guard unionArea > 0 else {
            return 0
        }

        return intersectionArea / unionArea
    }

    private func topmostVisibleWindowFrame(for pid: pid_t) -> CGRect? {
        topmostVisibleWindowInfo(for: pid)?.frame
    }

    private func topmostVisibleWindowOwnerPID(excluding excludedPID: pid_t) -> pid_t? {
        topmostVisibleWindowInfo(excluding: excludedPID)?.pid
    }

    private func topmostVisibleWindowInfo(for pid: pid_t? = nil, excluding excludedPID: pid_t? = nil) -> VisibleWindowInfo? {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowInfoList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = windowInfo[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = windowInfo[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
                  frame.width > 0,
                  frame.height > 0 else {
                continue
            }

            let windowPID = ownerPID.int32Value
            if let pid, windowPID != pid {
                continue
            }

            if let excludedPID, windowPID == excludedPID {
                continue
            }

            return VisibleWindowInfo(pid: windowPID, frame: frame)
        }

        return nil
    }

    private func windowsAttribute(on element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)

        guard status == .success, let value else {
            return []
        }

        if let windows = value as? [AXUIElement] {
            return windows
        }

        if let array = value as? [Any] {
            return array.compactMap { $0 as! AXUIElement? }
        }

        return []
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, on: window),
              let size = sizeAttribute(kAXSizeAttribute as CFString, on: window) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ targetFrame: CGRect, on window: AXUIElement, screens: [CGRect]) -> CGRect? {
        let originalFrame = frame(of: window)

        _ = setSize(targetFrame.size, attribute: kAXSizeAttribute as CFString, on: window)
        _ = setPoint(targetFrame.origin, attribute: kAXPositionAttribute as CFString, on: window)
        _ = setSize(targetFrame.size, attribute: kAXSizeAttribute as CFString, on: window)
        _ = setPoint(targetFrame.origin, attribute: kAXPositionAttribute as CFString, on: window)

        guard let firstAppliedFrame = frame(of: window) else {
            return nil
        }

        if WindowGeometryPlanner.isApproximately(firstAppliedFrame, targetFrame) {
            return firstAppliedFrame
        }

        let fittingOrigin = WindowGeometryPlanner.fittingOrigin(
            for: targetFrame,
            actualSize: firstAppliedFrame.size,
            screens: screens
        )
        _ = setPoint(fittingOrigin, attribute: kAXPositionAttribute as CFString, on: window)

        guard let finalFrame = frame(of: window) else {
            return nil
        }

        if WindowGeometryPlanner.isApproximately(finalFrame, targetFrame) {
            return finalFrame
        }

        guard let originalFrame else {
            return nil
        }

        guard movedOrResized(from: originalFrame, to: finalFrame) else {
            return nil
        }

        if WindowGeometryPlanner.isApproximately(finalFrame.origin, fittingOrigin) {
            return finalFrame
        }

        return finalFrame
    }

    private func movedOrResized(from originalFrame: CGRect, to finalFrame: CGRect) -> Bool {
        !WindowGeometryPlanner.isApproximately(originalFrame, finalFrame, tolerance: 2)
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

    private func elementAttribute(_ attribute: CFString, on element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func boolAttribute(_ attribute: CFString, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard status == .success,
              let value,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }

        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
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

    private func setBool(_ value: Bool, attribute: CFString, on element: AXUIElement) -> Bool {
        let boolValue: CFBoolean = value ? kCFBooleanTrue! : kCFBooleanFalse!
        return AXUIElementSetAttributeValue(element, attribute, boolValue) == .success
    }

    private func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }

        return pid
    }

    private static func describe(_ frame: CGRect) -> String {
        "x=\(Int(frame.minX)), y=\(Int(frame.minY)), width=\(Int(frame.width)), height=\(Int(frame.height))"
    }
}

private struct WindowCandidate {
    let window: AXUIElement
    let source: String
}

private struct VisibleWindowInfo {
    let pid: pid_t
    let frame: CGRect
}
