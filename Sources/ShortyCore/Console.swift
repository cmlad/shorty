import Foundation
import OSLog

public final class Console {
    private let logger: Logger

    public init(
        subsystem: String = "dev.shorty.Shorty",
        category: String = "Shorty"
    ) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    public func error(_ message: String) {
        write(level: "ERROR", message: message)
    }

    private func write(level: String, message: String) {
        let line = "[Shorty] [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        FileHandle.standardError.write(data)

        switch level {
        case "ERROR":
            logger.error("\(message, privacy: .public)")
        default:
            logger.info("\(message, privacy: .public)")
        }
    }
}
