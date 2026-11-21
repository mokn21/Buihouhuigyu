import Foundation
import Observation

#if canImport(SwiftUI) && canImport(Translation)
import SwiftUI
import Translation

@available(iOS 18.0, *)
@Observable
final class AppleTranslationBridge: TextTranslationService {
    struct PendingRequest {
        let text: String
        let continuation: CheckedContinuation<String, Error>
    }

    let source = Locale.Language(identifier: "en")
    let target = Locale.Language(identifier: "ar")
    var configuration: TranslationSession.Configuration?
    private let requestStream: AsyncStream<PendingRequest>
    private let requestContinuation: AsyncStream<PendingRequest>.Continuation
    private(set) var statusMessage = "لم تبدأ الترجمة بعد."

    init() {
        let pair = AsyncStream<PendingRequest>.makeStream()
        requestStream = pair.stream
        requestContinuation = pair.continuation
        configuration = TranslationSession.Configuration(source: source, target: target)
    }

    func translate(_ text: String) async throws -> String {
        guard #available(iOS 18.0, *) else {
            throw TranslationError.unavailable("ترجمة Apple المخصصة تتطلب iPadOS 18 أو أحدث؛ التطبيق يبقى متوافقًا مع iPadOS 17.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            requestContinuation.yield(PendingRequest(text: text, continuation: continuation))
        }
    }

    @available(iOS 18.0, *)
    func run(session: TranslationSession) async {
        let availability = await LanguageAvailability().status(from: source, to: target)
        guard availability == .installed || availability == .supported else {
            statusMessage = "زوج اللغات English → Arabic غير متاح على هذا الجهاز."
            for await request in requestStream {
                request.continuation.resume(throwing: TranslationError.unavailable(statusMessage))
            }
            return
        }
        statusMessage = availability == .installed ? "نموذجا اللغة جاهزان." : "قد يطلب النظام تنزيل نماذج اللغة."
        for await request in requestStream {
            do {
                let response = try await session.translate(request.text)
                request.continuation.resume(returning: response.targetText)
            } catch {
                request.continuation.resume(throwing: error)
            }
        }
    }
}
#endif

#if !canImport(SwiftUI) || !canImport(Translation)
final class AppleTranslationBridge {}
#endif

struct DefaultTranslationService: TextTranslationService {
    func translate(_ text: String) async throws -> String {
        throw TranslationError.unavailable("لم يتم تفعيل Apple Translation على إصدار iPadOS الحالي.")
    }
}
