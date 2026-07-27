import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let startupURLs = CommandLine.arguments.dropFirst().map {
    URL(fileURLWithPath: $0).standardizedFileURL
}
let applicationDelegate = AppDelegate(startupURLs: startupURLs)
application.delegate = applicationDelegate
application.run()
