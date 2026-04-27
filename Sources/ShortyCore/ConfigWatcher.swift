import Foundation

public final class ConfigWatcher: NSObject {
    public typealias ChangeHandler = () -> Void

    private let url: URL
    private let changeHandler: ChangeHandler
    private var timer: Timer?
    private var lastKnownVersion: FileVersion

    public init(url: URL, changeHandler: @escaping ChangeHandler) {
        self.url = url
        self.changeHandler = changeHandler
        self.lastKnownVersion = FileVersion(url: url)
        super.init()
    }

    public func start() {
        stop()
        lastKnownVersion = FileVersion(url: url)

        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )

        timer?.tolerance = 0.25
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let currentVersion = FileVersion(url: url)
        guard currentVersion != lastKnownVersion else {
            return
        }

        lastKnownVersion = currentVersion
        changeHandler()
    }

    @objc
    private func timerDidFire() {
        poll()
    }
}

private enum FileVersion: Equatable {
    case missing
    case modified(Date)

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

        if let date = values?.contentModificationDate {
            self = .modified(date)
        } else {
            self = .missing
        }
    }
}
