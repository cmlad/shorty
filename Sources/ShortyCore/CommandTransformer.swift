import Foundation

public enum CommandPatternPart: Equatable, Sendable {
    case regex(name: String, pattern: String)
    case string(String)
}

public enum CommandDisplaySegmentKind: Equatable, Sendable {
    case matched
    case placeholder
}

public struct CommandDisplaySegment: Equatable, Sendable {
    public let text: String
    public let kind: CommandDisplaySegmentKind

    public init(text: String, kind: CommandDisplaySegmentKind) {
        self.text = text
        self.kind = kind
    }
}

public struct CommandTransformerEvaluation: Equatable, Sendable {
    public let transformerName: String
    public let segments: [CommandDisplaySegment]
    public let resultText: String?

    public var isComplete: Bool {
        resultText != nil
    }

    public var displayText: String {
        segments.map(\.text).joined()
    }

    public init(
        transformerName: String,
        segments: [CommandDisplaySegment],
        resultText: String?
    ) {
        self.transformerName = transformerName
        self.segments = segments
        self.resultText = resultText
    }
}

public struct CommandTransformer: Sendable {
    public typealias Transform = @Sendable ([String: String], Date) -> String

    public let name: String
    public let parts: [CommandPatternPart]
    public let transform: Transform

    public init(
        name: String,
        parts: [CommandPatternPart],
        transform: @escaping Transform
    ) {
        self.name = name
        self.parts = parts
        self.transform = transform
    }
}

public enum CommandTransformerEngine {
    public static let defaultTransformers: [CommandTransformer] = [
        CommandTransformer(
            name: "Epoch Seconds",
            parts: [.regex(name: "seconds", pattern: #"\d{10}"#)]
        ) { captures, now in
            guard let rawValue = captures["seconds"], let seconds = TimeInterval(rawValue) else {
                return "Invalid epoch seconds"
            }

            return formatUTCAndSanFrancisco(Date(timeIntervalSince1970: seconds), now: now)
        },

        CommandTransformer(
            name: "Epoch Milliseconds",
            parts: [.regex(name: "milliseconds", pattern: #"\d{14}"#)]
        ) { captures, now in
            guard let rawValue = captures["milliseconds"], let milliseconds = TimeInterval(rawValue) else {
                return "Invalid epoch milliseconds"
            }

            return formatUTCAndSanFrancisco(Date(timeIntervalSince1970: milliseconds / 1_000), now: now)
        },

        CommandTransformer(
            name: "Disk Size Units",
            parts: [
                .regex(name: "amount", pattern: #"\d+(?:\.\d+)?"#),
                .regex(name: "unit", pattern: #"b|bytes|kb|mb|gb|tb"#),
            ]
        ) { captures, _ in
            guard let rawAmount = captures["amount"],
                  let amount = Double(rawAmount),
                  let rawUnit = captures["unit"]?.lowercased(),
                  let inputUnit = ByteUnit.parse(rawUnit) else {
                return "Invalid byte conversion"
            }

            return formatByteConversions(amount: amount, inputUnit: inputUnit)
        },
    ] + timeTransformers()

    public static func evaluate(
        _ input: String,
        transformers: [CommandTransformer] = defaultTransformers,
        now: Date = Date()
    ) -> [CommandTransformerEvaluation] {
        let normalizedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInput.isEmpty else {
            return []
        }

        return transformers.compactMap { transformer in
            evaluate(normalizedInput, transformer: transformer, now: now)
        }
    }

    private static func evaluate(
        _ input: String,
        transformer: CommandTransformer,
        now: Date
    ) -> CommandTransformerEvaluation? {
        var segments: [CommandDisplaySegment] = []
        var captures: [String: String] = [:]
        var matchedRegexPartIndices = Set<Int>()
        var currentIndex = input.startIndex

        for partIndex in transformer.parts.indices {
            let part = transformer.parts[partIndex]
            currentIndex = skipWhitespace(in: input, from: currentIndex)

            guard currentIndex < input.endIndex else {
                appendPlaceholders(
                    for: transformer.parts,
                    startingAt: partIndex,
                    to: &segments
                )
                return CommandTransformerEvaluation(
                    transformerName: transformer.name,
                    segments: segments,
                    resultText: resultText(
                        for: transformer,
                        captures: captures,
                        matchedRegexPartIndices: matchedRegexPartIndices,
                        now: now
                    )
                )
            }

            switch part {
            case let .regex(name, pattern):
                let tokenEnd = nextWhitespace(in: input, from: currentIndex)
                let token = String(input[currentIndex..<tokenEnd])
                guard matchesFullToken(token, pattern: pattern) else {
                    return nil
                }

                append(text: token, kind: .matched, separated: !segments.isEmpty, to: &segments)
                captures[name] = token
                matchedRegexPartIndices.insert(partIndex)
                currentIndex = tokenEnd

            case let .string(value):
                let lowercasedValue = value.lowercased()
                let remainingInput = String(input[currentIndex...])
                let lowercasedRemainingInput = remainingInput.lowercased()

                if lowercasedRemainingInput.hasPrefix(lowercasedValue) {
                    append(text: value, kind: .matched, separated: !segments.isEmpty, to: &segments)
                    currentIndex = input.index(currentIndex, offsetBy: value.count)
                    continue
                }

                guard lowercasedValue.hasPrefix(lowercasedRemainingInput) else {
                    return nil
                }

                append(text: remainingInput, kind: .matched, separated: !segments.isEmpty, to: &segments)
                let suffixStart = value.index(value.startIndex, offsetBy: remainingInput.count)
                if suffixStart < value.endIndex {
                    appendSegment(String(value[suffixStart...]), kind: .placeholder, to: &segments)
                }
                appendPlaceholders(
                    for: transformer.parts,
                    startingAt: transformer.parts.index(after: partIndex),
                    to: &segments
                )
                return CommandTransformerEvaluation(
                    transformerName: transformer.name,
                    segments: segments,
                    resultText: resultText(
                        for: transformer,
                        captures: captures,
                        matchedRegexPartIndices: matchedRegexPartIndices,
                        now: now
                    )
                )
            }
        }

        currentIndex = skipWhitespace(in: input, from: currentIndex)
        guard currentIndex == input.endIndex else {
            return nil
        }

        return CommandTransformerEvaluation(
            transformerName: transformer.name,
            segments: segments,
            resultText: resultText(
                for: transformer,
                captures: captures,
                matchedRegexPartIndices: matchedRegexPartIndices,
                now: now
            )
        )
    }

    private static func resultText(
        for transformer: CommandTransformer,
        captures: [String: String],
        matchedRegexPartIndices: Set<Int>,
        now: Date
    ) -> String? {
        let allRegexPartsMatched = transformer.parts.enumerated().allSatisfy { index, part in
            switch part {
            case .regex:
                return matchedRegexPartIndices.contains(index)
            case .string:
                return true
            }
        }

        guard allRegexPartsMatched else {
            return nil
        }

        return transformer.transform(captures, now)
    }

    private static func skipWhitespace(in input: String, from startIndex: String.Index) -> String.Index {
        var index = startIndex
        while index < input.endIndex, input[index].isWhitespace {
            index = input.index(after: index)
        }

        return index
    }

    private static func nextWhitespace(in input: String, from startIndex: String.Index) -> String.Index {
        var index = startIndex
        while index < input.endIndex, !input[index].isWhitespace {
            index = input.index(after: index)
        }

        return index
    }

    private static func matchesFullToken(_ token: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "^(?:\(pattern))$",
            options: [.caseInsensitive]
        ) else {
            return false
        }

        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        return regex.firstMatch(in: token, options: [], range: range) != nil
    }

    private static func appendPlaceholders(
        for parts: [CommandPatternPart],
        startingAt startIndex: Int,
        to segments: inout [CommandDisplaySegment]
    ) {
        guard startIndex < parts.endIndex else {
            return
        }

        for part in parts[startIndex...] {
            append(text: placeholderText(for: part), kind: .placeholder, separated: !segments.isEmpty, to: &segments)
        }
    }

    private static func placeholderText(for part: CommandPatternPart) -> String {
        switch part {
        case let .regex(name, _):
            return name
        case let .string(value):
            return value
        }
    }

    private static func append(
        text: String,
        kind: CommandDisplaySegmentKind,
        separated: Bool,
        to segments: inout [CommandDisplaySegment]
    ) {
        if separated {
            appendSegment(" ", kind: kind, to: &segments)
        }

        appendSegment(text, kind: kind, to: &segments)
    }

    private static func appendSegment(
        _ text: String,
        kind: CommandDisplaySegmentKind,
        to segments: inout [CommandDisplaySegment]
    ) {
        guard !text.isEmpty else {
            return
        }

        if let last = segments.last, last.kind == kind {
            segments[segments.index(before: segments.endIndex)] = CommandDisplaySegment(
                text: last.text + text,
                kind: kind
            )
            return
        }

        segments.append(CommandDisplaySegment(text: text, kind: kind))
    }

    private static func timeTransformers() -> [CommandTransformer] {
        [
            timeTransformer(command: "utc time", name: "UTC Time", timeZone: TimeZone(secondsFromGMT: 0)!),
            timeTransformer(command: "et time", name: "ET Time", timeZone: TimeZone(identifier: "America/New_York")!),
            timeTransformer(command: "cet time", name: "CET Time", timeZone: TimeZone(identifier: "Europe/Paris")!),
            timeTransformer(command: "turkey time", name: "Turkey Time", timeZone: TimeZone(identifier: "Europe/Istanbul")!),
            timeTransformer(command: "dubai time", name: "Dubai Time", timeZone: TimeZone(identifier: "Asia/Dubai")!),
            timeTransformer(command: "korea time", name: "Korea Time", timeZone: TimeZone(identifier: "Asia/Seoul")!),
            timeTransformer(command: "japan time", name: "Japan Time", timeZone: TimeZone(identifier: "Asia/Tokyo")!),
        ]
    }

    private static func timeTransformer(command: String, name: String, timeZone: TimeZone) -> CommandTransformer {
        CommandTransformer(
            name: name,
            parts: [.string(command)]
        ) { _, now in
            format(now, in: timeZone)
        }
    }

    private static func formatUTCAndSanFrancisco(_ date: Date, now: Date) -> String {
        let utc = TimeZone(secondsFromGMT: 0)!
        let sanFrancisco = TimeZone(identifier: "America/Los_Angeles")!
        let relative = relativeDescription(from: date, to: now)
        return """
        UTC: \(format(date, in: utc)) (\(relative))
        San Francisco: \(format(date, in: sanFrancisco)) (\(relative))
        """
    }

    private static func format(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return formatter.string(from: date)
    }

    private static func relativeDescription(from date: Date, to now: Date) -> String {
        let delta = Int(now.timeIntervalSince(date).rounded())
        let direction = delta >= 0 ? "ago" : "from now"
        let totalSeconds = abs(delta)
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
        }
        if days > 0 || hours > 0 {
            parts.append("\(hours)h")
        }
        if days > 0 || hours > 0 || minutes > 0 {
            parts.append("\(minutes)m")
        }
        parts.append("\(seconds)s")

        return "\(parts.joined(separator: " ")) \(direction)"
    }

    private enum ByteUnit: String, CaseIterable {
        case bytes
        case kb
        case mb
        case gb
        case tb

        static func parse(_ value: String) -> ByteUnit? {
            if value == "b" {
                return .bytes
            }

            return ByteUnit(rawValue: value)
        }

        var multiplier: Double {
            switch self {
            case .bytes:
                return 1
            case .kb:
                return 1_024
            case .mb:
                return 1_024 * 1_024
            case .gb:
                return 1_024 * 1_024 * 1_024
            case .tb:
                return 1_024 * 1_024 * 1_024 * 1_024
            }
        }
    }

    private static func formatByteConversions(amount: Double, inputUnit: ByteUnit) -> String {
        let bytes = amount * inputUnit.multiplier
        return ByteUnit.allCases
            .filter { $0 != inputUnit }
            .map { unit in
                "\(unit.rawValue): \(formatByteValue(bytes / unit.multiplier))"
            }
            .joined(separator: "\n")
    }

    private static func formatByteValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
