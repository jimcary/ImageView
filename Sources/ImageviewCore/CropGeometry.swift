import CoreGraphics

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
}
