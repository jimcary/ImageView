import AppKit
import ImageviewCore

@MainActor
final class AppDelegate:
    NSObject,
    NSApplicationDelegate,
    NSMenuDelegate,
    NSMenuItemValidation
{
    private let startupURLs: [URL]
    private var windowControllers: [ViewerWindowController] = []
    private var preferencesWindowController: PreferencesWindowController?
    private var recentMenu: NSMenu?

    private var activeWindowController: ViewerWindowController? {
        windowControllers.first(where: { $0.window?.isKeyWindow == true })
            ?? windowControllers.last
    }

    private var keyWindowController: ViewerWindowController? {
        windowControllers.first(where: { $0.window?.isKeyWindow == true })
    }

    init(startupURLs: [URL] = []) {
        self.startupURLs = startupURLs
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        if windowControllers.isEmpty {
            makeViewer(urls: startupURLs)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        recordRecent(urls)
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

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }
        application(NSApp, open: [url])
    }

    @objc private func clearRecent(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
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

    @objc private func rotateLeft(_ sender: Any?) {
        keyWindowController?.rotateLeft(sender)
    }

    @objc private func rotateRight(_ sender: Any?) {
        keyWindowController?.rotateRight(sender)
    }

    @objc private func pinClipboard(_ sender: Any?) {
        activeWindowController?.pinClipboard(sender)
    }

    @objc private func recognizeText(_ sender: Any?) {
        activeWindowController?.performOCR(sender)
    }

    @objc private func deleteCurrent(_ sender: Any?) {
        keyWindowController?.deleteCurrent(sender)
    }

    @objc private func commitCropAndOverwrite(_ sender: Any?) {
        keyWindowController?.commitCropAndOverwrite(sender)
    }

    @objc private func saveCurrentEdits(_ sender: Any?) {
        keyWindowController?.saveCurrentEdits(sender)
    }

    @objc private func showCurrentInFinder(_ sender: Any?) {
        keyWindowController?.showCurrentInFinder(sender)
    }

    @objc private func toggleGrid(_ sender: Any?) {
        activeWindowController?.toggleGrid(sender)
    }

    @objc private func toggleInspector(_ sender: Any?) {
        activeWindowController?.toggleInspector(sender)
    }

    @objc private func pinCurrentImage(_ sender: Any?) {
        activeWindowController?.pinCurrentImage(sender)
    }

    @objc private func printCurrentImage(_ sender: Any?) {
        activeWindowController?.printCurrentImage(sender)
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
        controller.onShortcutsChanged = { [weak self] in
            self?.configureMainMenu()
        }
        controller.onPreferencesChanged = { [weak self] in
            self?.windowControllers.forEach { $0.applyPreferences() }
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
        recordRecent(urls)
        let controller = ViewerWindowController(urls: urls)
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.windowControllers.removeAll { $0 === controller }
        }
        controller.onOpenURLsRequested = { [weak self, weak controller] urls in
            guard let self else { return }
            self.recordRecent(urls)
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
            shortcut: .open
        )
        openItem.target = self
        let recentItem = NSMenuItem(title: L10n.text("menu.open_recent"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: L10n.text("menu.open_recent"))
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        self.recentMenu = recentMenu
        fileMenu.addItem(recentItem)
        fileMenu.addItem(.separator())
        let saveItem = fileMenu.addItem(
            withTitle: L10n.text("menu.save"),
            action: #selector(saveCurrentEdits(_:)),
            shortcut: .save
        )
        saveItem.target = self
        let showInFinderItem = fileMenu.addItem(
            withTitle: L10n.text("menu.show_in_finder"),
            action: #selector(showCurrentInFinder(_:)),
            shortcut: .showInFinder
        )
        showInFinderItem.target = self
        fileMenu.addItem(.separator())
        let printItem = fileMenu.addItem(
            withTitle: L10n.text("menu.print"),
            action: #selector(printCurrentImage(_:)),
            keyEquivalent: "p"
        )
        printItem.target = self
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
        let delete = editMenu.addItem(
            withTitle: L10n.text("menu.delete"),
            action: #selector(deleteCurrent(_:)),
            shortcut: .delete
        )
        delete.target = self
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
            shortcut: .ocr
        )
        recognize.target = self
        let crop = editMenu.addItem(
            withTitle: L10n.text("menu.crop_and_save"),
            action: #selector(commitCropAndOverwrite(_:)),
            shortcut: .crop
        )
        crop.target = self
        let pin = editMenu.addItem(
            withTitle: L10n.text("toolbar.pin"),
            action: #selector(pinCurrentImage(_:)),
            shortcut: .pin
        )
        pin.target = self
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: L10n.text("menu.view"))
        let previous = viewMenu.addItem(
            withTitle: L10n.text("menu.previous"),
            action: #selector(showPrevious(_:)),
            shortcut: .previous
        )
        previous.target = self
        let next = viewMenu.addItem(
            withTitle: L10n.text("menu.next"),
            action: #selector(showNext(_:)),
            shortcut: .next
        )
        next.target = self
        viewMenu.addItem(.separator())
        let grid = viewMenu.addItem(
            withTitle: L10n.text("toolbar.grid"),
            action: #selector(toggleGrid(_:)),
            shortcut: .grid
        )
        grid.target = self
        let inspector = viewMenu.addItem(
            withTitle: L10n.text("toolbar.info"),
            action: #selector(toggleInspector(_:)),
            shortcut: .inspector
        )
        inspector.target = self
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
        let rotateLeft = viewMenu.addItem(
            withTitle: L10n.text("toolbar.rotate_left"),
            action: #selector(rotateLeft(_:)),
            shortcut: .rotateLeft
        )
        rotateLeft.target = self
        let rotateRight = viewMenu.addItem(
            withTitle: L10n.text("toolbar.rotate_right"),
            action: #selector(rotateRight(_:)),
            shortcut: .rotateRight
        )
        rotateRight.target = self
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else {
            return
        }
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        if urls.isEmpty {
            let empty = menu.addItem(
                withTitle: L10n.text("menu.no_recent"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
        } else {
            for url in urls {
                let item = menu.addItem(
                    withTitle: url.lastPathComponent,
                    action: #selector(openRecent(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = url
                item.target = self
            }
            menu.addItem(.separator())
            let clear = menu.addItem(
                withTitle: L10n.text("menu.clear_recent"),
                action: #selector(clearRecent(_:)),
                keyEquivalent: ""
            )
            clear.target = self
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(deleteCurrent(_:)):
            keyWindowController?.hasCurrentItem == true
        case #selector(commitCropAndOverwrite(_:)):
            keyWindowController?.canCommitCrop == true
        case #selector(saveCurrentEdits(_:)):
            keyWindowController?.canSaveCurrentEdits == true
        case #selector(showCurrentInFinder(_:)):
            keyWindowController?.hasCurrentItem == true
        case #selector(rotateLeft(_:)), #selector(rotateRight(_:)):
            keyWindowController?.hasCurrentItem == true
        default:
            true
        }
    }

    private func recordRecent(_ urls: [URL]) {
        for url in urls {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
    }
}

private extension NSMenu {
    func addItem(
        withTitle title: String,
        action: Selector?,
        shortcut command: ShortcutCommand
    ) -> NSMenuItem {
        let shortcut = PreferencesStore().shortcut(for: command)
        let item = addItem(
            withTitle: title,
            action: action,
            keyEquivalent: shortcut.key
        )
        item.keyEquivalentModifierMask = shortcut.modifiers.appKitFlags
        return item
    }
}

private extension ShortcutModifiers {
    var appKitFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.shift) { flags.insert(.shift) }
        return flags
    }
}
