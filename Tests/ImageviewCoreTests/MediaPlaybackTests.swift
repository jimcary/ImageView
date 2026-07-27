import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImageviewCore

@Test
func frameTimingReadsGIFAPNGWebPAndHEICSDictionaries() {
    let fixtures: [[CFString: Any]] = [
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 0.08]],
        [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.09]],
        [kCGImagePropertyWebPDictionary: [kCGImagePropertyWebPDelayTime: 0.10]],
        [kCGImagePropertyHEICSDictionary: [kCGImagePropertyHEICSDelayTime: 0.11]],
    ]

    #expect(fixtures.map(ImageFrameTiming.duration(from:)) == [0.08, 0.09, 0.10, 0.11])
}

@Test
func playbackPolicyClampsUnsafeDelaysAndWrapsFrames() {
    #expect(FramePlaybackPolicy.safeDelay(nil) == 0.1)
    #expect(FramePlaybackPolicy.safeDelay(0) == 0.1)
    #expect(FramePlaybackPolicy.safeDelay(0.005) == 0.02)
    #expect(FramePlaybackPolicy.safeDelay(0.25) == 0.25)
    #expect(FramePlaybackPolicy.nextFrame(after: 2, frameCount: 3) == 0)
    #expect(FramePlaybackPolicy.nextFrame(after: 0, frameCount: 1) == 0)
}

@Test
func playbackKindSeparatesDocumentsFromAnimations() {
    #expect(MediaPlaybackKind.classify(url: URL(fileURLWithPath: "/tmp/a.pdf"), frameCount: 3) == .document)
    #expect(MediaPlaybackKind.classify(url: URL(fileURLWithPath: "/tmp/a.pdf"), frameCount: 1) == .document)
    #expect(MediaPlaybackKind.classify(url: URL(fileURLWithPath: "/tmp/a.gif"), frameCount: 3) == .animation)
    #expect(MediaPlaybackKind.classify(url: URL(fileURLWithPath: "/tmp/a.webp"), frameCount: 1) == .still)
    #expect(MediaPlaybackKind.classify(url: URL(fileURLWithPath: "/tmp/a.tiff"), frameCount: 3) == .document)
}

@Test
func mediaSubimageCacheKeyIncludesPageOrFrameIndex() {
    let first = MediaSubimageKey(mediaID: "asset", index: 0)
    let second = MediaSubimageKey(mediaID: "asset", index: 1)
    #expect(first != second)
    #expect(Set([first, second]).count == 2)
}

@Test
func decoderReadsDistinctAnimatedGIFFramesAndDurations() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Imageview-\(UUID().uuidString).gif")
    defer { try? FileManager.default.removeItem(at: url) }
    let destination = try #require(
        CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            2,
            nil
        )
    )
    CGImageDestinationSetProperties(
        destination,
        [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ],
        ] as CFDictionary
    )
    let firstImage = try solidImage(red: 1, blue: 0)
    let secondImage = try solidImage(red: 0, blue: 1)
    CGImageDestinationAddImage(
        destination,
        firstImage,
        [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.08,
            ],
        ] as CFDictionary
    )
    CGImageDestinationAddImage(
        destination,
        secondImage,
        [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.12,
            ],
        ] as CFDictionary
    )
    #expect(CGImageDestinationFinalize(destination))

    let first = try ImageDecoder().decode(url: url, page: 0)
    let second = try ImageDecoder().decode(url: url, page: 1)

    #expect(first.frameCount == 2)
    #expect(first.index == 0)
    #expect(second.index == 1)
    #expect(first.duration == 0.08)
    #expect(second.duration == 0.12)
    #expect(first.playbackKind == .animation)
    #expect(second.playbackKind == .animation)
    #expect(pixelRGBA(first.image) != pixelRGBA(second.image))
}

private func solidImage(red: CGFloat, blue: CGFloat) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return try #require(context.makeImage())
}

private func pixelRGBA(_ image: CGImage) -> [UInt8] {
    guard let data = image.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data) else {
        return []
    }
    return Array(UnsafeBufferPointer(start: bytes, count: min(4, CFDataGetLength(data))))
}
