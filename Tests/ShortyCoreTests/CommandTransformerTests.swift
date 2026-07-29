import XCTest
@testable import ShortyCore

final class CommandTransformerTests: XCTestCase {
    func testStructuredPrefixRendersRemainingStringAndRegexPlaceholders() {
        let transformer = CommandTransformer(
            name: "Bytes",
            parts: [
                .regex(name: "bytes", pattern: #"\d+"#),
                .string("to"),
                .regex(name: "kb/mb/gb/tb", pattern: #"kb|mb|gb|tb"#),
            ]
        ) { _, _ in
            "converted"
        }

        let results = CommandTransformerEngine.evaluate("1223 t", transformers: [transformer])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].displayText, "1223 to kb/mb/gb/tb")
        XCTAssertEqual(results[0].segments, [
            CommandDisplaySegment(text: "1223 t", kind: .matched),
            CommandDisplaySegment(text: "o kb/mb/gb/tb", kind: .placeholder),
        ])
        XCTAssertNil(results[0].resultText)
    }

    func testStructuredFullMatchRunsTransformerWithCaptures() {
        let transformer = CommandTransformer(
            name: "Bytes",
            parts: [
                .regex(name: "bytes", pattern: #"\d+"#),
                .string("to"),
                .regex(name: "unit", pattern: #"kb|mb|gb|tb"#),
            ]
        ) { captures, _ in
            "\(captures["bytes"] ?? "") \(captures["unit"] ?? "")"
        }

        let results = CommandTransformerEngine.evaluate("1223 to mb", transformers: [transformer])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].displayText, "1223 to mb")
        XCTAssertEqual(results[0].resultText, "1223 mb")
    }

    func testStringPartsAdvanceOnlyAfterFullMatch() {
        let transformer = CommandTransformer(
            name: "Bytes",
            parts: [
                .regex(name: "bytes", pattern: #"\d+"#),
                .string("to"),
                .regex(name: "unit", pattern: #"kb|mb"#),
            ]
        ) { _, _ in
            "converted"
        }

        XCTAssertTrue(CommandTransformerEngine.evaluate("1223 t mb", transformers: [transformer]).isEmpty)
    }

    func testRegexPartsRequireFullTokenMatch() {
        let transformer = CommandTransformer(
            name: "Epoch Seconds",
            parts: [.regex(name: "seconds", pattern: #"\d{10}"#)]
        ) { _, _ in
            "date"
        }

        XCTAssertTrue(CommandTransformerEngine.evaluate("178", transformers: [transformer]).isEmpty)
    }

    func testInvalidExtraInputProducesNoMatch() {
        let transformer = CommandTransformer(
            name: "Epoch Seconds",
            parts: [.regex(name: "seconds", pattern: #"\d{10}"#)]
        ) { _, _ in
            "date"
        }

        XCTAssertTrue(CommandTransformerEngine.evaluate("1782275959 extra", transformers: [transformer]).isEmpty)
    }

    func testRunsTransformerWhenAllRegexPartsMatchBeforeAllStringsAreEntered() {
        let transformer = CommandTransformer(
            name: "Bytes",
            parts: [
                .regex(name: "bytes", pattern: #"\d+"#),
                .string("bytes"),
            ]
        ) { captures, _ in
            captures["bytes"] ?? ""
        }

        let results = CommandTransformerEngine.evaluate("1223 b", transformers: [transformer])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].displayText, "1223 bytes")
        XCTAssertEqual(results[0].resultText, "1223")
    }

    func testEpochSecondsFormatsUTCAndSanFranciscoOnSeparateLinesWithRelativeAge() {
        let now = Date(timeIntervalSince1970: 90_061)
        let results = CommandTransformerEngine.evaluate("0000000000", now: now)

        let result = results.first { $0.transformerName == "Epoch Seconds" }?.resultText
        XCTAssertEqual(
            result,
            """
            UTC: 1970-01-01 00:00:00 GMT (1d 1h 1m 1s ago)
            San Francisco: 1969-12-31 16:00:00 PST (1d 1h 1m 1s ago)
            """
        )
    }

    func testEpochMillisecondsFormatsUTCAndSanFranciscoOnSeparateLinesWithRelativeAge() {
        let now = Date(timeIntervalSince1970: 90_061)
        let results = CommandTransformerEngine.evaluate("00000000000000", now: now)

        let result = results.first { $0.transformerName == "Epoch Milliseconds" }?.resultText
        XCTAssertEqual(
            result,
            """
            UTC: 1970-01-01 00:00:00 GMT (1d 1h 1m 1s ago)
            San Francisco: 1969-12-31 16:00:00 PST (1d 1h 1m 1s ago)
            """
        )
    }

    func testByteConversionOutputsEveryOtherUnit() {
        let results = CommandTransformerEngine.evaluate("1024 bytes")

        let result = results.first { $0.transformerName == "Disk Size Units" }?.resultText
        XCTAssertEqual(
            result,
            """
            kb: 1
            mb: 0.000977
            gb: 0.000001
            tb: 0
            """
        )
    }

    func testByteConversionExcludesEnteredUnit() {
        let results = CommandTransformerEngine.evaluate("1 mb")

        let result = results.first { $0.transformerName == "Disk Size Units" }?.resultText
        XCTAssertEqual(
            result,
            """
            bytes: 1048576
            kb: 1024
            gb: 0.000977
            tb: 0.000001
            """
        )
    }

    func testByteConversionTreatsBAsBytesAlias() {
        let results = CommandTransformerEngine.evaluate("1024 b")

        let result = results.first { $0.transformerName == "Disk Size Units" }?.resultText
        XCTAssertEqual(
            result,
            """
            kb: 1
            mb: 0.000977
            gb: 0.000001
            tb: 0
            """
        )
    }

    func testByteConversionDoesNotMatchIncompleteUnitRegex() {
        let results = CommandTransformerEngine.evaluate("1024 m")

        XCTAssertFalse(results.contains { $0.transformerName == "Disk Size Units" })
    }

    func testCurrentTimeCommandsUseInjectedDate() {
        let now = Date(timeIntervalSince1970: 0)

        let results = CommandTransformerEngine.evaluate("utc time", now: now)

        XCTAssertEqual(results.first?.transformerName, "UTC Time")
        XCTAssertEqual(results.first?.resultText, "1970-01-01 00:00:00 GMT")
    }

    func testCurrentTimePrefixShowsRemainingStringAndResult() {
        let now = Date(timeIntervalSince1970: 0)
        let results = CommandTransformerEngine.evaluate("utc t", now: now)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].transformerName, "UTC Time")
        XCTAssertEqual(results[0].displayText, "utc time")
        XCTAssertEqual(results[0].segments, [
            CommandDisplaySegment(text: "utc t", kind: .matched),
            CommandDisplaySegment(text: "ime", kind: .placeholder),
        ])
        XCTAssertEqual(results[0].resultText, "1970-01-01 00:00:00 GMT")
    }

    func testCurrentTimeStringPrefixRunsTransformer() {
        let now = Date(timeIntervalSince1970: 0)

        let results = CommandTransformerEngine.evaluate("u", now: now)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].transformerName, "UTC Time")
        XCTAssertEqual(results[0].displayText, "utc time")
        XCTAssertEqual(results[0].resultText, "1970-01-01 00:00:00 GMT")
    }

    func testCurrentTimeSupportsRequestedZones() {
        let now = Date(timeIntervalSince1970: 0)
        let zones = ["utc", "et", "cet", "turkey", "dubai", "korea", "japan"]

        for zone in zones {
            let results = CommandTransformerEngine.evaluate("\(zone) time", now: now)
            XCTAssertEqual(results.count, 1, "Expected \(zone) to match")
            XCTAssertNotNil(results[0].resultText)
        }
    }
}
