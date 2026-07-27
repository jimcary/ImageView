import AppKit

@MainActor
final class PinboardWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let originalImageSize: NSSize?
    private var frameBeforeThumbnail: NSRect?
    private var minimumSizeBeforeThumbnail: NSSize?
    private var thumbnailMenuItem: NSMenuItem?

    convenience init(image: NSImage) {
        let sourceSize = Self.pixelSize(for: image)
        let imageView = PinImageView(image: image, sourceSize: sourceSize)
        let scale = min(1, min(520 / max(sourceSize.width, 1), 520 / max(sourceSize.height, 1)))
        let size = NSSize(
            width: max(sourceSize.width * scale, 160),
            height: max(sourceSize.height * scale, 120)
        )
        self.init(
            contentView: imageView,
            size: size,
            title: L10n.text("pin.image"),
            originalImageSize: sourceSize
        )
    }

    convenience init(text: String) {
        let textView = NSTextView()
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.96)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.font = .systemFont(ofSize: 15)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        self.init(
            contentView: scrollView,
            size: NSSize(width: 360, height: 240),
            title: L10n.text("pin.text"),
            originalImageSize: nil
        )
    }

    private init(
        contentView: NSView,
        size: NSSize,
        title: String,
        originalImageSize: NSSize?
    ) {
        self.originalImageSize = originalImageSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.minSize = NSSize(width: 120, height: 90)
        panel.contentView = contentView
        super.init(window: panel)
        panel.delegate = self
        installContextMenu(on: contentView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func installContextMenu(on view: NSView) {
        let menu = NSMenu()
        for value in [100, 75, 50, 25] {
            let item = NSMenuItem(
                title: String(format: L10n.text("pin.opacity"), value),
                action: #selector(setOpacity(_:)),
                keyEquivalent: ""
            )
            item.tag = value
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if originalImageSize != nil {
            let originalSize = NSMenuItem(
                title: L10n.text("pin.original_size"),
                action: #selector(showOriginalSize(_:)),
                keyEquivalent: ""
            )
            originalSize.target = self
            menu.addItem(originalSize)
        }
        let thumbnail = NSMenuItem(
            title: L10n.text("pin.thumbnail_mode"),
            action: #selector(toggleThumbnailMode(_:)),
            keyEquivalent: ""
        )
        thumbnail.target = self
        thumbnailMenuItem = thumbnail
        menu.addItem(thumbnail)
        menu.addItem(.separator())
        let close = NSMenuItem(
            title: L10n.text("pin.close"),
            action: #selector(closePin(_:)),
            keyEquivalent: ""
        )
        close.target = self
        menu.addItem(close)
        view.menu = menu
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        window?.alphaValue = CGFloat(sender.tag) / 100
    }

    @objc private func showOriginalSize(_ sender: Any?) {
        guard let originalImageSize, let window else {
            return
        }
        leaveThumbnailMode()
        (window.contentView as? PinImageView)?.resetToOriginalSize()
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(originalImageSize)
        window.setFrameTopLeftPoint(topLeft)
    }

    @objc private func toggleThumbnailMode(_ sender: Any?) {
        if frameBeforeThumbnail == nil {
            enterThumbnailMode()
        } else {
            leaveThumbnailMode()
        }
    }

    @objc private func closePin(_ sender: Any?) {
        close()
    }

    private func enterThumbnailMode() {
        guard let window else {
            return
        }
        frameBeforeThumbnail = window.frame
        minimumSizeBeforeThumbnail = window.minSize
        let aspectSize = originalImageSize ?? window.frame.size
        let thumbnailSize = Self.thumbnailSize(for: aspectSize)
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)

        (window.contentView as? PinImageView)?.isThumbnailMode = true
        window.minSize = .zero
        window.contentAspectRatio = thumbnailSize
        window.setFrame(NSRect(origin: window.frame.origin, size: thumbnailSize), display: true, animate: true)
        window.setFrameTopLeftPoint(topLeft)
        thumbnailMenuItem?.state = .on
    }

    private func leaveThumbnailMode() {
        guard let window, let previousFrame = frameBeforeThumbnail else {
            return
        }
        frameBeforeThumbnail = nil
        (window.contentView as? PinImageView)?.isThumbnailMode = false
        window.contentAspectRatio = .zero
        window.minSize = minimumSizeBeforeThumbnail ?? NSSize(width: 120, height: 90)
        minimumSizeBeforeThumbnail = nil
        window.setFrame(previousFrame, display: true, animate: true)
        thumbnailMenuItem?.state = .off
    }

    private static func pixelSize(for image: NSImage) -> NSSize {
        let largestRepresentation = image.representations
            .filter { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
            .max {
                $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
            }
        if let largestRepresentation {
            return NSSize(
                width: largestRepresentation.pixelsWide,
                height: largestRepresentation.pixelsHigh
            )
        }
        return image.size
    }

    private static func thumbnailSize(for sourceSize: NSSize) -> NSSize {
        let longEdge: CGFloat = 240
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return NSSize(width: longEdge, height: 160)
        }
        if sourceSize.width >= sourceSize.height {
            return NSSize(
                width: longEdge,
                height: longEdge * sourceSize.height / sourceSize.width
            )
        }
        return NSSize(
            width: longEdge * sourceSize.width / sourceSize.height,
            height: longEdge
        )
    }
}

@MainActor
private final class PinImageView: NSView {
    private let image: NSImage
    private let sourceSize: NSSize
    private var scale: CGFloat = 1
    private var offset = CGPoint.zero
    private var dragStart: CGPoint?
    var isThumbnailMode = false {
        didSet { needsDisplay = true }
    }

    init(image: NSImage, sourceSize: NSSize) {
        self.image = image
        self.sourceSize = sourceSize
        super.init(frame: NSRect(origin: .zero, size: sourceSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let drawingScale = isThumbnailMode
            ? min(bounds.width / max(sourceSize.width, 1), bounds.height / max(sourceSize.height, 1))
            : scale
        let drawingOffset = isThumbnailMode ? CGPoint.zero : offset
        let size = NSSize(width: sourceSize.width * drawingScale, height: sourceSize.height * drawingScale)
        let rect = NSRect(
            x: bounds.midX - size.width / 2 + drawingOffset.x,
            y: bounds.midY - size.height / 2 + drawingOffset.y,
            width: size.width,
            height: size.height
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func scrollWheel(with event: NSEvent) {
        scale = min(max(scale * exp(-event.scrollingDeltaY * 0.015), 0.05), 20)
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        scale = min(max(scale * (1 + event.magnification), 0.05), 20)
        needsDisplay = true
    }

    func resetToOriginalSize() {
        scale = 1
        offset = .zero
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let dragStart {
            offset.x += point.x - dragStart.x
            offset.y += point.y - dragStart.y
            needsDisplay = true
        }
        self.dragStart = point
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }
}
