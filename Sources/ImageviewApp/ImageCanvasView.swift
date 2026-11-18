import AppKit
import ImageviewCore

final class ImageCanvasView: NSView {
    enum ZoomMode {
        case fit
        case actualSize
    }

    var onOpenURLs: (([URL]) -> Void)?
    var onNavigate: ((Bool) -> Void)?
    var onBeginCropRequested: (() -> Bool)?
    var onCropChanged: ((NormalizedRect) -> Void)?
    var onCancelCrop: (() -> Void)?

    private(set) var hasCropSelection = false
    var isCropMode: Bool { cropMode }

    var image: CGImage? {
        didSet {
            needsDisplay = true
        }
    }
    var errorMessage: String? {
        didSet { needsDisplay = true }
    }
    var isLoading = false {
        didSet { needsDisplay = true }
    }

    private var zoomMode: ZoomMode = .fit
    private var zoomScale: CGFloat = 1
    private var panOffset = CGPoint.zero
    private var lastDragPoint: CGPoint?
    private var cropMode = false
    private var crop = NormalizedRect.full
    private var cropDrag: CropDrag?

    private struct CropDrag {
        let startPoint: CGPoint
        let startCrop: NormalizedRect?
        let edges: CropResizeEdges
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        setAccessibilityIdentifier("imageCanvas")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        if let image {
            let drawingRect = imageRect(for: image)
            NSImage(cgImage: image, size: drawingRect.size).draw(
                in: drawingRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
            )
            if cropMode, hasCropSelection {
                drawCropOverlay(in: drawingRect)
            }
        } else {
            let message = errorMessage
                ?? (isLoading ? L10n.text("viewer.loading") : L10n.text("viewer.empty"))
            drawCentered(message)
        }
    }

    func fitToWindow() {
        zoomMode = .fit
        zoomScale = 1
        panOffset = .zero
        needsDisplay = true
    }

    func present(_ image: CGImage?, resetViewport: Bool) {
        self.image = image
        if resetViewport {
            zoomMode = .fit
            zoomScale = 1
            panOffset = .zero
        }
        needsDisplay = true
    }

    func showActualSize() {
        zoomMode = .actualSize
        zoomScale = 1
        panOffset = .zero
        needsDisplay = true
    }

    func beginCrop() {
        cropMode = true
        hasCropSelection = false
        cropDrag = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func endCrop() {
        cropMode = false
        hasCropSelection = false
        cropDrag = nil
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.control) || abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            let factor = exp(-event.scrollingDeltaY * 0.015)
            zoomMode = .actualSize
            zoomScale = min(max(zoomScale * factor, 0.05), 32)
            needsDisplay = true
        } else if abs(event.scrollingDeltaX) > 4 {
            onNavigate?(event.scrollingDeltaX < 0)
        }
    }

    override func magnify(with event: NSEvent) {
        zoomMode = .actualSize
        zoomScale = min(max(zoomScale * (1 + event.magnification), 0.05), 32)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastDragPoint = nil
        cropDrag = nil
        guard let image else {
            return
        }
        let imageRect = imageRect(for: image)
        let intent = ImageCanvasInteraction.primaryDragIntent(
            startsInsideImage: imageRect.contains(point),
            optionPressed: event.modifierFlags.contains(.option)
        )
        switch intent {
        case .pan:
            lastDragPoint = point
        case .cropSelection:
            if !cropMode, onBeginCropRequested?() != true {
                return
            }
            if hasCropSelection {
                let displayRect = cropDisplayRect(in: imageRect)
                let edges = cropEdges(at: point, cropRect: displayRect)
                if !edges.isEmpty {
                    cropDrag = CropDrag(startPoint: point, startCrop: crop, edges: edges)
                    return
                }
            }
            cropDrag = CropDrag(startPoint: point, startCrop: nil, edges: [])
        case nil:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let cropDrag, let image {
            let imageRect = imageRect(for: image)
            if cropDrag.startCrop != nil {
                updateCropDrag(
                    cropDrag,
                    currentPoint: point,
                    imageRect: imageRect
                )
            } else if let selection = CropGeometry.normalizedSelection(
                from: cropDrag.startPoint,
                to: point,
                inside: imageRect
            ) {
                hasCropSelection = true
                updateCrop(selection)
            }
            return
        }
        if let lastDragPoint {
            panOffset.x += point.x - lastDragPoint.x
            panOffset.y += point.y - lastDragPoint.y
            needsDisplay = true
        }
        lastDragPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
        cropDrag = nil
    }

    override func cancelOperation(_ sender: Any?) {
        if cropMode {
            onCancelCrop?()
        } else {
            super.cancelOperation(sender)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
        guard !urls.isEmpty else {
            return false
        }
        onOpenURLs?(urls)
        return true
    }

    private func imageRect(for image: CGImage) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        let baseScale: CGFloat
        switch zoomMode {
        case .fit:
            baseScale = min(
                bounds.width / max(imageSize.width, 1),
                bounds.height / max(imageSize.height, 1)
            )
        case .actualSize:
            baseScale = 1
        }
        let scale = baseScale * zoomScale
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2 + panOffset.x,
            y: bounds.midY - size.height / 2 + panOffset.y,
            width: size.width,
            height: size.height
        )
    }

    private func drawCropOverlay(in imageRect: CGRect) {
        let cropRect = cropDisplayRect(in: imageRect)
        NSColor.black.withAlphaComponent(0.58).setFill()
        let outside = NSBezierPath(rect: imageRect)
        outside.appendRect(cropRect)
        outside.windingRule = .evenOdd
        outside.fill()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: cropRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        NSColor.white.withAlphaComponent(0.55).setStroke()
        for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
            let vertical = NSBezierPath()
            vertical.move(to: CGPoint(x: cropRect.minX + cropRect.width * fraction, y: cropRect.minY))
            vertical.line(to: CGPoint(x: cropRect.minX + cropRect.width * fraction, y: cropRect.maxY))
            vertical.stroke()

            let horizontal = NSBezierPath()
            horizontal.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + cropRect.height * fraction))
            horizontal.line(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + cropRect.height * fraction))
            horizontal.stroke()
        }

        NSColor.white.setFill()
        for point in [
            CGPoint(x: cropRect.minX, y: cropRect.minY),
            CGPoint(x: cropRect.midX, y: cropRect.minY),
            CGPoint(x: cropRect.maxX, y: cropRect.minY),
            CGPoint(x: cropRect.minX, y: cropRect.midY),
            CGPoint(x: cropRect.maxX, y: cropRect.midY),
            CGPoint(x: cropRect.minX, y: cropRect.maxY),
            CGPoint(x: cropRect.midX, y: cropRect.maxY),
            CGPoint(x: cropRect.maxX, y: cropRect.maxY),
        ] {
            CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8).fill()
        }
    }

    private func cropDisplayRect(in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + crop.x * imageRect.width,
            y: imageRect.minY + crop.y * imageRect.height,
            width: crop.width * imageRect.width,
            height: crop.height * imageRect.height
        )
    }

    private func cropEdges(at point: CGPoint, cropRect: CGRect) -> CropResizeEdges {
        CropGeometry.resizeEdges(
            at: point,
            cropRect: cropRect,
            hitDistance: 12
        )
    }

    private func updateCropDrag(
        _ drag: CropDrag,
        currentPoint: CGPoint,
        imageRect: CGRect
    ) {
        guard let startCrop = drag.startCrop,
              imageRect.width > 0,
              imageRect.height > 0 else {
            return
        }
        updateCrop(
            CropGeometry.resizedSelection(
                startCrop,
                from: drag.startPoint,
                to: currentPoint,
                imageRect: imageRect,
                edges: drag.edges,
                minimumSize: 0.01
            )
        )
    }

    private func updateCrop(_ crop: NormalizedRect) {
        self.crop = crop
        onCropChanged?(crop)
        needsDisplay = true
    }

    private func drawCentered(_ message: String) {
        if errorMessage == nil, !isLoading,
           let symbol = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil) {
            let configuration = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
            let image = symbol.withSymbolConfiguration(configuration) ?? symbol
            image.draw(
                in: CGRect(x: bounds.midX - 28, y: bounds.midY - 64, width: 56, height: 56),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]
        let textRect = CGRect(
            x: 40,
            y: bounds.midY + (errorMessage == nil && !isLoading ? 8 : -10),
            width: max(bounds.width - 80, 0),
            height: 40
        )
        message.draw(in: textRect, withAttributes: attributes)
    }
}
