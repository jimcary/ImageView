import AppKit
import ImageviewCore

@MainActor
final class MediaCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("MediaCollectionItem")

    private let nameLabel = NSTextField(labelWithString: "")
    private var thumbnailTask: Task<Void, Never>?
    private var representedID: MediaItem.ID?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView = imageView
        container.addSubview(imageView)

        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.font = .systemFont(ofSize: 11)
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
            view.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
                : NSColor.clear.cgColor
        }
    }

    func configure(with item: MediaItem, maxPixelSize: Int) {
        thumbnailTask?.cancel()
        representedID = item.id
        nameLabel.stringValue = item.url.lastPathComponent
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
