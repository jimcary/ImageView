import CoreGraphics
import Foundation
import Vision

enum OCRControllerError: Error {
    case noTextFound
}

struct OCRController {
    func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var recognizedLines: [String] = []
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    return
                }
                recognizedLines = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let text = recognizedLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw OCRControllerError.noTextFound
            }
            return text
        }.value
    }
}
