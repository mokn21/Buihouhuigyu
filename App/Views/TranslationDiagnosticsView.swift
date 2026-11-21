import SwiftUI

struct TranslationDiagnosticsView: View {
    let coordinator: TranslationCoordinator
    let bridge: AnyObject?
    @Environment(\.dismiss) private var dismiss
    @State private var results: [(String, String)] = []
    @State private var running = false
    @State private var status = "لم يبدأ الاختبار."
    @State private var elapsedMilliseconds: Double?

    private let samples = ["Hello", "Press start", "The door is locked"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    diagnosticCard(title: "حالة OCR", value: coordinator.ocrStatusMessage)
                    diagnosticCard(title: "آخر نص مكتشف", value: coordinator.lastDetectedText.isEmpty ? "لا يوجد نص مكتشف بعد." : coordinator.lastDetectedText)
                    diagnosticCard(title: "حالة الترجمة", value: coordinator.translationStatusMessage)
                    diagnosticCard(title: "آخر خطأ", value: coordinator.lastError ?? "لا يوجد خطأ مسجل.")
                    diagnosticCard(title: "الإطارات المعالجة", value: "\(coordinator.processedFrames) — المتخطاة: \(coordinator.skippedFrames)")
                    diagnosticCard(title: "طلبات الترجمة", value: "أُرسلت: \(coordinator.submittedTranslationCount) — عادت: \(coordinator.returnedTranslationCount)")

                    Divider()
                    Text("اختبار Apple Translation الحقيقي")
                        .font(.headline)
                    Text("يُرسل هذا الاختبار ثلاث جمل إلى Apple Translation. لا توجد نتائج ثابتة؛ عند عدم توفر الجلسة أو النماذج سيظهر سبب الفشل.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .rightToLeft)
                    Button(running ? "جارٍ الاختبار…" : "اختبار الترجمة") {
                        runTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)

                    diagnosticCard(title: "حالة الاختبار", value: status)
                    if let elapsedMilliseconds {
                        diagnosticCard(title: "زمن الاختبار", value: String(format: "%.0f مللي ثانية", elapsedMilliseconds))
                    }
                    ForEach(results, id: \.0) { source, target in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("الإنجليزية: \(source)").font(.subheadline.weight(.semibold))
                            Text("العربية: \(target)").font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
                .environment(\.layoutDirection, .rightToLeft)
            }
            .navigationTitle("تشخيص الترجمة")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func diagnosticCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func runTest() {
        guard !running else { return }
        running = true
        results = []
        status = "جارٍ إرسال النصوص إلى Apple Translation…"
        let started = ContinuousClock.now
        Task {
            do {
                guard #available(iOS 18.0, *), let bridge = bridge as? AppleTranslationBridge else {
                    throw TranslationError.unavailable("اختبار Apple Translation يتطلب iPadOS 18 أو أحدث وجلسة ترجمة مفعلة.")
                }
                var output: [(String, String)] = []
                for sample in samples {
                    let translated = try await bridge.translate(sample)
                    output.append((sample, translated))
                }
                let finished = ContinuousClock.now
                await MainActor.run {
                    results = output
                    elapsedMilliseconds = Double(started.duration(to: finished).components.seconds) * 1000 + Double(started.duration(to: finished).components.attoseconds) / 1_000_000_000_000_000
                    status = "نجح الاختبار: أعادت Apple Translation نتائج فعلية للجمل الثلاث."
                    running = false
                }
            } catch {
                await MainActor.run {
                    status = error.localizedDescription
                    running = false
                }
            }
        }
    }
}
