import AppKit
import ImageviewCore

final class ImageCanvasView: NSView {
    enum ZoomMode {
        case fit
        case actualSize
    }

    var onOpenURLs: (([URL]) -> Void)?
    var onNavigate: ((Bool) -> Void)?
    var onCropChanged: ((NormalizedRect) -> Void)?

    var image: CGImage? {
        didSet {
            if oldValue !== image {
                panOffset = .zero
            }
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
    private var cropAspect = CropAspect.free
    private var cropDrag: CropDrag?

    private struct CropDrag {
        let startPoint: CGPoint
        let startCrop: NormalizedRect
        let edges: CropEdges
    }

    private struct CropEdges: OptionSet {
        let rawValue: Int

        static let left = CropEdges(rawValue: 1 << 0)
        static let right = CropEdges(rawValue: 1 << 1)
        static let top = CropEdges(rawValue: 1 << 2)
        static let bottom = CropEdges(rawValue: 1 << 3)
        static let move = CropEdges(rawValue: 1 << 4)
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        bounds.fill()

        if let image {
            let drawingRect = imageRect(for: image)
            NSImage(cgImage: image, size: drawingRect.size).draw(
                in: drawingRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            if cropMode {
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

    func showActualSize() {
        zoomMode = .actualSize
        zoomScale = 1
        panOffset = .zero
        needsDisplay = true
    }

    func beginCrop(_ crop: NormalizedRect = .full) {
        cropMode = true
        self.crop = crop
        cropAspect = .free
        needsDisplay = true
    }

    func endCrop() {
        cropMode = false
        cropDrag = nil
        needsDisplay = true
    }

    func setCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        guard let image else {
            return
        }

        let ratio: CGFloat?
        if aspect == .original {
            ratio = CGFloat(image.width) / CGFloat(image.height)
        } else {
            ratio = aspect.ratio
        }
        guard let ratio else {
            return
        }

        let current = CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
        let constrained = constrain(current, ratio: ratio)
        updateCrop(constrained)
    }

    func setCropPixelSize(width: Int, height: Int) {
        guard let image, width > 0, height > 0 else {
            return
        }
        let normalizedWidth = min(CGFloat(width) / CGFloat(image.width), 1)
        let normalizedHeight = min(CGFloat(height) / CGFloat(image.height), 1)
        let proposed = CGRect(
            x: crop.x + (crop.width - normalizedWidth) / 2,
            y: crop.y + (crop.height - normalizedHeight) / 2,
            width: normalizedWidth,
            height: normalizedHeight
        )
        updateCrop(proposed)
    }

    func cropPixelSize() -> CGSize? {
        guard let image else {
            return nil
        }
        return CGSize(
            width: round(crop.width * CGFloat(image.width)),
            height: round(crop.height * CGFloat(image.height))
        )
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
        if cropMode, let image {
            let displayRect = cropDisplayRect(in: imageRect(for: image))
            let edges = cropEdges(at: point, cropRect: displayRect)
            if !edges.isEmpty {
                cropDrag = CropDrag(startPoint: point, startCrop: crop, edges: edges)
                return
            }
        }
        lastDragPoint = point
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let cropDrag, let image {
            updateCropDrag(cropDrag, currentPoint: point, imageRect: imageRect(for: image))
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

    private func cropEdges(at point: CGPoint, cropRect: CGRect) -> CropEdges {
        let hitDistance: CGFloat = 12
        guard cropRect.insetBy(dx: -hitDistance, dy: -hitDistance).contains(point) else {
            return []
        }

        var edges: CropEdges = []
        if abs(point.x - cropRect.minX) <= hitDistance {
            edges.insert(.left)
        }
        if abs(point.x - cropRect.maxX) <= hitDistance {
            edges.insert(.right)
        }
        if abs(point.y - cropRect.minY) <= hitDistance {
            edges.insert(.top)
        }
        if abs(point.y - cropRect.maxY) <= hitDistance {
            edges.insert(.bottom)
        }
        if edges.isEmpty, cropRect.contains(point) {
            edges = .move
        }
        return edges
    }

    private func updateCropDrag(
        _ drag: CropDrag,
        currentPoint: CGPoint,
        imageRect: CGRect
    ) {
        guard imageRect.width > 0, imageRect.height > 0 else {
            return
        }
        let deltaX = (currentPoint.x - drag.startPoint.x) / imageRect.width
        let deltaY = (currentPoint.y - drag.startPoint.y) / imageRect.height
        var proposed = CGRect(
            x: drag.startCrop.x,
            y: drag.startCrop.y,
            width: drag.startCrop.width,
            height: drag.startCrop.height
        )

        if drag.edges.contains(.move) {
            proposed.origin.x += deltaX
            proposed.origin.y += deltaY
        } else {
            if drag.edges.contains(.left) {
                proposed.origin.x += deltaX
                proposed.size.width -= deltaX
            }
            if drag.edges.contains(.right) {
                proposed.size.width += deltaX
            }
            if drag.edges.contains(.top) {
                proposed.origin.y += deltaY
                proposed.size.height -= deltaY
            }
            if drag.edges.contains(.bottom) {
                proposed.size.height += deltaY
            }
        }

        if let ratio = effectiveCropRatio() {
            proposed = constrain(proposed, ratio: ratio)
        }
        updateCrop(proposed)
    }

    private func effectiveCropRatio() -> CGFloat? {
        if cropAspect == .original, let image {
            return CGFloat(image.width) / CGFloat(image.height)
        }
        return cropAspect.ratio
    }

    private func constrain(_ proposed: CGRect, ratio: CGFloat) -> CGRect {
        let standardized = proposed.standardized
        let size: CGSize
        if standardized.width / max(standardized.height, 0.0001) > ratio {
            size = CGSize(width: standardized.height * ratio, height: standardized.height)
        } else {
            size = CGSize(width: standardized.width, height: standardized.width / ratio)
        }
        return CGRect(
            x: standardized.midX - size.width / 2,
            y: standardized.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func updateCrop(_ proposed: CGRect) {
        let minimum: CGFloat = 0.01
        var rectangle = proposed.standardized
        rectangle.size.width = min(max(rectangle.width, minimum), 1)
        rectangle.size.height = min(max(rectangle.height, minimum), 1)
        rectangle.origin.x = min(max(rectangle.origin.x, 0), 1 - rectangle.width)
        rectangle.origin.y = min(max(rectangle.origin.y, 0), 1 - rectangle.height)
        crop = NormalizedRect(
            x: rectangle.origin.x,
            y: rectangle.origin.y,
            width: rectangle.width,
            height: rectangle.height
        )
        onCropChanged?(crop)
        needsDisplay = true
    }

    private func drawCentered(_ message: String) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]
        let textRect = CGRect(
            x: 40,
            y: bounds.midY - 20,
            width: max(bounds.width - 80, 0),
            height: 40
        )
        message.draw(in: textRect, withAttributes: attributes)
    }
}
