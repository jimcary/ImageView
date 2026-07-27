import AppKit
import ImageviewCore

@MainActor
final class InspectorViewController: NSViewController {
    var onTrash: (() -> Void)?

    private let textView = NSTextView()
    private let labelPopup = NSPopUpButton()
    private var item: MediaItem?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        labelPopup.addItems(withTitles: [
            L10n.text("label.no_label"), L10n.text("label.gray"), L10n.text("label.green"),
            L10n.text("label.purple"), L10n.text("label.blue"), L10n.text("label.yellow"),
            L10n.text("label.red"), L10n.text("label.orange"),
        ])
        labelPopup.target = self
        labelPopup.action = #selector(labelChanged(_:))

        let reveal = button(L10n.text("inspector.show_finder"), action: #selector(revealInFinder(_:)))
        let copyPath = button(L10n.text("inspector.copy_path"), action: #selector(copyPath(_:)))
        let openDefault = button(L10n.text("inspector.open_default"), action: #selector(openInDefaultApp(_:)))
        let trash = button(L10n.text("inspector.trash"), action: #selector(moveToTrash(_:)))

        let buttonGrid = NSGridView(views: [
            [reveal, copyPath],
            [openDefault, trash],
        ])
        buttonGrid.rowSpacing = 6
        buttonGrid.columnSpacing = 6
        buttonGrid.translatesAutoresizingMaskIntoConstraints = false

        let labelRow = NSStackView(views: [
            NSTextField(labelWithString: L10n.text("inspector.finder_label")),
            labelPopup,
        ])
        labelRow.orientation = .horizontal
        labelRow.spacing = 8
        labelRow.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(labelRow)
        root.addSubview(buttonGrid)
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            labelRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            labelRow.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
            labelRow.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            buttonGrid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            buttonGrid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            buttonGrid.topAnchor.constraint(equalTo: labelRow.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: buttonGrid.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    func update(item: MediaItem?, properties: [CFString: Any]?) {
        self.item = item
        labelPopup.selectItem(at: max(min(item?.finderLabel ?? 0, 7), 0))

        guard let item else {
            textView.string = ""
            return
        }
        var lines = [
            item.url.lastPathComponent,
            item.url.path,
            "",
        ]
        if let fileSize = item.fileSize {
            lines.append("FileSize: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
        }
        if let createdAt = item.createdAt {
            lines.append("Created: \(createdAt.formatted())")
        }
        if let modifiedAt = item.modifiedAt {
            lines.append("Modified: \(modifiedAt.formatted())")
        }
        if let properties {
            lines.append(contentsOf: MetadataFormatter.rows(from: properties).map {
                "\($0.key): \($0.value)"
            })
        }
        textView.string = lines.joined(separator: "\n")
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func revealInFinder(_ sender: Any?) {
        guard let url = item?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyPath(_ sender: Any?) {
        guard let path = item?.url.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc private func openInDefaultApp(_ sender: Any?) {
        guard let url = item?.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func moveToTrash(_ sender: Any?) {
        guard let url = item?.url else { return }
        do {
            _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            onTrash?()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func labelChanged(_ sender: Any?) {
        guard var url = item?.url else { return }
        var values = URLResourceValues()
        values.labelNumber = labelPopup.indexOfSelectedItem
        do {
            try url.setResourceValues(values)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
