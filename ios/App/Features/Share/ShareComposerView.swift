import SwiftUI
import UniformTypeIdentifiers
import AppCore

/// "Share your glow": pick a format (photo, before/after collage, 9:16 story
/// card), edit the caption, then send it to Instagram Stories, Photos, the
/// clipboard or any app. Every export keeps the AI provenance metadata.
struct ShareComposerView: View {
    let payload: SharePayload

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var format: ShareFormat = .photo
    @State private var showPrompt = false
    @State private var caption = ""
    @State private var rendered: UIImage?
    @State private var isWorking = false
    @State private var activityItems: ActivityItems?

    private var branded: Bool { !app.purchases.isPro }

    private var formats: [ShareFormat] {
        ShareFormat.allCases.filter { $0 != .beforeAfter || payload.original != nil }
    }

    private var instagramReady: Bool { InstagramStories.isAvailable(appID: app.config.instagramAppID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    formatPicker
                    if format == .story, payload.shareablePrompt != nil {
                        Toggle("Show my prompt on the card", isOn: $showPrompt)
                            .font(.subheadline.weight(.semibold))
                            .tint(Palette.accent)
                    }
                    destinations
                    captionCard
                    notes
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackground(intensity: 0.45))
            .navigationTitle("Share your glow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Palette.accent)
        .task(id: RenderKey(format: format, showPrompt: showPrompt, branded: branded)) {
            await render()
        }
        .onAppear {
            if caption.isEmpty {
                caption = ShareCaption.make(for: payload, hashtags: app.config.shareHashtags, link: app.config.shareLinkURL)
            }
            #if DEBUG
            if ScreenshotScene.current == .share, payload.original != nil { format = .beforeAfter }
            #endif
        }
        .sheet(item: $activityItems) { item in
            ShareSheet(items: item.items)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Sections

    private var preview: some View {
        ZStack {
            if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Palette.shadow, radius: 18, y: 10)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .id(rendered)
            } else {
                ProgressView().tint(Palette.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: rendered)
        .accessibilityLabel("Preview of the \(format.title.lowercased()) you're sharing")
    }

    private var formatPicker: some View {
        HStack(spacing: 8) {
            ForEach(formats) { option in
                SelectableChip(title: option.title, symbolName: option.symbolName, isSelected: format == option) {
                    Haptics.selection()
                    format = option
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var destinations: some View {
        HStack(alignment: .top, spacing: 0) {
            ShareTarget(title: "Stories", symbol: "camera.circle.fill", isPrimary: true) {
                Task { await shareToStories() }
            }
            ShareTarget(title: "Save", symbol: "square.and.arrow.down") {
                Task { await save() }
            }
            ShareTarget(title: "Copy image", symbol: "doc.on.doc") {
                copyImage()
            }
            ShareTarget(title: "More apps", symbol: "ellipsis") {
                shareToApps()
            }
        }
        .disabled(rendered == nil || isWorking)
        .opacity(rendered == nil ? 0.5 : 1)
    }

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Caption")
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    UIPasteboard.general.string = caption
                    Haptics.success()
                    app.showToast("Caption copied", style: .success)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Palette.accent)
            }
            TextField("Say something about it…", text: $caption, axis: .vertical)
                .lineLimit(3...6)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(16)
        .cardStyle()
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            if branded {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Free exports carry a small \(Brand.name) mark.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                        Button("Remove it with Pro") {
                            dismiss()
                            app.presentPaywall(source: "share_watermark")
                        }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.accent)
                Text("Posting publicly? Switch on the app's AI label (for example Instagram's “AI info”). Your file already carries an invisible “made with AI” tag.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    // MARK: Rendering

    private struct RenderKey: Equatable {
        let format: ShareFormat
        let showPrompt: Bool
        let branded: Bool
    }

    private func render() async {
        let payload = payload
        let format = format
        let showPrompt = showPrompt
        let branded = branded
        let image = await Task.detached(priority: .userInitiated) {
            ShareRenderer.render(payload, format: format, branded: branded, showPrompt: showPrompt)
        }.value
        guard !Task.isCancelled else { return }
        rendered = image
    }

    /// The rendered image as a file with IPTC "made with AI" metadata.
    private func encodedFile() throws -> URL {
        guard let rendered else { throw CocoaError(.fileWriteUnknown) }
        return try ImageExporter.temporaryFile(for: rendered, operation: payload.operation, watermark: false)
    }

    // MARK: Destinations

    private func shareToStories() async {
        guard let rendered else { return }
        let appID = app.config.instagramAppID
        if InstagramStories.isAvailable(appID: appID) {
            UIPasteboard.general.string = caption
            let opened = await InstagramStories.share(rendered, asBackground: format == .story, appID: appID)
            if !opened { app.showToast("Couldn't open Instagram.", style: .error) }
            return
        }
        // No Meta App ID configured (or Instagram missing): the system sheet
        // still offers Instagram → Stories / Feed / Messages.
        app.showToast("Pick Instagram, then Stories.", style: .info)
        shareToApps()
    }

    private func save() async {
        guard let rendered else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await PhotoLibrarySaver.save(rendered, operation: payload.operation, watermark: false)
            Haptics.success()
            app.showToast("Saved to Photos", style: .success)
        } catch {
            app.handle(error)
        }
    }

    private func copyImage() {
        guard let rendered else { return }
        if let encoded = ImageExporter.encode(rendered, operation: payload.operation) {
            let type = encoded.fileExtension == "png" ? UTType.png : UTType.jpeg
            UIPasteboard.general.setData(encoded.data, forPasteboardType: type.identifier)
        } else {
            UIPasteboard.general.image = rendered
        }
        Haptics.success()
        app.showToast("Image copied", style: .success)
    }

    private func shareToApps() {
        do {
            let file = try encodedFile()
            UIPasteboard.general.string = caption
            activityItems = ActivityItems(items: [file, CaptionActivityItem(caption: caption)])
        } catch {
            app.handle(error)
        }
    }
}

private struct ShareTarget: View {
    let title: String
    let symbol: String
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isPrimary ? Palette.onAccent : Palette.textPrimary)
                    .frame(width: 58, height: 58)
                    .background(isPrimary ? Palette.accent : Palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(isPrimary ? Color.clear : Palette.stroke, lineWidth: 1))
                    .shadow(color: Palette.shadow, radius: 8, y: 4)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pressable)
    }
}
