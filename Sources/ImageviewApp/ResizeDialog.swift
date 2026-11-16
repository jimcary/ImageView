import AppKit

@MainActor
final class ResizeDialog: NSObject, NSTextFieldDelegate {
    private let alert = NSAlert()
    private let presets = NSPopUpButton()
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let proportional = NSButton(checkboxWithTitle: L10n.text("resize.proportional"), target: nil, action: nil)
    private let validationLabel = NSTextField(wrappingLabelWithString: L10n.text("resize.invalid"))
    private let originalWidth: Int
    private let originalHeight: Int
    private let presetSizes = [320, 640, 800, 1024, 1280, 1920]

    private init(width: Int, height: Int) {
        originalWidth = width
        originalHeight = height
        super.init()
        alert.messageText = L10n.text("resize.title")
        alert.addButton(withTitle: L10n.text("resize.apply"))
        alert.addButton(withTitle: L10n.text("action.cancel"))

        presets.addItems(withTitles: [L10n.text("resize.custom")] + presetSizes.map { "\($0) × \($0)" })
        presets.target = self
        presets.action = #selector(presetChanged(_:))
        widthField.stringValue = "\(width)"
        heightField.stringValue = "\(height)"
        widthField.delegate = self
        heightField.delegate = self
        widthField.setAccessibilityIdentifier("resizeWidth")
        heightField.setAccessibilityIdentifier("resizeHeight")
        proportional.state = .on
        proportional.target = self
        proportional.action = #selector(proportionalChanged(_:))

        let pixels = NSTextField(labelWithString: L10n.text("resize.pixels"))
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: L10n.text("resize.fit")), presets],
            [NSTextField(labelWithString: L10n.text("crop.width")), widthField],
            [NSTextField(labelWithString: L10n.text("crop.height")), heightField],
            [NSTextField(labelWithString: L10n.text("resize.unit")), pixels],
            [NSView(), proportional],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 210))
        content.addSubview(grid)
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        validationLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(validationLabel)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            widthField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            validationLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            validationLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            validationLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
        ])
        alert.accessoryView = content
        updateValidity()
    }

    static func run(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        let dialog = ResizeDialog(width: width, height: height)
        guard dialog.alert.runModal() == .alertFirstButtonReturn,
              let width = dialog.dimension(dialog.widthField),
              let height = dialog.dimension(dialog.heightField),
              width * height <= 100_000_000 else {
            return nil
        }
        return (width, height)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        presets.selectItem(at: 0)
        if proportional.state == .on, let value = dimension(field) {
            if field === widthField {
                heightField.stringValue = "\(max(1, Int((Double(value) * Double(originalHeight) / Double(originalWidth)).rounded())))"
            } else {
                widthField.stringValue = "\(max(1, Int((Double(value) * Double(originalWidth) / Double(originalHeight)).rounded())))"
            }
        }
        updateValidity()
    }

    @objc private func presetChanged(_ sender: Any?) {
        let index = presets.indexOfSelectedItem - 1
        guard presetSizes.indices.contains(index) else { return }
        let size = presetSizes[index]
        if proportional.state == .on {
            let scale = Double(size) / Double(max(originalWidth, originalHeight))
            widthField.stringValue = "\(max(1, Int((Double(originalWidth) * scale).rounded())))"
            heightField.stringValue = "\(max(1, Int((Double(originalHeight) * scale).rounded())))"
        } else {
            widthField.stringValue = "\(size)"
            heightField.stringValue = "\(size)"
        }
        updateValidity()
    }

    @objc private func proportionalChanged(_ sender: Any?) {
        if proportional.state == .on {
            controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: widthField))
        }
    }

    private func dimension(_ field: NSTextField) -> Int? {
        guard let value = Int(field.stringValue), (1...16_384).contains(value) else { return nil }
        return value
    }

    private func updateValidity() {
        let valid: Bool
        if let width = dimension(widthField), let height = dimension(heightField) {
            valid = width * height <= 100_000_000
        } else {
            valid = false
        }
        alert.buttons.first?.isEnabled = valid
        validationLabel.isHidden = valid
    }
}
