import XCTest
@testable import ShortyCore

final class WindowSwitcherSessionTests: XCTestCase {
    func testInitialSelectionSkipsMostRecentWindowWhenPossible() {
        let session = WindowSwitcherSessionState(candidateCount: 3)

        XCTAssertEqual(session.selectedIndex, 1)
    }

    func testInitialSelectionUsesFirstWindowWhenOnlyOneCandidateExists() {
        let session = WindowSwitcherSessionState(candidateCount: 1)

        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testAdvanceWrapsSelection() {
        let session = WindowSwitcherSessionState(candidateCount: 3)

        session.advance()
        XCTAssertEqual(session.selectedIndex, 2)

        session.advance()
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testInitialReverseSelectionUsesLastWindowWhenPossible() {
        let session = WindowSwitcherSessionState(candidateCount: 3, initialDirection: .reverse)

        XCTAssertEqual(session.selectedIndex, 2)
    }

    func testReverseAdvanceWrapsSelection() {
        let session = WindowSwitcherSessionState(candidateCount: 3)

        session.advance(.reverse)
        XCTAssertEqual(session.selectedIndex, 0)

        session.advance(.reverse)
        XCTAssertEqual(session.selectedIndex, 2)
    }
}
