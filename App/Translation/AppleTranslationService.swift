import Foundation
import Observation

#if canImport(SwiftUI) && canImport(Translation)
import SwiftUI
import Translation

@available(iOS 18.0, *)
@Observable
final class AppleTranslationBridge: TextTranslationService {
    struct PendingRequest {
        let id: UUID
        let text: String
        let continuation: CheckedContinuation<String, Error>
    }

    let source = Locale.Language(identifier: "en")
    let target = Locale.Language(identifier: "ar")
    var configuration: TranslationSession.Configuration?
    private let requestStream: AsyncStream<PendingRequest>
    private let requestContinuation: AsyncStream<PendingRequest>.Continuation
    private(set) var statusMessage = "لم تبدأ الترجمة بعد."
    private(set) var sessionReady = false

    // One stream, one worker. The worker runs inside the structured
    // translationTask action, so SwiftUI cancellation also cancels the Apple
    // session before its view disappears.
    private var sessionGeneration: UInt64 = 0
    private var ledger = TranslationRequestLedger()
    private var pendingRequests: [UUID: PendingRequest] = [:]
    private var availabilityFailure: TranslationError?

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
        if let availabilityFailure {
            throw availabilityFailure
        }

        let id = UUID()
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw TranslationError.failed("انتهت جلسة الترجمة.") }
                return try await self.enqueueAndWait(id: id, text: text)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw TranslationError.failed("لم تستجب جلسة Apple Translation خلال 20 ثانية. تحقق من الجلسة ونماذج اللغة ثم حاول مرة أخرى.")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw TranslationError.failed("لم تُرجع جلسة Apple Translation نتيجة.")
            }
            return result
        }
    }

    private func enqueueAndWait(id: UUID, text: String) async throws -> String {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let request = PendingRequest(id: id, text: text, continuation: continuation)
                pendingRequests[id] = request
                ledger.enqueue(id)
                requestContinuation.yield(request)
            }
        }, onCancel: {
            self.cancelRequest(id)
        })
    }

    private func cancelRequest(_ id: UUID) {
        guard let request = pendingRequests.removeValue(forKey: id), ledger.complete(id) else { return }
        request.continuation.resume(throwing: TranslationError.failed("أُلغي طلب الترجمة قبل عودة النتيجة."))
    }

    @available(iOS 18.0, *)
    func run(session: TranslationSession) async {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        availabilityFailure = nil
        sessionReady = false
        statusMessage = "جارٍ تشغيل جلسة Apple Translation…"

        // Do not create an unstructured Task here. Apple invalidates a
        // TranslationSession when the attached view disappears or its
        // configuration changes; keeping the session in a detached child task
        // can therefore lead to a fatal error on the next translate call.
        await process(session: session, generation: generation)
    }

    @available(iOS 18.0, *)
    private func process(session: TranslationSession, generation: UInt64) async {
        let availability = await LanguageAvailability().status(from: source, to: target)
        guard availability == .installed || availability == .supported else {
            let error = TranslationError.unavailable("لا تتوفر ترجمة English إلى العربية على هذا الجهاز. لم تُعرض ترجمة وهمية.")
            availabilityFailure = error
            statusMessage = error.localizedDescription
            failPending(with: error)
            return
        }

        statusMessage = availability == .installed
            ? "نماذج ترجمة English إلى العربية جاهزة."
            : "نماذج ترجمة English إلى العربية غير مثبتة؛ سيطلب النظام تنزيلها."

        if availability == .supported {
            do {
                statusMessage = "جارٍ طلب تنزيل نماذج English إلى العربية…"
                try await session.prepareTranslation()
                statusMessage = "تم تنزيل نماذج English إلى العربية وأصبحت جاهزة."
            } catch {
                let failure = TranslationError.failed("تعذر تنزيل نماذج Apple Translation. وافق على التنزيل وتحقق من اتصال الإنترنت ثم حاول مرة أخرى.")
                availabilityFailure = failure
                statusMessage = failure.localizedDescription
                failPending(with: failure)
                return
            }
        }

        sessionReady = true
        statusMessage = "جلسة Apple Translation جاهزة للترجمة الإنجليزية إلى العربية."

        for await request in requestStream {
            guard generation == sessionGeneration, !Task.isCancelled else {
                // Leave the current stream item available to the replacement
                // worker. The pending continuation is still alive.
                requestContinuation.yield(request)
                return
            }
            guard ledger.claim(request.id) else {
                // A duplicate stream item or an already completed request.
                continue
            }

            do {
                let response = try await session.translate(request.text)
                if Task.isCancelled || generation != sessionGeneration {
                    ledger.requeue(request.id)
                    requestContinuation.yield(request)
                    return
                }
                let translatedText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translatedText.isEmpty else {
                    throw TranslationError.failed("أعاد Apple Translation نتيجة فارغة؛ لم تُعرض ترجمة وهمية.")
                }
                if ledger.complete(request.id) {
                    pendingRequests.removeValue(forKey: request.id)
                    request.continuation.resume(returning: translatedText)
                }
            } catch is CancellationError {
                ledger.requeue(request.id)
                requestContinuation.yield(request)
                return
            } catch {
                _ = ledger.complete(request.id)
                pendingRequests.removeValue(forKey: request.id)
                request.continuation.resume(throwing: TranslationError.failed(Self.arabicErrorMessage(for: error)))
            }
        }
    }

    private func failPending(with error: TranslationError) {
        let requests = Array(pendingRequests.values)
        pendingRequests.removeAll()
        for request in requests where ledger.complete(request.id) {
            request.continuation.resume(throwing: error)
        }
    }

    private static func arabicErrorMessage(for error: Error) -> String {
        if let translationError = error as? TranslationError, let message = translationError.errorDescription {
            return message
        }
        return "تعذرت ترجمة النص بواسطة Apple Translation. تحقق من توفر نماذج اللغة ثم حاول مرة أخرى."
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
