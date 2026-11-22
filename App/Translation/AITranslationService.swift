import Foundation

#if canImport(CoreML) && canImport(Tokenizers)
import CoreML
import Tokenizers

@available(iOS 18.0, *)
final class OpusMTEnglishArabicService: TextTranslationService {
    private let encoder: MLModel?
    private let decoder: MLModel?
    private var sourceTokenizer: Tokenizer?
    private var targetTokenizer: Tokenizer?
    private let sourceTokenizerJSONURL: URL?
    private let sourceTokenizerConfigURL: URL?
    private let targetTokenizerJSONURL: URL?
    private let targetTokenizerConfigURL: URL?
    private let initializationError: Error?
    private let maxTokens = 64
    private let padTokenID = 61246
    private let eosTokenID = 25897
    private let decoderStartTokenID = 61246
    private let arabicPrefixTokenID = 4212
    private let lock = NSLock()

    init() {
        sourceTokenizer = nil
        targetTokenizer = nil
        do {
            guard
                let encoderURL = Bundle.main.url(forResource: "OpusMTEnglishArabicEncoder", withExtension: "mlmodelc"),
                let decoderURL = Bundle.main.url(forResource: "OpusMTEnglishArabicDecoder", withExtension: "mlmodelc"),
                let sourceJSON = Bundle.main.url(forResource: "source-tokenizer", withExtension: "json"),
                let sourceConfig = Bundle.main.url(forResource: "source-tokenizer-config", withExtension: "json"),
                let targetJSON = Bundle.main.url(forResource: "target-tokenizer", withExtension: "json"),
                let targetConfig = Bundle.main.url(forResource: "target-tokenizer-config", withExtension: "json")
            else { throw TranslationError.unavailable("لم يتم تضمين ملفات tokenizer الخاصة بنموذج OPUS-MT.") }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            encoder = try MLModel(contentsOf: encoderURL, configuration: configuration)
            decoder = try MLModel(contentsOf: decoderURL, configuration: configuration)
            sourceTokenizerJSONURL = sourceJSON
            sourceTokenizerConfigURL = sourceConfig
            targetTokenizerJSONURL = targetJSON
            targetTokenizerConfigURL = targetConfig
            initializationError = nil
        } catch {
            encoder = nil
            decoder = nil
            sourceTokenizer = nil
            targetTokenizer = nil
            sourceTokenizerJSONURL = nil
            sourceTokenizerConfigURL = nil
            targetTokenizerJSONURL = nil
            targetTokenizerConfigURL = nil
            initializationError = error
        }
    }

    func translate(_ text: String) async throws -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw TranslationError.failed("لا يوجد نص لترجمته.") }
        try await loadTokenizersIfNeeded()
        return try await Task.detached(priority: .userInitiated) { [self] in
            try self.translateSynchronously(cleaned)
        }.value
    }

    private func loadTokenizersIfNeeded() async throws {
        if sourceTokenizer != nil, targetTokenizer != nil { return }
        if let initializationError { throw initializationError }
        guard let sourceTokenizerJSONURL, let sourceTokenizerConfigURL,
              let targetTokenizerJSONURL, let targetTokenizerConfigURL else {
            throw TranslationError.unavailable("لم يتم تضمين ملفات tokenizer الخاصة بنموذج OPUS-MT.")
        }
        let sourceFolder = try makeTokenizerFolder(
            prefix: "source",
            json: sourceTokenizerJSONURL,
            config: sourceTokenizerConfigURL
        )
        let targetFolder = try makeTokenizerFolder(
            prefix: "target",
            json: targetTokenizerJSONURL,
            config: targetTokenizerConfigURL
        )
        sourceTokenizer = try await AutoTokenizer.from(modelFolder: sourceFolder, strict: false)
        targetTokenizer = try await AutoTokenizer.from(modelFolder: targetFolder, strict: false)
    }

    private func makeTokenizerFolder(prefix: String, json: URL, config: URL) throws -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrionSubtitles/\(prefix)-tokenizer", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tokenizerJSON = root.appendingPathComponent("tokenizer.json")
        let tokenizerConfig = root.appendingPathComponent("tokenizer_config.json")
        if !FileManager.default.fileExists(atPath: tokenizerJSON.path) {
            try FileManager.default.copyItem(at: json, to: tokenizerJSON)
        }
        if !FileManager.default.fileExists(atPath: tokenizerConfig.path) {
            try FileManager.default.copyItem(at: config, to: tokenizerConfig)
        }
        return root
    }

    private func translateSynchronously(_ text: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if let initializationError { throw initializationError }
        guard let encoder, let decoder, let sourceTokenizer, let targetTokenizer else {
            throw TranslationError.unavailable("لم يتم تحميل نموذج OPUS-MT المحلي.")
        }

        var sourceIDs = sourceTokenizer.encode(text: text, addSpecialTokens: false).map(Int32.init)
        sourceIDs.insert(Int32(arabicPrefixTokenID), at: 0)
        if sourceIDs.last != Int32(eosTokenID) { sourceIDs.append(Int32(eosTokenID)) }
        sourceIDs = Array(sourceIDs.prefix(maxTokens))
        let sourceInput = try makeArray(values: sourceIDs, count: maxTokens, fill: Int32(padTokenID))
        let sourceMask = try makeArray(values: Array(repeating: Int32(1), count: sourceIDs.count), count: maxTokens, fill: 0)
        let encoded = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: sourceInput),
            "attention_mask": MLFeatureValue(multiArray: sourceMask),
        ]))
        guard let hidden = encoded.featureValue(for: "encoder_hidden_states")?.multiArrayValue else {
            throw TranslationError.failed("لم يُرجع نموذج OPUS-MT مخرجات المشفر.")
        }

        var outputIDs = [Int32(decoderStartTokenID)]
        for step in 0..<(maxTokens - 1) {
            let decoderInput = try makeArray(values: outputIDs, count: maxTokens, fill: Int32(padTokenID))
            let result = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "decoder_input_ids": MLFeatureValue(multiArray: decoderInput),
                "encoder_hidden_states": MLFeatureValue(multiArray: hidden),
                "encoder_attention_mask": MLFeatureValue(multiArray: sourceMask),
            ]))
            guard let logits = result.featureValue(for: "logits")?.multiArrayValue else {
                throw TranslationError.failed("لم يُرجع نموذج OPUS-MT مخرجات المولد.")
            }
            let next = argmax(logits, timestep: step)
            outputIDs.append(Int32(next))
            if next == eosTokenID { break }
        }

        let decodedIDs = outputIDs.filter { $0 != Int32(decoderStartTokenID) && $0 != Int32(eosTokenID) }
        let translated = targetTokenizer.decode(tokens: decodedIDs.map(Int.init), skipSpecialTokens: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else {
            throw TranslationError.failed("أعاد نموذج OPUS-MT نتيجة فارغة؛ لم تُعرض ترجمة وهمية.")
        }
        return translated
    }

    private func makeArray(values: [Int32], count: Int, fill: Int32) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .int32)
        for index in 0..<count { array[index] = NSNumber(value: index < values.count ? values[index] : fill) }
        return array
    }

    private func argmax(_ logits: MLMultiArray, timestep: Int) -> Int {
        let dimensions = logits.shape.map { $0.intValue }
        let vocabulary = dimensions.last ?? 0
        let stride = vocabulary
        var bestID = 0
        var bestValue = -Double.infinity
        let base = timestep * stride
        for token in 0..<vocabulary {
            let value = logits[base + token].doubleValue
            if value > bestValue { bestValue = value; bestID = token }
        }
        return bestID
    }
}

@available(iOS 18.0, *)
struct TranslationFallbackService: TextTranslationService {
    let primary: TextTranslationService
    let fallback: TextTranslationService

    func translate(_ text: String) async throws -> String {
        do { return try await primary.translate(text) }
        catch { return try await fallback.translate(text) }
    }
}
#else
struct OpusMTEnglishArabicService: TextTranslationService {
    func translate(_ text: String) async throws -> String {
        throw TranslationError.unavailable("محرك OPUS-MT يتطلب iPadOS 18 وCore ML وحزمة Tokenizers.")
    }
}
#endif
