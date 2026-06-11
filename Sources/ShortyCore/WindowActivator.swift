import AppKit
@preconcurrency import ApplicationServices
import Foundation

public struct ActivationResult {
    public let succeeded: Bool
    public let message: String
}

public struct WindowDescriptor {
    public let appWindowIndex: Int
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    public let executablePath: String?
    public let title: String
    public let document: String?
    public let url: String?
    public let identifier: String?
    public let role: String?
    public let subrole: String?
    public let position: CGPoint?
    public let size: CGSize?
    public let minimized: Bool?
}

public final class WindowActivator {
    private let console: Console
    private var cachedTargetsByShortcutID: [String: CachedWindowTarget] = [:]

    public init(console: Console) {
        self.console = console
    }

    public func resetCache() {
        cachedTargetsByShortcutID.removeAll()
    }

    public static func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public func activate(_ shortcut: LoadedShortcut) -> ActivationResult {
        if let cachedTarget = cachedMatch(for: shortcut) {
            return activateResolvedWindow(cachedTarget, for: shortcut)
        }

        let matches = matchingWindows(for: shortcut.matcher)

        guard matches.indices.contains(shortcut.matcher.windowIndex) else {
            let message = matches.isEmpty
                ? "No window matched `\(shortcut.id)`."
                : "Shortcut `\(shortcut.id)` matched \(matches.count) window(s), but window-index \(shortcut.matcher.windowIndex) is out of range."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        let target = matches[shortcut.matcher.windowIndex]
        cachedTargetsByShortcutID[shortcut.id] = CachedWindowTarget(
            pid: target.app.processIdentifier,
            window: target.window,
            appWindowIndex: target.appWindowIndex
        )
        return activateResolvedWindow(target, for: shortcut)
    }

    public func listWindows() -> [WindowDescriptor] {
        enumerateWindows(detail: .verbose)
            .map { window in
                WindowDescriptor(
                    appWindowIndex: window.appWindowIndex,
                    pid: window.app.processIdentifier,
                    bundleID: window.app.bundleIdentifier,
                    appName: window.app.localizedName ?? "<unknown>",
                    executablePath: window.executablePath,
                    title: window.title,
                    document: window.document,
                    url: window.url,
                    identifier: window.identifier,
                    role: window.role,
                    subrole: window.subrole,
                    position: window.position,
                    size: window.size,
                    minimized: window.minimized
                )
            }
    }

    @discardableResult
    public func activate(_ switchableWindow: SwitchableWindow) -> ActivationResult {
        guard let app = NSRunningApplication(processIdentifier: switchableWindow.pid) else {
            let message = "No running application found for selected window."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        guard !app.isTerminated else {
            let message = "Selected window's application has terminated."
            console.error(message)
            return ActivationResult(succeeded: false, message: message)
        }

        let target = MatchedWindow(
            app: app,
            window: switchableWindow.axWindow,
            appWindowIndex: 0,
            executablePath: app.executableURL?.path,
            title: switchableWindow.title,
            document: nil,
            url: nil,
            identifier: nil,
            role: nil,
            subrole: nil,
            position: nil,
            size: nil,
            minimized: nil
        )

        return activateResolvedWindow(target, actionDescription: "window switcher")
    }

    private func matchingWindows(for matcher: WindowMatcher) -> [MatchedWindow] {
        enumerateWindows(detail: .matching(for: matcher), for: matcher).filter { window in
            matcher.matches(
                app: window.app,
                title: window.title,
                document: window.document,
                url: window.url,
                identifier: window.identifier,
                executablePath: window.executablePath
            )
        }
    }

    private func cachedMatch(for shortcut: LoadedShortcut) -> MatchedWindow? {
        guard let cachedTarget = cachedTargetsByShortcutID[shortcut.id] else {
            return nil
        }

        guard let app = cachedApplication(for: cachedTarget, matcher: shortcut.matcher) else {
            cachedTargetsByShortcutID.removeValue(forKey: shortcut.id)
            return nil
        }

        guard attributeExists(kAXRoleAttribute as CFString, on: cachedTarget.window) else {
            cachedTargetsByShortcutID.removeValue(forKey: shortcut.id)
            return nil
        }

        let detail = WindowEnumerationDetail.matching(for: shortcut.matcher)
        let snapshot = snapshotWindow(
            cachedTarget.window,
            app: app,
            appWindowIndex: cachedTarget.appWindowIndex,
            detail: detail
        )

        guard let snapshot else {
            cachedTargetsByShortcutID.removeValue(forKey: shortcut.id)
            return nil
        }

        guard shortcut.matcher.matches(
            app: snapshot.app,
            title: snapshot.title,
            document: snapshot.document,
            url: snapshot.url,
            identifier: snapshot.identifier,
            executablePath: snapshot.executablePath
        ) else {
            cachedTargetsByShortcutID.removeValue(forKey: shortcut.id)
            return nil
        }

        return snapshot
    }

    private func enumerateWindows(detail: WindowEnumerationDetail, for matcher: WindowMatcher? = nil) -> [MatchedWindow] {
        let applications = candidateApplications(for: matcher)

        var matches: [MatchedWindow] = []

        for app in applications {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            for (windowIndex, window) in windows(for: appElement).enumerated() {
                guard let matchedWindow = snapshotWindow(
                    window,
                    app: app,
                    appWindowIndex: windowIndex,
                    detail: detail
                ) else {
                    continue
                }

                matches.append(matchedWindow)
            }
        }

        return matches
    }

    private func snapshotWindow(
        _ window: AXUIElement,
        app: NSRunningApplication,
        appWindowIndex: Int,
        detail: WindowEnumerationDetail
    ) -> MatchedWindow? {
        if detail.requiresRolePresence && !attributeExists(kAXRoleAttribute as CFString, on: window) {
            return nil
        }

        let title = textAttribute(kAXTitleAttribute as CFString, on: window) ?? ""
        let executablePath = app.executableURL?.path
        let document = detail.needsDocument ? textAttribute(kAXDocumentAttribute as CFString, on: window) : nil
        let url = detail.needsURL ? textAttribute(kAXURLAttribute as CFString, on: window) : nil
        let identifier = detail.needsIdentifier ? textAttribute(kAXIdentifierAttribute as CFString, on: window) : nil
        let role = detail.needsRole ? textAttribute(kAXRoleAttribute as CFString, on: window) : nil
        let subrole = detail.needsSubrole ? textAttribute(kAXSubroleAttribute as CFString, on: window) : nil
        let position = detail.needsPosition ? pointAttribute(kAXPositionAttribute as CFString, on: window) : nil
        let size = detail.needsSize ? sizeAttribute(kAXSizeAttribute as CFString, on: window) : nil
        let minimized = detail.needsMinimized ? boolAttribute(kAXMinimizedAttribute as CFString, on: window) : nil

        return MatchedWindow(
            app: app,
            window: window,
            appWindowIndex: appWindowIndex,
            executablePath: executablePath,
            title: title,
            document: document,
            url: url,
            identifier: identifier,
            role: role,
            subrole: subrole,
            position: position,
            size: size,
            minimized: minimized
        )
    }

    private func candidateApplications(for matcher: WindowMatcher?) -> [NSRunningApplication] {
        let applications: [NSRunningApplication]

        if let bundleID = matcher?.bundleID {
            applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter {
                !$0.isTerminated && $0.activationPolicy != .prohibited
            }
        } else {
            applications = NSWorkspace.shared.runningApplications.filter {
                !$0.isTerminated && $0.activationPolicy != .prohibited
            }
        }

        guard let matcher else {
            return applications
        }

        return applications.filter { app in
            matcher.matchesApplication(app: app, executablePath: app.executableURL?.path)
        }
    }

    private func cachedApplication(
        for cachedTarget: CachedWindowTarget,
        matcher: WindowMatcher
    ) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: cachedTarget.pid) else {
            return nil
        }

        guard !app.isTerminated, app.activationPolicy != .prohibited else {
            return nil
        }

        return matcher.matchesApplication(app: app, executablePath: app.executableURL?.path) ? app : nil
    }

    private func windows(for appElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        guard status == .success else {
            return []
        }

        if let windows = value as? [AXUIElement] {
            return windows
        }

        if let array = value as? [Any] {
            return array.map { $0 as! AXUIElement }
        }

        return []
    }

    private static func focus(_ window: AXUIElement) {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private func activateResolvedWindow(_ target: MatchedWindow, for shortcut: LoadedShortcut) -> ActivationResult {
        activateResolvedWindow(target, actionDescription: "shortcut `\(shortcut.id)`")
    }

    private func activateResolvedWindow(_ target: MatchedWindow, actionDescription: String) -> ActivationResult {
        if target.app.isHidden {
            target.app.unhide()
        }

        setBoolAttribute(false, attribute: kAXMinimizedAttribute as CFString, on: target.window)
        target.app.activate(options: [.activateIgnoringOtherApps])
        Self.focus(target.window)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.focus(target.window)
        }

        let titlePart = target.title.isEmpty ? "untitled window" : "\"\(target.title)\""
        let message = "Activated \(titlePart) for \(actionDescription)."
        console.info(message)
        return ActivationResult(succeeded: true, message: message)
    }

    private func textAttribute(_ attribute: CFString, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard status == .success, let value else {
            return nil
        }

        if let string = value as? String {
            return string
        }

        if let url = value as? URL {
            return url.absoluteString
        }

        return nil
    }

    private func boolAttribute(_ attribute: CFString, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard status == .success, let value else {
            return nil
        }

        return value as? Bool
    }

    private func attributeExists(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute, &value) == .success
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

    private func setBoolAttribute(_ value: Bool, attribute: CFString, on element: AXUIElement) {
        let boolValue: CFBoolean = value ? kCFBooleanTrue : kCFBooleanFalse
        _ = AXUIElementSetAttributeValue(element, attribute, boolValue)
    }
}

private struct WindowEnumerationDetail {
    let needsDocument: Bool
    let needsURL: Bool
    let needsIdentifier: Bool
    let needsRole: Bool
    let needsSubrole: Bool
    let needsPosition: Bool
    let needsSize: Bool
    let needsMinimized: Bool
    let requiresRolePresence: Bool

    static func matching(for matcher: WindowMatcher) -> WindowEnumerationDetail {
        WindowEnumerationDetail(
            needsDocument: matcher.documentRegex != nil,
            needsURL: matcher.urlRegex != nil,
            needsIdentifier: matcher.identifierRegex != nil,
            needsRole: false,
            needsSubrole: false,
            needsPosition: false,
            needsSize: false,
            needsMinimized: false,
            requiresRolePresence: true
        )
    }

    static let verbose = WindowEnumerationDetail(
        needsDocument: true,
        needsURL: true,
        needsIdentifier: true,
        needsRole: true,
        needsSubrole: true,
        needsPosition: true,
        needsSize: true,
        needsMinimized: true,
        requiresRolePresence: false
    )
}

private struct CachedWindowTarget {
    let pid: pid_t
    let window: AXUIElement
    let appWindowIndex: Int
}

private struct MatchedWindow {
    let app: NSRunningApplication
    let window: AXUIElement
    let appWindowIndex: Int
    let executablePath: String?
    let title: String
    let document: String?
    let url: String?
    let identifier: String?
    let role: String?
    let subrole: String?
    let position: CGPoint?
    let size: CGSize?
    let minimized: Bool?
}
