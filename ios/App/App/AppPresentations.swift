import SwiftUI

/// Paywall, AI-consent sheet, share composer and toasts. Attached to the root
/// view and to the full-screen editor; only the topmost (`isActive`) one
/// presents, because a view that is already presenting a full-screen cover
/// can't present a sheet.
struct AppPresentations: ViewModifier {
    let isActive: Bool
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { isActive && app.isPaywallPresented },
                set: { app.isPaywallPresented = $0 }
            ), onDismiss: { app.presentationEnded() }) {
                PaywallView(source: app.paywallSource)
                    .environment(app)
                    .pageSheetSizing()
            }
            .sheet(item: Binding(
                get: { isActive ? app.outOfCredits : nil },
                set: { app.outOfCredits = $0 }
            )) { request in
                OutOfCreditsSheet(request: request)
                    .environment(app)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Palette.background)
            }
            .sheet(isPresented: Binding(
                get: { isActive && app.isBestShotPresented },
                set: { app.isBestShotPresented = $0 }
            )) {
                BestShotView()
                    .environment(app)
                    .pageSheetSizing()
            }
            .sheet(isPresented: Binding(
                get: { isActive && app.isAccountPromptPresented && !app.isPaywallPresented && app.outOfCredits == nil },
                set: { app.isAccountPromptPresented = $0 }
            ), onDismiss: { app.presentationEnded() }) {
                AccountPromptSheet()
                    .environment(app)
            }
            .sheet(item: Binding(
                get: { isActive ? app.consentRequest : nil },
                set: { app.consentRequest = $0 }
            )) { request in
                AIConsentView(
                    providerName: app.config.processorName,
                    processors: app.config.consentProcessors,
                    retention: app.config.retentionPhrase,
                    asksGuardian: app.ageDefaults.requiresGuardianStep,
                    onAccept: { guardianConfirmed in
                        app.consentRequest = nil
                        app.grantAIConsent(guardianConfirmed: guardianConfirmed)
                        request.onAccept()
                    },
                    onDecline: { app.consentRequest = nil }
                )
                .environment(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.background)
            }
            .sheet(item: Binding(
                get: { isActive ? app.shareRequest : nil },
                set: { app.shareRequest = $0 }
            )) { payload in
                ShareComposerView(payload: payload)
                    .environment(app)
                    .presentationDetents([.large])
                    .presentationBackground(Palette.background)
                    .pageSheetSizing()
            }
            .toast(Binding(
                get: { isActive ? app.toast : nil },
                set: { app.toast = $0 }
            ))
    }
}
