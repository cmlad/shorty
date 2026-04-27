import XCTest
@testable import ShortyCore

final class LaunchOptionsTests: XCTestCase {
    func testParsesListWindowsMode() throws {
        let options = try LaunchOptions(arguments: ["Shorty", "--list-windows"])
        XCTAssertEqual(options.mode, .listWindows)
    }

    func testParsesValidateMode() throws {
        let options = try LaunchOptions(arguments: ["Shorty", "--validate-config"])
        XCTAssertEqual(options.mode, .validateConfig)
    }

    func testParsesVerboseListMode() throws {
        let options = try LaunchOptions(arguments: ["Shorty", "--list-windows", "--verbose"])
        XCTAssertEqual(options.mode, .listWindows)
        XCTAssertEqual(options.windowListFormat, .verbose)
    }
}
