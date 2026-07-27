import CoreGraphics
import CoreImage
import Foundation
import Vision

enum SubjectExtractionError: Error {
    case noSubjectFound
    case cannotRender
}

@available(macOS 14.0, *)
struct SubjectExtractionController {
    func extract(_ image: CGImage) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else {
                throw SubjectExtractionError.noSubjectFound
            }

            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
            let source = CIImage(cgImage: image)
            let mask = CIImage(cvPixelBuffer: maskBuffer)
            let transparent = CIImage(color: .clear).cropped(to: source.extent)
            guard let filter = CIFilter(
                name: "CIBlendWithMask",
                parameters: [
                    kCIInputImageKey: source,
                    kCIInputBackgroundImageKey: transparent,
                    kCIInputMaskImageKey: mask,
                ]
            ), let output = filter.outputImage,
              let result = CIContext(options: [.cacheIntermediates: false])
                .createCGImage(output, from: source.extent) else {
                throw SubjectExtractionError.cannotRender
            }
            return result
        }.value
    }
}
