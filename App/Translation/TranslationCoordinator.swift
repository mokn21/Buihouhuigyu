import CoreVideo
import Foundation
import Observation

@MainActor
@Observable
final class TranslationCoordinator {
    private(set) var state: TranslationState = .stopped
    private(set) var latestEntry: TranslationEntry?
    private(set) var lastError: String?
    private(set) var processedFrames = 0
    private(set) var skippedFrames = 0

    var region: CaptureRegion = .fullScreen {
        didSet { ocr.region = region }
    }
    var minimumFrameInterval: Duration = .milliseconds(250)

    private let ocr: OCRService
    private let translator: TextTranslationService
    private var task: Task<Void, Never>?
    private var lastSubmittedAt: ContinuousClock.Instant?
    private var lastSourceText = ""
    private var cache: [String: String] = [:]

    init(ocr: OCRService = OCRService(), translator: TextTranslationService = DefaultTranslationService()) {
        self.ocr = ocr
        self.translator = translator
    }

    func start() {
        task?.cancel()
        task = nil
        lastError = nil
        state = .running
    }

    func pause() {
        task?.cancel()
        task = nil
        state = .paused
    }

    func stop() {
        task?.cancel()
        task = nil
        state = .stopped
        lastSourceText = ""
    }

    func submit(pixelBuffer: CVPixelBuffer) {
        guard state == .running else {
            skippedFrames += 1
            return
        }
        let now = ContinuousClock.now
        if let lastSubmittedAt, lastSubmittedAt.duration(to: now) < minimumFrameInterval {
            skippedFrames += 1
            return
        }
        lastSubmittedAt = now
        task?.cancel()
        let ocr = self.ocr
        let translator = self.translator
        task = Task { [weak self] in
            guard let self else { return }
            guard let result = await ocr.recognize(pixelBuffer: pixelBuffer, capturedAt: now), !Task.isCancelled else { return }
            let normalized = Self.normalize(result.text)
            guard !normalized.isEmpty, normalized != self.lastSourceText else {
                self.skippedFrames += 1
                return
            }
            self.lastSourceText = normalized
            self.processedFrames += 1
            let translated: String
            if let cached = self.cache[normalized] {
                translated = cached
            } else {
                do {
                    translated = try await translator.translate(result.text)
                    guard !Task.isCancelled else { return }
                    self.cache[normalized] = translated
                } catch {
                    self.lastError = error.localizedDescription
                    self.state = .failed(error.localizedDescription)
                    return
                }
            }
            let finished = ContinuousClock.now
            self.latestEntry = TranslationEntry(
                sourceText: result.text,
                translatedText: translated,
                metrics: LatencyMetrics(
                    capturedAt: result.capturedAt,
                    ocrStartedAt: result.startedAt,
                    ocrFinishedAt: result.finishedAt,
                    translationFinishedAt: finished,
                    displayedAt: ContinuousClock.now
                )
            )
        }
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
