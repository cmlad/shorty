import Foundation

public final class Console {
    public init() {}

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
    }
}
