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
            )) {
                PaywallView(source: app.paywallSource)
                    .environment(app)
            }
            .sheet(item: Binding(
                get: { isActive ? app.consentRequest : nil },
                set: { app.consentRequest = $0 }
            )) { request in
                AIConsentView(
                    providerName: app.config.processorName,
                    retentionHours: app.config.dataRetentionHours,
                    onAccept: {
                        app.consentRequest = nil
                        request.onAccept()
                    },
                    onDecline: { app.consentRequest = nil }
                )
                .environment(app)
                .presentationDetents([.large])
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
            }
            .toast(Binding(
                get: { isActive ? app.toast : nil },
                set: { app.toast = $0 }
            ))
    }
}
