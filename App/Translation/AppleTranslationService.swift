import Foundation

#if canImport(Translation)
import Translation

/// Local, on-device translation. iPadOS 17.4 provides the framework; the
/// single-string API is guarded at iPadOS 18 because that is its documented
/// availability in the current SDK.
@available(iOS 18.0, iPadOS 18.0, *)
struct AppleTranslationService: TextTranslationService {
    func translate(_ text: String) async throws -> String {
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "ar")
        )
        let response = try await session.translate(text)
        return response.targetText
    }
}
#endif

struct DefaultTranslationService: TextTranslationService {
    func translate(_ text: String) async throws -> String {
        #if canImport(Translation)
        if #available(iOS 18.0, iPadOS 18.0, *) {
            return try await AppleTranslationService().translate(text)
        }
        #endif
        throw TranslationError.unavailable("الترجمة المحلية تتطلب iPadOS 18 أو أحدث.")
    }
}
