import AppKit
import ImageviewCore

@MainActor
final class PreferencesWindowController: NSWindowController {
    var onLanguageChanged: (() -> Void)?
    var onShortcutsChanged: (() -> Void)?
    var onPreferencesChanged: (() -> Void)?

    private let preferences = PreferencesStore()
    private let languagePopup = NSPopUpButton()
    private let singleWindowButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let quitButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let clearRecentButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let recursiveButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let wrapButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let showsThumbnailsButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let thumbnailSlider = NSSlider(value: 96, minValue: 48, maxValue: 320, target: nil, action: nil)
    private let thumbnailValue = NSTextField(labelWithString: "")
    private let pinOpacitySlider = NSSlider(value: 1, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let pinOpacityValue = NSTextField(labelWithString: "")
    private let cacheSlider = NSSlider(value: 512, minValue: 64, maxValue: 4_096, target: nil, action: nil)
    private let cacheValue = NSTextField(labelWithString: "")
    private let tabController = NSTabViewController()
    private var shortcutControls: [ShortcutControls] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("preferences.title")
        window.center()
        super.init(window: window)
        configureControls()
        rebuildTabs()
        window.contentViewController = tabController
        synchronizeFromStore()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func configureControls() {
        languagePopup.addItems(withTitles: [
            L10n.text("preferences.system_language"),
            L10n.text("preferences.english"),
            L10n.text("preferences.chinese"),
        ])
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        configure(singleWindowButton, action: #selector(booleanChanged(_:)), tag: 1)
        configure(quitButton, action: #selector(booleanChanged(_:)), tag: 2)
        configure(clearRecentButton, action: #selector(booleanChanged(_:)), tag: 3)
        configure(recursiveButton, action: #selector(booleanChanged(_:)), tag: 4)
        configure(wrapButton, action: #selector(booleanChanged(_:)), tag: 5)
        configure(showsThumbnailsButton, action: #selector(booleanChanged(_:)), tag: 6)

        thumbnailSlider.target = self
        thumbnailSlider.action = #selector(thumbnailSizeChanged(_:))
        pinOpacitySlider.target = self
        pinOpacitySlider.action = #selector(pinOpacityChanged(_:))
        cacheSlider.target = self
        cacheSlider.action = #selector(cacheLimitChanged(_:))
    }

    private func configure(_ button: NSButton, action: Selector, tag: Int) {
        button.target = self
        button.action = action
        button.tag = tag
    }

    private func rebuildTabs() {
        tabController.tabStyle = .toolbar
        tabController.addChild(tab(
            title: L10n.text("preferences.general"),
            symbol: "gearshape",
            rows: [
                labeled(L10n.text("preferences.language"), languagePopup),
                titled(singleWindowButton, L10n.text("preferences.single_window")),
                titled(quitButton, L10n.text("preferences.quit_last_window")),
                titled(clearRecentButton, L10n.text("preferences.clear_recent")),
            ]
        ))
        tabController.addChild(tab(
            title: L10n.text("preferences.viewer"),
            symbol: "photo",
            rows: [
                titled(recursiveButton, L10n.text("preferences.recursive")),
                titled(wrapButton, L10n.text("preferences.wrap")),
            ]
        ))
        tabController.addChild(tab(
            title: L10n.text("preferences.thumbnails"),
            symbol: "rectangle.grid.3x2",
            rows: [
                titled(showsThumbnailsButton, L10n.text("preferences.show_thumbnails")),
                sliderRow(
                    label: L10n.text("preferences.thumbnail_size"),
                    slider: thumbnailSlider,
                    value: thumbnailValue
                ),
            ]
        ))
        tabController.addChild(tab(
            title: L10n.text("preferences.pinboard"),
            symbol: "pin",
            rows: [
                sliderRow(
                    label: L10n.text("preferences.pin_opacity"),
                    slider: pinOpacitySlider,
                    value: pinOpacityValue
                ),
            ]
        ))
        tabController.addChild(tab(
            title: L10n.text("preferences.shortcuts"),
            symbol: "command",
            rows: shortcutRows()
        ))
        tabController.addChild(tab(
            title: L10n.text("preferences.formats"),
            symbol: "doc.richtext",
            rows: [information(L10n.text("preferences.formats_info"))]
        ))

        let reset = NSButton(
            title: L10n.text("preferences.reset"),
            target: self,
            action: #selector(resetPreferences(_:))
        )
        tabController.addChild(tab(
            title: L10n.text("preferences.advanced"),
            symbol: "wrench.and.screwdriver",
            rows: [
                sliderRow(
                    label: L10n.text("preferences.cache_limit"),
                    slider: cacheSlider,
                    value: cacheValue
                ),
                reset,
            ]
        ))
    }

    private func tab(title: String, symbol: String, rows: [NSView]) -> NSViewController {
        let controller = NSViewController()
        controller.title = title

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
        ])
        controller.view = view
        return controller
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let stack = NSStackView(views: [NSTextField(labelWithString: title), control])
        stack.orientation = .horizontal
        stack.spacing = 12
        return stack
    }

    private func titled(_ button: NSButton, _ title: String) -> NSView {
        button.title = title
        return button
    }

    private func sliderRow(label: String, slider: NSSlider, value: NSTextField) -> NSView {
        slider.widthAnchor.constraint(equalToConstant: 280).isActive = true
        value.widthAnchor.constraint(equalToConstant: 72).isActive = true
        value.alignment = .right
        let stack = NSStackView(views: [
            NSTextField(labelWithString: label),
            slider,
            value,
        ])
        stack.orientation = .horizontal
        stack.spacing = 12
        return stack
    }

    private func information(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.maximumNumberOfLines = 0
        label.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return label
    }

    private func synchronizeFromStore() {
        let languages = AppLanguage.allCases
        languagePopup.selectItem(at: languages.firstIndex(of: preferences.language) ?? 0)
        singleWindowButton.state = preferences.singleWindow ? .on : .off
        quitButton.state = preferences.closeLastWindowQuits ? .on : .off
        clearRecentButton.state = preferences.clearsRecentItems ? .on : .off
        recursiveButton.state = preferences.recursiveScan ? .on : .off
        wrapButton.state = preferences.wrapsNavigation ? .on : .off
        showsThumbnailsButton.state = preferences.showsThumbnails ? .on : .off
        thumbnailSlider.integerValue = preferences.thumbnailSize
        pinOpacitySlider.doubleValue = preferences.pinOpacity
        cacheSlider.integerValue = preferences.cacheLimitMB
        synchronizeShortcuts()
        updateValueLabels()
    }

    private func updateValueLabels() {
        thumbnailValue.stringValue = "\(thumbnailSlider.integerValue) px"
        pinOpacityValue.stringValue = "\(Int(pinOpacitySlider.doubleValue * 100))%"
        cacheValue.stringValue = "\(cacheSlider.integerValue) MB"
    }

    @objc private func languageChanged(_ sender: Any?) {
        let languages = AppLanguage.allCases
        guard languages.indices.contains(languagePopup.indexOfSelectedItem) else {
            return
        }
        preferences.language = languages[languagePopup.indexOfSelectedItem]
        onLanguageChanged?()
    }

    @objc private func booleanChanged(_ sender: NSButton) {
        let value = sender.state == .on
        switch sender.tag {
        case 1: preferences.singleWindow = value
        case 2: preferences.closeLastWindowQuits = value
        case 3: preferences.clearsRecentItems = value
        case 4: preferences.recursiveScan = value
        case 5: preferences.wrapsNavigation = value
        case 6: preferences.showsThumbnails = value
        default: break
        }
        onPreferencesChanged?()
    }

    @objc private func thumbnailSizeChanged(_ sender: NSSlider) {
        preferences.thumbnailSize = sender.integerValue
        updateValueLabels()
        onPreferencesChanged?()
    }

    @objc private func pinOpacityChanged(_ sender: NSSlider) {
        preferences.pinOpacity = sender.doubleValue
        updateValueLabels()
        onPreferencesChanged?()
    }

    @objc private func cacheLimitChanged(_ sender: NSSlider) {
        preferences.cacheLimitMB = sender.integerValue
        updateValueLabels()
        onPreferencesChanged?()
    }

    @objc private func resetPreferences(_ sender: Any?) {
        preferences.reset()
        synchronizeFromStore()
        onLanguageChanged?()
    }

    private func shortcutRows() -> [NSView] {
        if shortcutControls.isEmpty {
            shortcutControls = ShortcutCommand.allCases.map { command in
                let keyField = NSTextField()
                keyField.widthAnchor.constraint(equalToConstant: 64).isActive = true
                keyField.alignment = .center
                keyField.target = self
                keyField.action = #selector(shortcutChanged(_:))

                let modifierButtons = [
                    modifierButton("⌘"),
                    modifierButton("⌥"),
                    modifierButton("⌃"),
                    modifierButton("⇧"),
                ]
                return ShortcutControls(
                    command: command,
                    keyField: keyField,
                    modifierButtons: modifierButtons
                )
            }
        }

        return shortcutControls.map { controls in
            let row = NSStackView(views: [
                shortcutLabel(for: controls.command),
                controls.keyField,
            ] + controls.modifierButtons)
            row.orientation = .horizontal
            row.spacing = 8
            return row
        }
    }

    private func shortcutLabel(for command: ShortcutCommand) -> NSView {
        let label = NSTextField(labelWithString: L10n.text("shortcut.\(command.rawValue)"))
        label.widthAnchor.constraint(equalToConstant: 140).isActive = true
        return label
    }

    private func modifierButton(_ title: String) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(shortcutChanged(_:)))
        button.setButtonType(.switch)
        return button
    }

    private func synchronizeShortcuts() {
        let shortcuts = preferences.shortcuts
        for controls in shortcutControls {
            guard let shortcut = shortcuts.first(where: { $0.command == controls.command }) else {
                continue
            }
            controls.keyField.stringValue = displayKey(shortcut.key)
            let modifiers: [ShortcutModifiers] = [.command, .option, .control, .shift]
            for (button, modifier) in zip(controls.modifierButtons, modifiers) {
                button.state = shortcut.modifiers.contains(modifier) ? .on : .off
            }
        }
    }

    @objc private func shortcutChanged(_ sender: Any?) {
        let modifiers: [ShortcutModifiers] = [.command, .option, .control, .shift]
        let shortcuts = shortcutControls.map { controls in
            let selected = zip(controls.modifierButtons, modifiers).reduce(into: ShortcutModifiers()) {
                if $1.0.state == .on {
                    $0.insert($1.1)
                }
            }
            return Shortcut(
                command: controls.command,
                key: storedKey(controls.keyField.stringValue),
                modifiers: selected
            )
        }

        do {
            try preferences.updateShortcuts(shortcuts)
            synchronizeShortcuts()
            onShortcutsChanged?()
        } catch ShortcutPreferencesError.conflict {
            presentShortcutError(L10n.text("preferences.shortcut_conflict"))
            synchronizeShortcuts()
        } catch {
            presentShortcutError(L10n.text("preferences.shortcut_invalid"))
            synchronizeShortcuts()
        }
    }

    private func displayKey(_ key: String) -> String {
        switch key {
        case "\u{F702}": "←"
        case "\u{F703}": "→"
        default: key.uppercased()
        }
    }

    private func storedKey(_ key: String) -> String {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "←": "\u{F702}"
        case "→": "\u{F703}"
        default: key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func presentShortcutError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("preferences.shortcut_error")
        alert.informativeText = message
        alert.runModal()
    }
}

private struct ShortcutControls {
    let command: ShortcutCommand
    let keyField: NSTextField
    let modifierButtons: [NSButton]
}
