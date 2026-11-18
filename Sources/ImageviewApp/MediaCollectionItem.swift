import AppKit
import ImageviewCore

private final class SelectionBackgroundView: NSView {
    var selected = false {
        didSet { needsDisplay = true }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard selected else { return }
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 9, yRadius: 9)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        outline.fill()
        NSColor.controlAccentColor.setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
    }
}

@MainActor
final class MediaCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("MediaCollectionItem")

    private let nameLabel = NSTextField(labelWithString: "")
    private var thumbnailTask: Task<Void, Never>?
    private var representedID: MediaItem.ID?

    override func loadView() {
        let container = SelectionBackgroundView()

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView = imageView
        container.addSubview(imageView)

        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -5),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            imageView.bottomAnchor.constraint(equalTo: nameLabel.topAnchor, constant: -4),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 3),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -3),
            nameLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            nameLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
        view = container
    }

    override var isSelected: Bool {
        didSet {
            (view as? SelectionBackgroundView)?.selected = isSelected
        }
    }

    func configure(with item: MediaItem, maxPixelSize: Int) {
        thumbnailTask?.cancel()
        representedID = item.id
        nameLabel.stringValue = item.url.lastPathComponent
        nameLabel.toolTip = item.url.lastPathComponent
        imageView?.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)

        let id = item.id
        let url = item.url
        thumbnailTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try ThumbnailDecoder().decode(url: url, maxPixelSize: maxPixelSize) }
            }.value
            guard let self, !Task.isCancelled, self.representedID == id,
                  case let .success(image) = result else {
                return
            }
            self.imageView?.image = NSImage(cgImage: image, size: .zero)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        representedID = nil
        imageView?.image = nil
        nameLabel.stringValue = ""
    }
}
