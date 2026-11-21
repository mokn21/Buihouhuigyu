import CoreVideo
import Foundation
import Observation

@Observable
final class TranslationCoordinator {
    private(set) var state: TranslationState = .stopped
    private(set) var latestEntry: TranslationEntry?
    private(set) var lastError: String?
	private(set) var processedFrames = 0
	private(set) var skippedFrames = 0
	private(set) var ocrStatusMessage = "لم يبدأ OCR بعد."
	private(set) var lastDetectedText = ""
	private(set) var translationStatusMessage = "لم يُرسل نص إلى الترجمة بعد."
	private(set) var submittedTranslationCount = 0
	private(set) var returnedTranslationCount = 0

    var region: CaptureRegion = .fullScreen {
        didSet { ocr.region = region }
    }
    var sourceLanguage = "en-US" {
        didSet { ocr.sourceLanguage = sourceLanguage }
    }
    var minimumFrameInterval: Duration = .milliseconds(250)

    private let ocr: OCRService
    private let translator: TextTranslationService
    private var ocrTask: Task<Void, Never>?
    private var translationTasks: [UInt64: Task<Void, Never>] = [:]
    private var lastSubmittedAt: ContinuousClock.Instant?
    private var lastSourceText = ""
    private var nextGeneration: UInt64 = 0
    private var cache: [String: String] = [:]

    let appleTranslationBridge: AnyObject?

    init(ocr: OCRService = OCRService(), translator: TextTranslationService? = nil) {
        self.ocr = ocr
        self.ocr.sourceLanguage = "en-US"
#if canImport(SwiftUI) && canImport(Translation)
        if #available(iOS 18.0, *) {
            let bridge = AppleTranslationBridge()
            self.appleTranslationBridge = bridge
            self.translator = translator ?? bridge
        } else {
            self.appleTranslationBridge = nil
            self.translator = translator ?? DefaultTranslationService()
        }
#else
        self.appleTranslationBridge = nil
        self.translator = translator ?? DefaultTranslationService()
#endif
    }

	func start() {
        ocrTask?.cancel()
        ocrTask = nil
		lastError = nil
		ocrStatusMessage = "OCR يعمل وينتظر إطارًا نصيًا."
		translationStatusMessage = "بانتظار نص إنجليزي من OCR."
		state = .running
    }

    func pause() {
        ocrTask?.cancel()
        ocrTask = nil
        state = .paused
    }

    func stop() {
        ocrTask?.cancel()
        ocrTask = nil
        translationTasks.values.forEach { $0.cancel() }
        translationTasks.removeAll()
		state = .stopped
		lastSourceText = ""
		ocrStatusMessage = "تم إيقاف OCR والترجمة."
		translationStatusMessage = "تم إيقاف الترجمة."
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

        // Only OCR is replaced by a newer frame. A translation already in
        // progress is allowed to finish; its generation controls visibility.
        ocrTask?.cancel()
        let ocr = self.ocr
        ocrTask = Task { [weak self] in
            guard let self else { return }
			guard let result = await ocr.recognize(pixelBuffer: pixelBuffer, capturedAt: now), !Task.isCancelled else {
				self.ocrStatusMessage = "لم يُكتشف نص في آخر إطار."
				return
			}
			self.ocrStatusMessage = "اكتشف OCR نصًا إنجليزيًا."
			self.acceptOCR(result)
        }
    }

    private func acceptOCR(_ result: OCRResult) {
        let normalized = Self.normalize(result.text)
        guard !normalized.isEmpty, normalized != lastSourceText else {
            skippedFrames += 1
            return
        }
		lastSourceText = normalized
		lastDetectedText = result.text
		processedFrames += 1
        nextGeneration &+= 1
        let generation = nextGeneration
        let translator = self.translator

		if let cached = cache[normalized] {
			translationStatusMessage = "تمت إعادة استخدام ترجمة محفوظة."
			publish(cached, source: result, generation: generation)
			return
		}

		translationStatusMessage = "أُرسل النص إلى Apple Translation…"
		submittedTranslationCount += 1
		let task = Task { [weak self] in
            guard let self else { return }
            do {
                let translated = try await translator.translate(result.text)
                guard !Task.isCancelled else { return }
				self.cache[normalized] = translated
				self.returnedTranslationCount += 1
				self.translationStatusMessage = "عادت ترجمة عربية من Apple Translation."
				self.publish(translated, source: result, generation: generation)
			} catch {
                guard !Task.isCancelled else { return }
				self.lastError = error.localizedDescription
				self.translationStatusMessage = "فشلت الترجمة: \(error.localizedDescription)"
                self.state = .failed(error.localizedDescription)
            }
            self.translationTasks[generation] = nil
        }
        translationTasks[generation] = task
    }

    private func publish(_ translated: String, source: OCRResult, generation: UInt64) {
        // A late translation may finish, but it must never replace a newer one.
        guard generation == nextGeneration, (state == .running || state == .paused) else { return }
        let finished = ContinuousClock.now
        latestEntry = TranslationEntry(
            sourceText: source.text,
            translatedText: translated,
            metrics: LatencyMetrics(
                capturedAt: source.capturedAt,
                ocrStartedAt: source.startedAt,
                ocrFinishedAt: source.finishedAt,
                translationFinishedAt: finished,
                displayedAt: ContinuousClock.now
            )
        )
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
