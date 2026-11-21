import SwiftUI

#if canImport(Translation)
import Translation

struct AppleTranslationTaskModifier: ViewModifier {
    let bridge: AppleTranslationBridge?

    func body(content: Content) -> some View {
        guard #available(iOS 17.4, *), let bridge else { return AnyView(content) }
        return AnyView(
            content.translationTask(bridge.configuration) { session in
                if #available(iOS 18.0, *) {
                    await bridge.run(session: session)
                }
            }
        )
    }
}
#else
struct AppleTranslationTaskModifier: ViewModifier {
    let bridge: AppleTranslationBridge?
    func body(content: Content) -> some View { content }
}
#endif
