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

        for (index, window) in windows.enumerated() {
            if index > 0 {
                print("")
            }

            print("Bundle ID: \(window.bundleID ?? "<no bundle id>")")
            print("Window title: \(window.title.isEmpty ? "<untitled>" : window.title)")

            let extra = window.document ?? window.url ?? window.identifier ?? window.executablePath
            if let extra, !extra.isEmpty {
                print("Best match value: \(extra)")
            }

            if options.windowListFormat == .verbose {
                print("App name: \(window.appName)")
                print("PID: \(window.pid)")
                print("App window index: \(window.appWindowIndex)")

                if let executablePath = window.executablePath {
                    print("Executable path: \(executablePath)")
                }
                if let document = window.document {
                    print("Document: \(document)")
                }
                if let url = window.url {
                    print("URL: \(url)")
                }
                if let identifier = window.identifier {
                    print("Identifier: \(identifier)")
                }
                if let role = window.role {
                    print("Role: \(role)")
                }
                if let subrole = window.subrole {
                    print("Subrole: \(subrole)")
                }
                if let minimized = window.minimized {
                    print("Minimized: \(minimized)")
                }
                if let position = window.position {
                    print("Position: x=\(Int(position.x)) y=\(Int(position.y))")
                }
                if let size = window.size {
                    print("Size: width=\(Int(size.width)) height=\(Int(size.height))")
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
