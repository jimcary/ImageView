import AppKit
import ImageviewCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let startupURLs: [URL]
    private var windowControllers: [ViewerWindowController] = []
    private var preferencesWindowController: PreferencesWindowController?

    private var activeWindowController: ViewerWindowController? {
        windowControllers.first(where: { $0.window?.isKeyWindow == true })
            ?? windowControllers.last
    }

    init(startupURLs: [URL] = []) {
        self.startupURLs = startupURLs
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        makeViewer(urls: startupURLs)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if PreferencesStore().singleWindow, let controller = activeWindowController {
            controller.open(urls: urls)
        } else {
            makeViewer(urls: urls)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            if let controller = activeWindowController {
                controller.showWindow(nil)
            } else {
                makeViewer(urls: [])
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        PreferencesStore().closeLastWindowQuits
    }

    func applicationWillTerminate(_ notification: Notification) {
        if PreferencesStore().clearsRecentItems {
            NSDocumentController.shared.clearRecentDocuments(nil)
        }
    }

    @objc private func openDocument(_ sender: Any?) {
        activeWindowController?.chooseFiles(sender)
    }

    @objc private func showPrevious(_ sender: Any?) {
        activeWindowController?.showPrevious(sender)
    }

    @objc private func showNext(_ sender: Any?) {
        activeWindowController?.showNext(sender)
    }

    @objc private func fitToWindow(_ sender: Any?) {
        activeWindowController?.fitToWindow(sender)
    }

    @objc private func showActualSize(_ sender: Any?) {
        activeWindowController?.showActualSize(sender)
    }

    @objc private func pinClipboard(_ sender: Any?) {
        activeWindowController?.pinClipboard(sender)
    }

    @objc private func recognizeText(_ sender: Any?) {
        activeWindowController?.performOCR(sender)
    }

    @objc private func showPreferences(_ sender: Any?) {
        if let preferencesWindowController {
            preferencesWindowController.showWindow(nil)
            preferencesWindowController.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = PreferencesWindowController()
        controller.onLanguageChanged = { [weak self] in
            self?.reloadLanguage()
        }
        preferencesWindowController = controller
        controller.showWindow(nil)
    }

    private func reloadLanguage() {
        configureMainMenu()
        let previousControllers = windowControllers
        let urls = previousControllers.map(\.currentURL)
        windowControllers.removeAll()
        for url in urls {
            makeViewer(urls: url.map { [$0] } ?? [])
        }
        previousControllers.forEach { $0.close() }
        preferencesWindowController?.close()
        preferencesWindowController = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    private func makeViewer(urls: [URL]) -> ViewerWindowController {
        let controller = ViewerWindowController(urls: urls)
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.windowControllers.removeAll { $0 === controller }
        }
        controller.onOpenURLsRequested = { [weak self, weak controller] urls in
            guard let self else { return }
            if PreferencesStore().singleWindow, let controller {
                controller.open(urls: urls)
            } else {
                self.makeViewer(urls: urls)
            }
        }
        windowControllers.append(controller)
        controller.showWindow(nil)
        return controller
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: L10n.text("app.about"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let preferences = appMenu.addItem(
            withTitle: L10n.text("menu.preferences"),
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        preferences.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: L10n.text("app.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L10n.text("menu.file"))
        let openItem = fileMenu.addItem(
            withTitle: L10n.text("menu.open"),
            action: #selector(openDocument(_:)),
            keyEquivalent: "o"
        )
        openItem.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: L10n.text("menu.close_window"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.text("menu.edit"))
        editMenu.addItem(
            withTitle: L10n.text("menu.copy"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        let pastePin = editMenu.addItem(
            withTitle: L10n.text("menu.pin_clipboard"),
            action: #selector(pinClipboard(_:)),
            keyEquivalent: "v"
        )
        pastePin.keyEquivalentModifierMask = [.command, .shift]
        pastePin.target = self
        let recognize = editMenu.addItem(
            withTitle: L10n.text("menu.recognize_text"),
            action: #selector(recognizeText(_:)),
            keyEquivalent: "r"
        )
        recognize.keyEquivalentModifierMask = [.command, .shift]
        recognize.target = self
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: L10n.text("menu.view"))
        let previous = viewMenu.addItem(
            withTitle: L10n.text("menu.previous"),
            action: #selector(showPrevious(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        )
        previous.target = self
        let next = viewMenu.addItem(
            withTitle: L10n.text("menu.next"),
            action: #selector(showNext(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        )
        next.target = self
        viewMenu.addItem(.separator())
        let fit = viewMenu.addItem(
            withTitle: L10n.text("menu.fit"),
            action: #selector(fitToWindow(_:)),
            keyEquivalent: "0"
        )
        fit.target = self
        let actual = viewMenu.addItem(
            withTitle: L10n.text("menu.actual"),
            action: #selector(showActualSize(_:)),
            keyEquivalent: "1"
        )
        actual.target = self
        viewMenu.addItem(.separator())
        viewMenu.addItem(
            withTitle: L10n.text("menu.full_screen"),
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        ).keyEquivalentModifierMask = [.control, .command]
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        NSApp.mainMenu = mainMenu
    }
}
