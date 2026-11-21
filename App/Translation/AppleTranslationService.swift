import Foundation

/// Apple Translation is intentionally kept behind this protocol. Its public
/// custom-session flow is supplied by SwiftUI's translationTask modifier, so a
/// headless translation service must not construct an unsupported session or
/// silently substitute a server API.
struct DefaultTranslationService: TextTranslationService {
    func translate(_ text: String) async throws -> String {
        throw TranslationError.unavailable("يلزم ربط Apple Translation عبر واجهة iPadOS المدعومة قبل تشغيل الترجمة العربية.")
    }
}
