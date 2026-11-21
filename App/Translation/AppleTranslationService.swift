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

    // One stream, one worker. Re-running translationTask replaces the worker;
    // it never starts a second consumer of the same stream.
    private var workerTask: Task<Void, Never>?
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
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let request = PendingRequest(id: id, text: text, continuation: continuation)
                pendingRequests[id] = request
                ledger.enqueue(id)
                requestContinuation.yield(request)
            }
        }, onCancel: {
            // The worker handles cancellation and either requeues the request
            // or completes it with an explicit error. No fake result is used.
        })
    }

    @available(iOS 18.0, *)
    func run(session: TranslationSession) async {
        workerTask?.cancel()
        sessionGeneration &+= 1
        let generation = sessionGeneration
        availabilityFailure = nil

        let worker = Task { [weak self] in
            guard let self else { return }
            await self.process(session: session, generation: generation)
        }
        workerTask = worker
        await worker.value
        if generation == sessionGeneration {
            workerTask = nil
        }
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
                if ledger.complete(request.id) {
                    pendingRequests.removeValue(forKey: request.id)
                    request.continuation.resume(returning: response.targetText)
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
