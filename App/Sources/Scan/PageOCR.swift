import UIKit
import Vision

struct RecognizedPage: Equatable, Sendable {
    let text: String
    let meanConfidence: Double
}

enum PageOCRError: Error {
    case unreadableImage
}

enum PageOCR {
    static func recognize(image: UIImage) throws -> RecognizedPage {
        guard let cgImage = image.cgImage else { throw PageOCRError.unreadableImage }
        return try perform(VNImageRequestHandler(cgImage: cgImage, options: [:]))
    }

    static func recognize(pixelBuffer: CVPixelBuffer) throws -> RecognizedPage {
        try perform(VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]))
    }

    private static func perform(_ handler: VNImageRequestHandler) throws -> RecognizedPage {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE", "en-US"]
        request.usesLanguageCorrection = true
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        let text = lines.map(\.string).joined(separator: "\n")
        let meanConfidence = lines.isEmpty
            ? 0
            : lines.map { Double($0.confidence) }.reduce(0, +) / Double(lines.count)
        return RecognizedPage(text: text, meanConfidence: meanConfidence)
    }
}
