import SwiftUI

#if canImport(Translation)
import Translation

struct AppleTranslationTaskModifier: ViewModifier {
    let bridge: AnyObject?

    func body(content: Content) -> some View {
        guard #available(iOS 18.0, *), let bridge = bridge as? AppleTranslationBridge else { return AnyView(content) }
        bridge.recordModifierMounted()
        return AnyView(
            content.translationTask(source: bridge.source, target: bridge.target) { session in
                if #available(iOS 18.0, *) {
                    bridge.recordTranslationTaskClosureStarted()
                    defer { bridge.recordTranslationTaskClosureEnded() }
                    await bridge.run(session: session)
                }
            }
        )
    }
}
#else
struct AppleTranslationTaskModifier: ViewModifier {
    let bridge: AnyObject?
    func body(content: Content) -> some View { content }
}
#endif
