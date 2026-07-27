import CoreGraphics

public struct CropResizeEdges: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public static let left = CropResizeEdges(rawValue: 1 << 0)
    public static let right = CropResizeEdges(rawValue: 1 << 1)
    public static let top = CropResizeEdges(rawValue: 1 << 2)
    public static let bottom = CropResizeEdges(rawValue: 1 << 3)
    public static let move = CropResizeEdges(rawValue: 1 << 4)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public enum CropAspect: String, CaseIterable, Sendable {
    case free
    case original
    case square
    case oneByTwo
    case twoByOne
    case twoByThree
    case threeByTwo
    case threeByFour
    case fourByThree
    case nineBySixteen
    case sixteenByNine

    public var ratio: CGFloat? {
        switch self {
        case .free, .original:
            nil
        case .square:
            1
        case .oneByTwo:
            1.0 / 2.0
        case .twoByOne:
            2.0
        case .twoByThree:
            2.0 / 3.0
        case .threeByTwo:
            3.0 / 2.0
        case .threeByFour:
            3.0 / 4.0
        case .fourByThree:
            4.0 / 3.0
        case .nineBySixteen:
            9.0 / 16.0
        case .sixteenByNine:
            16.0 / 9.0
        }
    }
}

public struct CropGeometry: Sendable {
    public let crop: NormalizedRect

    public init(crop: NormalizedRect) {
        self.crop = crop
    }

    public static func normalizedSelection(
        from start: CGPoint,
        to end: CGPoint,
        inside bounds: CGRect
    ) -> NormalizedRect? {
        let bounds = bounds.standardized
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let selection = CGRect(
            x: start.x,
            y: start.y,
            width: end.x - start.x,
            height: end.y - start.y
        ).standardized.intersection(bounds)
        guard !selection.isNull, selection.width >= 1, selection.height >= 1 else {
            return nil
        }

        return NormalizedRect(
            x: (selection.minX - bounds.minX) / bounds.width,
            y: (selection.minY - bounds.minY) / bounds.height,
            width: selection.width / bounds.width,
            height: selection.height / bounds.height
        )
    }

    public func pixelRect(imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        let originX = floor(crop.x * imageSize.width)
        let originY = floor(crop.y * imageSize.height)
        let maximumX = ceil((crop.x + crop.width) * imageSize.width)
        let maximumY = ceil((crop.y + crop.height) * imageSize.height)
        return CGRect(
            x: originX,
            y: originY,
            width: min(maximumX, imageSize.width) - originX,
            height: min(maximumY, imageSize.height) - originY
        )
    }

    public static func constrain(
        _ proposed: CGRect,
        to aspect: CropAspect,
        inside bounds: CGRect
    ) -> CGRect {
        let available = proposed.standardized.intersection(bounds.standardized)
        guard !available.isNull, available.width > 0, available.height > 0,
              let ratio = aspect.ratio, ratio > 0 else {
            return available.isNull ? .zero : available
        }

        var size = available.size
        if size.width / size.height > ratio {
            size.width = size.height * ratio
        } else {
            size.height = size.width / ratio
        }

        let center = CGPoint(x: available.midX, y: available.midY)
        var origin = CGPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
        )
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    public static func resizeEdges(
        at point: CGPoint,
        cropRect: CGRect,
        hitDistance: CGFloat
    ) -> CropResizeEdges {
        guard cropRect.insetBy(dx: -hitDistance, dy: -hitDistance).contains(point) else {
            return []
        }

        var edges: CropResizeEdges = []
        let horizontal = [
            (CropResizeEdges.left, abs(point.x - cropRect.minX)),
            (.right, abs(point.x - cropRect.maxX)),
        ].filter { $0.1 <= hitDistance }.min { $0.1 < $1.1 }
        let vertical = [
            (CropResizeEdges.top, abs(point.y - cropRect.minY)),
            (.bottom, abs(point.y - cropRect.maxY)),
        ].filter { $0.1 <= hitDistance }.min { $0.1 < $1.1 }

        if let horizontal {
            edges.insert(horizontal.0)
        }
        if let vertical {
            edges.insert(vertical.0)
        }
        if edges.isEmpty, cropRect.contains(point) {
            edges.insert(.move)
        }
        return edges
    }

    public static func resizedSelection(
        _ original: NormalizedRect,
        from startPoint: CGPoint,
        to currentPoint: CGPoint,
        imageRect: CGRect,
        edges: CropResizeEdges,
        minimumSize: CGFloat
    ) -> NormalizedRect {
        guard imageRect.width > 0, imageRect.height > 0 else {
            return original
        }

        let deltaX = (currentPoint.x - startPoint.x) / imageRect.width
        let deltaY = (currentPoint.y - startPoint.y) / imageRect.height
        let minimum = min(max(minimumSize, 0), 1)
        var minX = original.x
        var maxX = original.x + original.width
        var minY = original.y
        var maxY = original.y + original.height

        if edges.contains(.move) {
            minX = min(max(minX + deltaX, 0), 1 - original.width)
            minY = min(max(minY + deltaY, 0), 1 - original.height)
            maxX = minX + original.width
            maxY = minY + original.height
        } else {
            if edges.contains(.left) {
                minX = min(max(minX + deltaX, 0), maxX - minimum)
            }
            if edges.contains(.right) {
                maxX = max(min(maxX + deltaX, 1), minX + minimum)
            }
            if edges.contains(.top) {
                minY = min(max(minY + deltaY, 0), maxY - minimum)
            }
            if edges.contains(.bottom) {
                maxY = max(min(maxY + deltaY, 1), minY + minimum)
            }
        }

        return NormalizedRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}
