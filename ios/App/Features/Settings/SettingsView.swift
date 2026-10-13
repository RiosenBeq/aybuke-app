import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showManageSubscription = false
    @State private var confirmDeleteCreations = false
    @State private var confirmDeleteAccount = false
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            List {
                membershipSection
                creditsSection
                appearanceSection
                privacySection
                shareSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            .confirmationDialog("Delete all creations?", isPresented: $confirmDeleteCreations, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    app.deleteAllCreations()
                    app.showToast("Your library is empty now.", style: .success)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every image saved in \(Brand.name) on this iPhone. Photos you saved to your library stay there.")
            }
            .confirmationDialog("Delete my data?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
                Button("Delete my data", role: .destructive) {
                    Task { await app.deleteAccountAndData() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes your creations, your anonymous account and its credits from our servers. Subscriptions are managed by Apple and must be cancelled separately.")
            }
        }
        .tint(Palette.accent)
    }

    // MARK: Sections

    private var membershipSection: some View {
        Section {
            if app.purchases.isPro {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Brand.name) Pro").font(.headline)
                        Text("Thank you for supporting us ✦").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                } icon: {
                    Image(systemName: "crown.fill").foregroundStyle(Palette.accent)
                }
                Button("Manage subscription") { showManageSubscription = true }
            } else {
                Button {
                    dismiss()
                    app.presentPaywall(source: "settings")
                } label: {
                    Label("Upgrade to \(Brand.name) Pro", systemImage: "crown.fill")
                        .fontWeight(.semibold)
                }
            }
            Button {
                isRestoring = true
                Task {
                    await app.purchases.restore()
                    app.credits.refresh(isPro: app.purchases.isPro)
                    isRestoring = false
                    app.showToast(app.purchases.isPro ? "Purchases restored ✦" : "No active subscription found.", style: app.purchases.isPro ? .success : .info)
                }
            } label: {
                HStack {
                    Text("Restore purchases")
                    if isRestoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
        } header: {
            Text("Membership")
        }
        .listRowBackground(Palette.surface)
    }

    private var creditsSection: some View {
        Section {
            HStack {
                Label("Credits left", systemImage: "bolt.fill")
                Spacer()
                Text("\(app.credits.balance)")
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            Button("Buy a credit pack") {
                dismiss()
                app.presentPaywall(source: "settings_packs")
            }
        } header: {
            Text("Credits")
        } footer: {
            Text(app.purchases.isPro
                 ? "Pro includes \(app.credits.policy.proMonthlyAllowance) credits every month; unused credits roll over one month. Failed creations are refunded automatically."
                 : "You get \(app.credits.policy.freeDailyAllowance) free credits every day. Background removal and adjustments are always free.")
        }
        .listRowBackground(Palette.surface)
    }

    private var appearanceSection: some View {
        @Bindable var app = app
        return Section {
            Picker("Appearance", selection: $app.appearance) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            Text("Appearance")
        } footer: {
            Text("Light is our signature pink look. Automatic follows your iPhone.")
        }
        .listRowBackground(Palette.surface)
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(get: { app.hasAIConsent }, set: { app.setAIConsent($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud AI processing")
                    Text("Selected photos are processed by \(app.config.processorName).")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .tint(Palette.accent)
            Button("Delete all creations", role: .destructive) { confirmDeleteCreations = true }
            Button("Delete my data & account", role: .destructive) { confirmDeleteAccount = true }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Uploaded photos are deleted from our servers within \(app.config.dataRetentionHours) hours and are never used to train AI models. Exports include an invisible “made with AI” label (IPTC metadata) as required by the EU AI Act.")
        }
        .listRowBackground(Palette.surface)
    }

    @ViewBuilder
    private var shareSection: some View {
        if let link = app.config.shareLinkURL {
            Section {
                ShareLink(
                    item: link,
                    subject: Text(Brand.storeTitle),
                    message: Text("I've been making my photos glow with \(Brand.name) — try it:")
                ) {
                    Label("Share \(Brand.name) with friends", systemImage: "heart.circle")
                }
                if let review = app.config.appStoreReviewURL {
                    Button {
                        openURL(review)
                    } label: {
                        Label("Rate \(Brand.name)", systemImage: "star")
                    }
                }
            } header: {
                Text("Spread the glow")
            }
            .listRowBackground(Palette.surface)
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                LegalCenterView()
            } label: {
                Label("Terms, privacy & legal", systemImage: "doc.text")
            }
            if let support = app.config.supportURL {
                Button {
                    openURL(support)
                } label: {
                    Label("Contact support", systemImage: "envelope")
                }
            }
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion).foregroundStyle(Palette.textSecondary)
            }
            if let banner = app.modeBanner {
                Label(banner, systemImage: "testtube.2")
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
            }
        } header: {
            Text("About")
        }
        .listRowBackground(Palette.surface)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Third-party notices required by the SIL Open Font License.
struct AcknowledgementsView: View {
    private var fontLicense: String {
        guard let url = Bundle.main.url(forResource: "BricolageGrotesque-OFL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Bricolage Grotesque is licensed under the SIL Open Font License 1.1."
        }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bricolage Grotesque")
                    .font(.headline)
                Text(fontLicense)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
    }
}
