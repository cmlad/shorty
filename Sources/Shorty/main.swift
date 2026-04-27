import AppKit
import ShortyCore

let console = Console()

do {
    let options = try LaunchOptions(arguments: CommandLine.arguments)

    switch options.mode {
    case .help:
        print(LaunchOptions.usage)
        exit(0)

    case .validateConfig:
        _ = try ConfigurationLoader.load(from: options.configURL)
        print("Config is valid: \(options.configURL.path)")
        exit(0)

    case .listWindows:
        guard WindowActivator.requestAccessibilityIfNeeded() else {
            console.error("Accessibility permission is required to list windows.")
            exit(1)
        }

        let activator = WindowActivator(console: console)
        let windows = activator.listWindows()

        if options.windowListFormat == .verbose {
            for (index, window) in windows.enumerated() {
                if index > 0 {
                    print("")
                }

                print("app: \(window.appName)")
                print("bundleId: \(window.bundleID ?? "<no bundle id>")")
                print("pid: \(window.pid)")
                print("appWindowIndex: \(window.appWindowIndex)")
                if let executablePath = window.executablePath {
                    print("executablePath: \(executablePath)")
                }
                print("title: \(window.title.isEmpty ? "<untitled>" : window.title)")

                if let document = window.document {
                    print("document: \(document)")
                }

                if let url = window.url {
                    print("url: \(url)")
                }

                if let identifier = window.identifier {
                    print("identifier: \(identifier)")
                }

                if let role = window.role {
                    print("role: \(role)")
                }

                if let subrole = window.subrole {
                    print("subrole: \(subrole)")
                }

                if let minimized = window.minimized {
                    print("minimized: \(minimized)")
                }

                if let position = window.position {
                    print("position: x=\(Int(position.x)) y=\(Int(position.y))")
                }

                if let size = window.size {
                    print("size: width=\(Int(size.width)) height=\(Int(size.height))")
                }
            }
        } else {
            for window in windows {
                let bundleID = window.bundleID ?? "<no bundle id>"
                let title = window.title.isEmpty ? "<untitled>" : window.title
                let extra = window.document ?? window.url ?? window.identifier ?? window.executablePath

                if let extra, !extra.isEmpty {
                    print("\(bundleID)\t\(title)\t\(extra)")
                } else {
                    print("\(bundleID)\t\(title)")
                }
            }
        }

        exit(0)

    case .run:
        let controller = try ShortyController(options: options, console: console)
        let app = NSApplication.shared
        let delegate = AppDelegate(controller: controller)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
} catch {
    console.error(error.localizedDescription)
    exit(1)
}
