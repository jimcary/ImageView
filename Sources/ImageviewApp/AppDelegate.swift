import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let startupURLs: [URL]
    private var windowController: ViewerWindowController?

    init(startupURLs: [URL] = []) {
        self.startupURLs = startupURLs
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        let controller = ViewerWindowController(urls: startupURLs)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let windowController {
            windowController.open(urls: urls)
        } else {
            let controller = ViewerWindowController(urls: urls)
            windowController = controller
            controller.showWindow(nil)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func openDocument(_ sender: Any?) {
        windowController?.chooseFiles(sender)
    }

    @objc private func showPrevious(_ sender: Any?) {
        windowController?.showPrevious(sender)
    }

    @objc private func showNext(_ sender: Any?) {
        windowController?.showNext(sender)
    }

    @objc private func fitToWindow(_ sender: Any?) {
        windowController?.fitToWindow(sender)
    }

    @objc private func showActualSize(_ sender: Any?) {
        windowController?.showActualSize(sender)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Imageview",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Imageview",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = fileMenu.addItem(
            withTitle: "Open…",
            action: #selector(openDocument(_:)),
            keyEquivalent: "o"
        )
        openItem.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let previous = viewMenu.addItem(
            withTitle: "Previous Image",
            action: #selector(showPrevious(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        )
        previous.target = self
        let next = viewMenu.addItem(
            withTitle: "Next Image",
            action: #selector(showNext(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        )
        next.target = self
        viewMenu.addItem(.separator())
        let fit = viewMenu.addItem(
            withTitle: "Fit to Window",
            action: #selector(fitToWindow(_:)),
            keyEquivalent: "0"
        )
        fit.target = self
        let actual = viewMenu.addItem(
            withTitle: "Actual Size",
            action: #selector(showActualSize(_:)),
            keyEquivalent: "1"
        )
        actual.target = self
        viewMenu.addItem(.separator())
        viewMenu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        ).keyEquivalentModifierMask = [.control, .command]
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        NSApp.mainMenu = mainMenu
    }
}
