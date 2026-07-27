import AppKit

@MainActor
final class PinboardWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    convenience init(image: NSImage) {
        let imageView = PinImageView(image: image)
        let sourceSize = image.size
        let scale = min(1, min(520 / max(sourceSize.width, 1), 520 / max(sourceSize.height, 1)))
        let size = NSSize(
            width: max(sourceSize.width * scale, 160),
            height: max(sourceSize.height * scale, 120)
        )
        self.init(contentView: imageView, size: size, title: L10n.text("pin.image"))
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
            title: L10n.text("pin.text")
        )
    }

    private init(contentView: NSView, size: NSSize, title: String) {
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

    @objc private func closePin(_ sender: Any?) {
        close()
    }
}

@MainActor
private final class PinImageView: NSView {
    private let image: NSImage
    private var scale: CGFloat = 1
    private var offset = CGPoint.zero
    private var dragStart: CGPoint?

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(
            x: bounds.midX - size.width / 2 + offset.x,
            y: bounds.midY - size.height / 2 + offset.y,
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
