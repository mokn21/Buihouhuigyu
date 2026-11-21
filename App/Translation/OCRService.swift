import CoreVideo
import Foundation
import Vision

struct OCRResult: Equatable {
    let text: String
    let capturedAt: ContinuousClock.Instant
    let startedAt: ContinuousClock.Instant
    let finishedAt: ContinuousClock.Instant
}

final class OCRService {
    var recognitionLevel: VNRequestTextRecognitionLevel = .fast
    var region: CaptureRegion = .fullScreen
    var sourceLanguage = "en-US"

    func recognize(pixelBuffer: CVPixelBuffer, capturedAt: ContinuousClock.Instant = ContinuousClock.now) async -> OCRResult? {
        let startedAt = ContinuousClock.now
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.recognitionLanguages = sourceLanguage == "auto" ? [] : [sourceLanguage]
        request.usesLanguageCorrection = false
        request.regionOfInterest = region.cgRect

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            log.error("Vision OCR failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return OCRResult(text: text, capturedAt: capturedAt, startedAt: startedAt, finishedAt: ContinuousClock.now)
    }
}

protocol TextTranslationService {
    func translate(_ text: String) async throws -> String
}

struct UnavailableTranslationService: TextTranslationService {
    let reason: String
    func translate(_ text: String) async throws -> String { throw TranslationError.unavailable(reason) }
}

enum TranslationError: LocalizedError {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason), .failed(let reason): return reason
        }
    }
}
