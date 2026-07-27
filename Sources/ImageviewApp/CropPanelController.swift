import AppKit
import ImageviewCore

@MainActor
final class CropPanelController: NSWindowController {
    var onAspectChanged: ((CropAspect) -> Void)?
    var onPixelSizeChanged: ((Int, Int) -> Void)?
    var onCopy: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onOverwrite: (() -> Void)?
    var onCancel: (() -> Void)?

    private let aspectPopup = NSPopUpButton()
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let aspects = CropAspect.allCases

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 230),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.text("crop.title")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.contentView = makeContentView()
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updatePixelSize(_ size: CGSize?) {
        guard let size else {
            widthField.stringValue = ""
            heightField.stringValue = ""
            return
        }
        widthField.integerValue = Int(size.width)
        heightField.integerValue = Int(size.height)
    }

    private func makeContentView() -> NSView {
        aspectPopup.addItems(withTitles: aspects.map(title(for:)))
        aspectPopup.target = self
        aspectPopup.action = #selector(aspectChanged(_:))

        for field in [widthField, heightField] {
            field.alignment = .right
            field.formatter = integerFormatter()
            field.target = self
            field.action = #selector(pixelSizeChanged(_:))
        }

        let form = NSGridView(views: [
            [NSTextField(labelWithString: L10n.text("crop.ratio")), aspectPopup],
            [NSTextField(labelWithString: L10n.text("crop.width")), widthField],
            [NSTextField(labelWithString: L10n.text("crop.height")), heightField],
        ])
        form.rowSpacing = 10
        form.columnSpacing = 12
        form.column(at: 0).xPlacement = .trailing

        let copyButton = button(L10n.text("action.copy"), action: #selector(copyImage(_:)))
        let saveButton = button(L10n.text("action.save_as"), action: #selector(saveAs(_:)))
        let overwriteButton = button(L10n.text("action.overwrite"), action: #selector(overwrite(_:)))
        let cancelButton = button(L10n.text("action.cancel"), action: #selector(cancel(_:)))

        let primaryButtons = NSStackView(views: [copyButton, saveButton])
        primaryButtons.orientation = .horizontal
        primaryButtons.distribution = .fillEqually
        primaryButtons.spacing = 8

        let secondaryButtons = NSStackView(views: [overwriteButton, cancelButton])
        secondaryButtons.orientation = .horizontal
        secondaryButtons.distribution = .fillEqually
        secondaryButtons.spacing = 8

        let stack = NSStackView(views: [form, primaryButtons, secondaryButtons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
            primaryButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secondaryButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return content
    }

    private func title(for aspect: CropAspect) -> String {
        switch aspect {
        case .free:
            L10n.text("crop.free")
        case .original:
            L10n.text("crop.original")
        case .square:
            "1:1"
        case .oneByTwo:
            "1:2"
        case .twoByOne:
            "2:1"
        case .twoByThree:
            "2:3"
        case .threeByTwo:
            "3:2"
        case .threeByFour:
            "3:4"
        case .fourByThree:
            "4:3"
        case .nineBySixteen:
            "9:16"
        case .sixteenByNine:
            "16:9"
        }
    }

    private func integerFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 200_000
        return formatter
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func aspectChanged(_ sender: Any?) {
        guard aspects.indices.contains(aspectPopup.indexOfSelectedItem) else {
            return
        }
        onAspectChanged?(aspects[aspectPopup.indexOfSelectedItem])
    }

    @objc private func pixelSizeChanged(_ sender: Any?) {
        let width = widthField.integerValue
        let height = heightField.integerValue
        guard width > 0, height > 0 else {
            return
        }
        onPixelSizeChanged?(width, height)
    }

    @objc private func copyImage(_ sender: Any?) {
        onCopy?()
    }

    @objc private func saveAs(_ sender: Any?) {
        onSaveAs?()
    }

    @objc private func overwrite(_ sender: Any?) {
        onOverwrite?()
    }

    @objc private func cancel(_ sender: Any?) {
        onCancel?()
    }
}

extension CropPanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onCancel?()
    }
}
