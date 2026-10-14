import SwiftUI
import StoreKit
import AppCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showManageSubscription = false
    @State private var confirmDeleteCreations = false
    @State private var confirmDeleteAccount = false
    @State private var isRestoring = false
    @State private var confirmSignOut = false
    @State private var showInvite = false
    @State private var showPacks = false
    @State private var showConsent = false
    @State private var showAgeUpdate = false
    #if DEBUG
    @State private var showsFeelGoodScene = ScreenshotScene.current == .feelGood
    #endif

    var body: some View {
        NavigationStack {
            List {
                // Under 13: no membership, account, credits or AI reminders.
                if app.allowsPurchases {
                    membershipSection
                    if app.canUseAccounts {
                        accountSection
                    }
                }
                if app.allowsCloudAI {
                    creditsSection
                    notificationsSection
                }
                ageSection
                appearanceSection
                languageSection
                privacySection
                shareSection
                aboutSection
            }
            #if DEBUG
            .navigationDestination(isPresented: $showsFeelGoodScene) { FeelGoodView() }
            #endif
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
            // Its own sheets: the app-wide ones can't show over Settings.
            .sheet(isPresented: $showConsent) {
                AIConsentView(
                    providerName: app.config.processorName,
                    processors: app.config.consentProcessors,
                    retention: app.config.retentionPhrase,
                    asksGuardian: app.ageDefaults.requiresGuardianStep,
                    onAccept: { guardianConfirmed in
                        app.grantAIConsent(guardianConfirmed: guardianConfirmed)
                        showConsent = false
                    },
                    onDecline: { showConsent = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.background)
            }
            .sheet(isPresented: $showAgeUpdate) {
                AgeStepView(mode: .update) { record in
                    let accepted = app.recordAge(record)
                    if accepted { showAgeUpdate = false }
                    return accepted
                }
                .padding(.top, 24)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.background)
            }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await app.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your credits stay with your account. Pro stays with the Apple Account that bought it, and Restore purchases brings it back.")
            }
            .confirmationDialog("Delete all creations?", isPresented: $confirmDeleteCreations, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    app.deleteAllCreations()
                    app.showToast("Your library is empty now.", style: .success)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every image saved in \(Brand.name) on this device. Photos you saved to your library stay there.")
            }
            .confirmationDialog("Delete my data?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
                Button("Delete my data", role: .destructive) {
                    Task { await app.deleteAccountAndData() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if !app.allowsCloudAI {
                    // Under 13 nothing was sent, and there are no credits or subscriptions.
                    Text("Deletes your creations and resets every setting on this device.")
                } else if app.canUseAccounts {
                    Text("Deletes your creations and your account with its credits from our servers, and resets every setting on this device. Subscriptions are managed by Apple and must be cancelled separately.")
                } else {
                    // Preview builds have no server account to delete.
                    Text("Deletes your creations and resets every setting on this device, including your AI consent. Subscriptions are managed by Apple and must be cancelled separately.")
                }
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
                        if let trial = app.purchases.trial {
                            Text("Free trial until \(trial.endsAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(Palette.textSecondary)
                        } else {
                            Text("Thank you for supporting us ✦").font(.caption).foregroundStyle(Palette.textSecondary)
                        }
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
                    defer { isRestoring = false }
                    do {
                        try await app.purchases.restore()
                    } catch {
                        if !AppModel.isCancellation(error) {
                            app.showToast(verbatim: AppModel.localizedMessage(for: error), style: .error)
                        }
                        return
                    }
                    app.credits.refresh(isPro: app.purchases.isPro)
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
            .disabled(isRestoring)
        } header: {
            Text("Membership")
        }
        .listRowBackground(Palette.surface)
    }

    private var accountSection: some View {
        Section {
            if app.isSignedIn {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in with Apple")
                        Text(app.accountEmail ?? String(localized: "Email hidden"))
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                } icon: {
                    Image(systemName: "apple.logo").foregroundStyle(Palette.textPrimary)
                }
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keep Pro and your credits when you switch or add a device. Signing in is optional.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                    AppleSignInButton()
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("Account")
        } footer: {
            if !app.canUseAccounts {
                Text("Accounts need the \(Brand.name) server, which isn't connected in this demo build.")
            } else {
                Text("Your photos stay on each device and are never uploaded to sync. We only learn your Apple ID email if you share it, and you can hide it.")
            }
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
            // The packs themselves, not the plans: she asked for a pack.
            Button("Buy a credit pack") { showPacks = true }
                .sheet(isPresented: $showPacks) {
                    CreditPacksView()
                        .environment(app)
                        .presentationDetents([.medium, .large])
                        .presentationBackground(Palette.background)
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

    private var notificationsSection: some View {
        Section {
            notificationToggle(.glowReady, title: "When my glow is ready", detail: "If I leave the app while it's working.")
            if !app.purchases.isPro {
                notificationToggle(.creditsBack, title: "When my free credits are back", detail: "Only after I run out.")
            }
            notificationToggle(.weeklyLook, title: "Look of the week", detail: "Fridays at 5 pm.")
            if app.notifier.authorization == .denied, let settings = URL(string: UIApplication.openNotificationSettingsURLString) {
                Button(Platform.isMac ? "Allow notifications in System Settings" : "Allow notifications in Settings") { openURL(settings) }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("All off until you turn them on. Never at night (9 pm–9 am) or during school hours on weekdays. No streaks, no spam.")
        }
        .listRowBackground(Palette.surface)
        .task { await app.notifier.refreshAuthorization() }
    }

    private func notificationToggle(_ kind: GlowNotificationKind, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        Toggle(isOn: Binding(
            get: { app.notifier.preferences.isOn(kind) && app.notifier.isAllowedBySystem },
            set: { on in
                Task {
                    if await app.notifier.set(kind, on: on) {
                        app.syncReminders()
                    }
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .tint(Palette.accent)
        .disabled(app.notifier.authorization == .denied)
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
            Text("Light is our signature pink look. Automatic follows your device.")
        }
        .listRowBackground(Palette.surface)
    }

    /// iOS keeps a language per app: this opens Glowlit's page in Settings,
    /// where "Language" lists every language the app speaks. The Mac keeps
    /// it under System Settings › General › Language & Region › Applications.
    private var languageSection: some View {
        Section {
            Button {
                if let url = URL(string: Platform.isMac ? Self.macLanguageSettings : UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                HStack {
                    Label("Language", systemImage: "globe")
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text(currentLanguage)
                        .foregroundStyle(Palette.textSecondary)
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        } footer: {
            Text(Platform.isMac
                 ? "Glowlit follows your Mac's language. To pick another one, click Language, then add Glowlit under Applications."
                 : "Glowlit follows your device's language. To pick another one, tap Language, then choose it in Settings.")
        }
        .listRowBackground(Palette.surface)
    }

    private static let macLanguageSettings = "x-apple.systempreferences:com.apple.Localization-Settings.extension"

    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let name = Locale.current.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private var privacySection: some View {
        Section {
            if app.allowsCloudAI {
                // On goes through the consent sheet (and its guardian step); off withdraws.
                Toggle(isOn: Binding(get: { app.hasAIConsent }, set: { on in
                    if on { showConsent = true } else { app.withdrawAIConsent() }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cloud AI processing")
                        // The same list the consent sheet shows.
                        ForEach(app.config.consentProcessors, id: \.self) { processor in
                            Text("\(processor.name): \(processor.roleText)")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .tint(Palette.accent)
            }
            Button("Delete all creations", role: .destructive) { confirmDeleteCreations = true }
            Button(role: .destructive) {
                confirmDeleteAccount = true
            } label: {
                HStack {
                    Text("Delete my data & account")
                    if app.isDeletingData {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(app.isDeletingData)
        } header: {
            Text("Privacy")
        } footer: {
            if app.allowsCloudAI {
                Text("Uploaded photos are deleted from our servers within \(app.config.retentionPhrase) and are never used to train AI models. Exports include an invisible “made with AI” label (IPTC metadata) as required by the EU AI Act.")
            } else {
                Text("Every tool runs on your device. Your photos are never uploaded.")
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var ageSection: some View {
        Section {
            LabeledContent("Age range", value: (app.ageRecord?.band ?? .unknown).title)
            Button("Update age range") { showAgeUpdate = true }
        } header: {
            Text("Age")
        } footer: {
            Text("Kept only on this device, and used only to choose what \(Brand.name) offers.")
        }
        .listRowBackground(Palette.surface)
    }

    private var shareSection: some View {
        Section {
            Button {
                showInvite = true
            } label: {
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
        .sheet(isPresented: $showInvite) {
            InviteView()
                .environment(app)
                .pageSheetSizing()
        }
    }

    private var aboutSection: some View {
        Section {
            Button {
                GlowTips.reset()
                dismiss()
                Task {
                    // After the sheet is gone, so the tour can spotlight the screen.
                    try? await Task.sleep(for: .seconds(0.5))
                    app.startTour()
                }
            } label: {
                Label("Show me around", systemImage: "sparkles")
            }
            NavigationLink {
                FeelGoodView()
            } label: {
                Label("Feel good", systemImage: "heart")
            }
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

/// Third-party notices: the Poppins font (SIL Open Font License) and the
/// RevenueCat SDK (MIT), the app's only third-party code. Licence texts stay in English.
struct AcknowledgementsView: View {
    private var fontLicense: String {
        Self.bundledText("Poppins-OFL") ?? String(localized: "Poppins is licensed under the SIL Open Font License 1.1.")
    }

    private var revenueCatLicense: String {
        Self.bundledText("RevenueCat-LICENSE") ?? "MIT License. Copyright (c) 2024 RevenueCat, Inc."
    }

    private static func bundledText(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Poppins")
                    .font(.headline)
                Text(fontLicense)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.textSecondary)
                Text(verbatim: "RevenueCat")
                    .font(.headline)
                    .padding(.top, 12)
                Text(revenueCatLicense)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
    }
}
