import CoreGraphics
import XCTest
@testable import ShortyCore

final class WindowGeometryPlannerTests: XCTestCase {
    func testHalfFramesUseVisibleScreenHalves() {
        let screen = CGRect(x: 100, y: 50, width: 1000, height: 800)

        XCTAssertEqual(
            WindowGeometryPlanner.halfFrame(on: screen, half: .left),
            CGRect(x: 100, y: 50, width: 500, height: 800)
        )
        XCTAssertEqual(
            WindowGeometryPlanner.halfFrame(on: screen, half: .right),
            CGRect(x: 600, y: 50, width: 500, height: 800)
        )
    }

    func testHalfCycleMovesToCurrentHalfWhenWindowIsNotAlreadyThere() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1200, height: 900),
        ]
        let window = CGRect(x: 1200, y: 100, width: 600, height: 500)

        XCTAssertEqual(
            WindowGeometryPlanner.halfCycleFrame(for: window, screens: screens, direction: .left),
            CGRect(x: 1000, y: 0, width: 600, height: 900)
        )
    }

    func testHalfCycleMovesLeftToPreviousMonitorRightHalf() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1200, height: 900),
        ]
        let window = CGRect(x: 1000, y: 0, width: 600, height: 900)

        XCTAssertEqual(
            WindowGeometryPlanner.halfCycleFrame(for: window, screens: screens, direction: .left),
            CGRect(x: 500, y: 0, width: 500, height: 800)
        )
    }

    func testHalfCycleWrapsLeftmostLeftHalfToRightmostRightHalf() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1200, height: 900),
        ]
        let window = CGRect(x: 0, y: 0, width: 500, height: 800)

        XCTAssertEqual(
            WindowGeometryPlanner.halfCycleFrame(for: window, screens: screens, direction: .left),
            CGRect(x: 1600, y: 0, width: 600, height: 900)
        )
    }

    func testHalfCycleWrapsRightmostRightHalfToLeftmostLeftHalf() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1200, height: 900),
        ]
        let window = CGRect(x: 1600, y: 0, width: 600, height: 900)

        XCTAssertEqual(
            WindowGeometryPlanner.halfCycleFrame(for: window, screens: screens, direction: .right),
            CGRect(x: 0, y: 0, width: 500, height: 800)
        )
    }

    func testApproximatelyUsesToleranceForHalfDetection() {
        let target = CGRect(x: 0, y: 0, width: 500, height: 800)

        XCTAssertTrue(
            WindowGeometryPlanner.isApproximately(
                CGRect(x: 8, y: -4, width: 492, height: 808),
                target,
                tolerance: 12
            )
        )
        XCTAssertFalse(
            WindowGeometryPlanner.isApproximately(
                CGRect(x: 20, y: 0, width: 500, height: 800),
                target,
                tolerance: 12
            )
        )
    }

    func testMaximizeFrameUsesCurrentScreen() {
        let screen = CGRect(x: 100, y: 50, width: 1000, height: 800)

        XCTAssertEqual(WindowGeometryPlanner.maximizeFrame(on: screen), screen)
    }

    func testAccessibilityFrameConvertsAppKitVisibleFrameToTopLeftCoordinates() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let visibleFrame = CGRect(x: 0, y: 60, width: 1000, height: 710)
        let displayBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

        XCTAssertEqual(
            WindowGeometryPlanner.accessibilityFrame(
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                displayBounds: displayBounds
            ),
            CGRect(x: 0, y: 30, width: 1000, height: 710)
        )
    }

    func testAccessibilityFrameConvertsOffsetDisplay() {
        let screenFrame = CGRect(x: 1000, y: -100, width: 1200, height: 900)
        let visibleFrame = CGRect(x: 1000, y: -50, width: 1200, height: 830)
        let displayBounds = CGRect(x: 1000, y: 0, width: 1200, height: 900)

        XCTAssertEqual(
            WindowGeometryPlanner.accessibilityFrame(
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                displayBounds: displayBounds
            ),
            CGRect(x: 1000, y: 20, width: 1200, height: 830)
        )
    }

    func testMonitorMovePreservesProportionalGeometry() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 2000, height: 1000),
        ]
        let window = CGRect(x: 250, y: 200, width: 500, height: 400)

        XCTAssertEqual(
            WindowGeometryPlanner.monitorMoveFrame(for: window, screens: screens, direction: .right),
            CGRect(x: 1500, y: 250, width: 1000, height: 500)
        )
    }

    func testScreenSelectionUsesCenterBeforeIntersectionFallback() {
        let screens = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ]

        XCTAssertEqual(
            WindowGeometryPlanner.screenIndex(
                containing: CGRect(x: 120, y: 20, width: 40, height: 40),
                screens: screens
            ),
            1
        )
    }

    func testScreenSelectionFallsBackToLargestIntersection() {
        let screens = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 200, y: 0, width: 100, height: 100),
        ]

        XCTAssertEqual(
            WindowGeometryPlanner.screenIndex(
                containing: CGRect(x: 50, y: 90, width: 40, height: 30),
                screens: screens
            ),
            0
        )
    }
}
