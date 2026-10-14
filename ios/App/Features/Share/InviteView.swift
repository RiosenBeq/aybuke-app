import SwiftUI
import UniformTypeIdentifiers

/// "Share Glowlit": a ready-made story card (app icon, what it does, a QR
/// code) plus a message with the link. Made from brand art only — the
/// user's photos are never included.
struct InviteView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var card: UIImage?
    @State private var activityItems: ActivityItems?

    private var link: URL? { app.config.shareLinkURL }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    preview
                    VStack(spacing: 6) {
                        Text(styled: "Glow *together*", size: 23)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Share Glowlit with your besties: a story card with a QR code, or a message with the link.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actions
                    Label("Your photos are never included.", systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
                .readableWidth(Metrics.compactWidth, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackground(intensity: 0.5))
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Palette.accent)
        .task {
            let link = link
            card = await Task.detached(priority: .userInitiated) { InviteCard.render(link: link) }.value
        }
        .shareSheet(item: $activityItems)
    }

    private var preview: some View {
        ZStack {
            if let card {
                Image(uiImage: card)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.card)
                    .shadow(color: Palette.shadow, radius: 18, y: 10)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .accessibilityLabel("Glowlit invite card with a QR code")
            } else {
                ProgressView().tint(Palette.accent)
            }
        }
        .frame(height: 400)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: card)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            // No Instagram app on the Mac: the message (with the card) is the way there.
            if !Platform.isMac {
                Button {
                    Task { await shareToStories() }
                } label: {
                    Label("Share to Stories", systemImage: "camera.circle.fill")
                }
                .buttonStyle(.primary)
            }

            HStack(spacing: 12) {
                Button {
                    shareMessage()
                } label: {
                    Label("Send a message", systemImage: "message.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)

                if link != nil {
                    Button {
                        copyLink()
                    } label: {
                        Label("Copy link", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
        .disabled(card == nil)
    }

    // MARK: Destinations

    private func shareToStories() async {
        guard let card else { return }
        let appID = app.config.instagramAppID
        if InstagramStories.isAvailable(appID: appID) {
            if await InstagramStories.share(card, asBackground: true, sourceType: nil, appID: appID) { return }
        }
        // Without a Meta App ID the system sheet still offers Instagram → Stories.
        guard let file = Self.pngFile(card) else { return }
        app.showToast("Tap Instagram, then Stories ✨", style: .info)
        activityItems = ActivityItems(items: [file])
    }

    /// The message (with the link) goes everywhere; the card rides along.
    private func shareMessage() {
        var items: [Any] = [InviteCard.message(link: link)]
        if let card, let file = Self.pngFile(card) { items.insert(file, at: 0) }
        activityItems = ActivityItems(items: items)
    }

    private func copyLink() {
        UIPasteboard.general.string = InviteCard.message(link: link)
        Haptics.success()
        app.showToast("Link copied", style: .success)
    }

    private static func pngFile(_ image: UIImage) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Glowlit-invite.png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
