import CoreGraphics
import Foundation

public enum WindowHalf: Sendable {
    case left
    case right
}

public enum WindowMoveDirection: Sendable {
    case left
    case right
}

public enum WindowGeometryPlanner {
    public static let defaultTolerance: CGFloat = 12

    public static func halfFrame(on screen: CGRect, half: WindowHalf) -> CGRect {
        let screen = screen.standardized
        let width = screen.width / 2

        switch half {
        case .left:
            return CGRect(x: screen.minX, y: screen.minY, width: width, height: screen.height)
        case .right:
            return CGRect(x: screen.midX, y: screen.minY, width: width, height: screen.height)
        }
    }

    public static func maximizeFrame(on screen: CGRect) -> CGRect {
        screen.standardized
    }

    public static func accessibilityFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        displayBounds: CGRect
    ) -> CGRect {
        let screenFrame = screenFrame.standardized
        let visibleFrame = visibleFrame.standardized
        let displayBounds = displayBounds.standardized

        return CGRect(
            x: displayBounds.minX + (visibleFrame.minX - screenFrame.minX),
            y: displayBounds.minY + (screenFrame.maxY - visibleFrame.maxY),
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    public static func halfCycleFrame(
        for windowFrame: CGRect,
        screens: [CGRect],
        direction: WindowMoveDirection,
        tolerance: CGFloat = defaultTolerance
    ) -> CGRect? {
        let screens = orderedScreens(screens)
        guard let currentIndex = screenIndex(containing: windowFrame, screens: screens) else {
            return nil
        }

        let currentScreen = screens[currentIndex]
        let targetHalf: WindowHalf = direction == .left ? .left : .right
        let targetFrame = halfFrame(on: currentScreen, half: targetHalf)

        guard isApproximately(windowFrame, targetFrame, tolerance: tolerance) ||
            isApproximatelyAnchored(windowFrame, to: targetHalf, on: currentScreen, tolerance: tolerance) else {
            return targetFrame
        }

        switch direction {
        case .left:
            let destinationIndex = currentIndex > 0 ? currentIndex - 1 : screens.count - 1
            return halfFrame(on: screens[destinationIndex], half: .right)
        case .right:
            let destinationIndex = currentIndex < screens.count - 1 ? currentIndex + 1 : 0
            return halfFrame(on: screens[destinationIndex], half: .left)
        }
    }

    public static func monitorMoveFrame(
        for windowFrame: CGRect,
        screens: [CGRect],
        direction: WindowMoveDirection
    ) -> CGRect? {
        let screens = orderedScreens(screens)
        guard screens.count > 1, let currentIndex = screenIndex(containing: windowFrame, screens: screens) else {
            return nil
        }

        let destinationIndex: Int
        switch direction {
        case .left:
            destinationIndex = currentIndex > 0 ? currentIndex - 1 : screens.count - 1
        case .right:
            destinationIndex = currentIndex < screens.count - 1 ? currentIndex + 1 : 0
        }

        return proportionalFrame(
            windowFrame.standardized,
            from: screens[currentIndex],
            to: screens[destinationIndex]
        )
    }

    public static func screenIndex(containing windowFrame: CGRect, screens: [CGRect]) -> Int? {
        let windowFrame = windowFrame.standardized
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)

        if let centerIndex = screens.firstIndex(where: { $0.standardized.contains(center) }) {
            return centerIndex
        }

        return screens
            .enumerated()
            .map { index, screen in
                (index: index, area: intersectionArea(windowFrame, screen.standardized))
            }
            .filter { $0.area > 0 }
            .max { $0.area < $1.area }?
            .index
    }

    public static func orderedScreens(_ screens: [CGRect]) -> [CGRect] {
        screens.map(\.standardized).sorted { first, second in
            if first.minX == second.minX {
                return first.minY < second.minY
            }

            return first.minX < second.minX
        }
    }

    public static func isApproximately(
        _ frame: CGRect,
        _ target: CGRect,
        tolerance: CGFloat = defaultTolerance
    ) -> Bool {
        let frame = frame.standardized
        let target = target.standardized

        return abs(frame.minX - target.minX) <= tolerance &&
            abs(frame.minY - target.minY) <= tolerance &&
            abs(frame.width - target.width) <= tolerance &&
            abs(frame.height - target.height) <= tolerance
    }

    public static func isApproximately(
        _ point: CGPoint,
        _ target: CGPoint,
        tolerance: CGFloat = defaultTolerance
    ) -> Bool {
        abs(point.x - target.x) <= tolerance &&
            abs(point.y - target.y) <= tolerance
    }

    public static func fittingOrigin(
        for targetFrame: CGRect,
        actualSize: CGSize,
        screens: [CGRect]
    ) -> CGPoint {
        let screens = orderedScreens(screens)
        guard let screenIndex = screenIndex(containing: targetFrame, screens: screens) else {
            return targetFrame.standardized.origin
        }

        let targetFrame = targetFrame.standardized
        let screen = screens[screenIndex]

        return CGPoint(
            x: clamp(
                targetFrame.minX,
                min: screen.minX,
                max: screen.maxX - actualSize.width
            ),
            y: clamp(
                targetFrame.minY,
                min: screen.minY,
                max: screen.maxY - actualSize.height
            )
        )
    }

    private static func proportionalFrame(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let source = source.standardized
        let destination = destination.standardized

        let widthRatio = source.width == 0 ? 1 : frame.width / source.width
        let heightRatio = source.height == 0 ? 1 : frame.height / source.height
        let xRatio = source.width == 0 ? 0 : (frame.minX - source.minX) / source.width
        let yRatio = source.height == 0 ? 0 : (frame.minY - source.minY) / source.height

        let width = min(destination.width, destination.width * widthRatio)
        let height = min(destination.height, destination.height * heightRatio)
        let x = clamp(
            destination.minX + destination.width * xRatio,
            min: destination.minX,
            max: destination.maxX - width
        )
        let y = clamp(
            destination.minY + destination.height * yRatio,
            min: destination.minY,
            max: destination.maxY - height
        )

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func isApproximatelyAnchored(
        _ frame: CGRect,
        to half: WindowHalf,
        on screen: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        let frame = frame.standardized
        let screen = screen.standardized
        let target = halfFrame(on: screen, half: half)

        guard frame.width > target.width + tolerance,
              frame.width < screen.width - tolerance,
              abs(frame.minY - screen.minY) <= tolerance,
              abs(frame.height - screen.height) <= tolerance else {
            return false
        }

        switch half {
        case .left:
            return abs(frame.minX - screen.minX) <= tolerance
        case .right:
            return abs(frame.maxX - screen.maxX) <= tolerance
        }
    }

    private static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }

        return Swift.min(Swift.max(value, minimum), maximum)
    }
}
