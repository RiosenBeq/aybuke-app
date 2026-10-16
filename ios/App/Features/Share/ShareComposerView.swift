import SwiftUI
import UniformTypeIdentifiers
import AppCore

/// "Share your glow": pick a format (photo, before/after collage, story
/// card…), a size for where she posts, a background and her own words where
/// the design has them, edit the caption, then send it to Instagram Stories,
/// Photos, the clipboard or any app. Every export keeps the AI provenance
/// metadata, and the free mark stays as it is.
struct ShareComposerView: View {
    let payload: SharePayload

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var format: ShareFormat = .photo
    @State private var showPrompt = false
    @State private var showsAILabel = false
    @State private var caption = ""
    @State private var rendered: UIImage?
    @State private var isWorking = false
    @State private var activityItems: ActivityItems?
    @State private var captionIdeas: [String] = []
    /// Who wrote the ideas on screen; nil for the hand-written ones.
    @State private var ideasWriter: WrittenBy?
    /// The writer working on new ones, while `isLoadingIdeas`.
    @State private var loadingWriter: WrittenBy = .device
    @State private var isLoadingIdeas = false
    @State private var faces = ShareFaceHiding()
    /// Where she posts (Photo and Story card).
    @State private var size: ShareSize = .original
    /// nil: the design's own.
    @State private var backdrop: ShareBackdrop?
    /// Her words as typed, and as drawn once they passed the text rules.
    @State private var drafts: [ShareTextSlot: String] = [:]
    @State private var texts: [ShareTextSlot: String] = [:]
    @State private var textFont: OverlayFont?
    @State private var textColor: OverlayColor?
    @State private var editsText = false
    @State private var textNotice: String?
    /// "Which vibe?" on its way to a poll with friends.
    @State private var pollDraft: PollDraft?
    @FocusState private var focusedSlot: ShareTextSlot?

    /// On-device edits are never branded; free cloud AI results are.
    private var branded: Bool { payload.provenance.showsMark(isPro: app.purchases.isPro) }
    private var madeWithAI: Bool { payload.provenance.carriesAIProvenance }

    private var formats: [ShareFormat] {
        ShareFormat.allCases.filter { format in
            switch format {
            case .beforeAfter: return payload.original != nil
            case .pick: return payload.pickPair != nil
            case .strip: return payload.stripImages.count >= 2
            case .photo, .story, .cover: return true
            }
        }
    }

    private var instagramReady: Bool { InstagramStories.isAvailable(appID: app.config.instagramAppID) }

    private var design: ShareDesign {
        ShareDesign(size: format == .story ? (size == .original ? .story : size) : size,
                    backdrop: backdrop, texts: texts, font: textFont, color: textColor)
    }

    /// The size the chosen design comes out in.
    private var shownSize: ShareSize { format == .story && size == .original ? .story : size }

    /// A background shows: the cards always, the Photo when its size leaves room.
    private var showsBackdrops: Bool {
        switch format {
        case .story, .strip: return true
        case .photo: return ShareLayout.showsBackdrop(imageWidth: payload.image.size.width, imageHeight: payload.image.size.height, size: size)
        case .beforeAfter, .cover, .pick: return false
        }
    }

    private var shownBackdrop: ShareBackdrop { backdrop ?? (format == .photo ? .blur : .glow) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    formatPicker
                    designControls
                    if format == .story, payload.shareablePrompt != nil, texts[.storyLine] == nil {
                        Toggle("Show my prompt on the card", isOn: $showPrompt)
                            .font(.subheadline.weight(.semibold))
                            .tint(Palette.accent)
                    }
                    if faces.isOffered {
                        HideOtherFacesSection(faces: faces)
                            .transition(.opacity)
                    }
                    destinations
                    if format == .pick && app.offersPolls {
                        askFriendsCard
                            .transition(.opacity)
                    }
                    if madeWithAI {
                        Toggle(isOn: $showsAILabel) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add a visible “AI-edited” label")
                                    .font(.subheadline.weight(.semibold))
                                Text("Be real with your followers. A small label goes in the corner.")
                                    .font(.legibleCaption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .tint(Palette.accent)
                    }
                    captionCard
                    captionIdeasCard
                    notes
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
                .readableWidth(Metrics.compactWidth)
                // The face switch arrives once the photo has been looked at.
                .animation(.snappy, value: faces.isOffered)
            }
            .scrollIndicators(.hidden)
            #if DEBUG
            // `-GLShareScrollBottom YES` shows the caption ideas in screenshots.
            .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "GLShareScrollBottom") ? .bottom : nil)
            #endif
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
        .task(id: RenderKey(format: format, showPrompt: showPrompt, branded: branded, aiLabel: showsAILabel, faces: faces.plan, design: design)) {
            await render()
        }
        // Her words are drawn a moment after she stops typing, once they pass the text rules.
        .task(id: drafts) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            commitTexts()
        }
        .onChange(of: format) { _, newFormat in
            textNotice = nil
            if newFormat.textSlots.isEmpty { editsText = false }
        }
        .task {
            app.writer.prewarm()
            await loadCaptionIdeas()
        }
        .task { await faces.prepare(payload) }
        .onAppear {
            if caption.isEmpty {
                caption = ShareCaption.make(for: payload, hashtags: app.config.shareHashtags,
                                            aiHashtags: app.config.aiShareHashtags, link: app.config.shareLinkURL)
            }
            #if DEBUG
            if ScreenshotScene.current == .share, payload.original != nil {
                // `-GLShareFormat pick` shows another format in screenshots.
                format = UserDefaults.standard.string(forKey: "GLShareFormat").flatMap(ShareFormat.init(rawValue:)) ?? .beforeAfter
            }
            if ScreenshotScene.current == .share {
                // `-GLShareSize story`, `-GLShareBackdrop blur|glow|<swatch>`, `-GLShareText "…"`
                // (the design's first text), `-GLShareFont <font>`, `-GLShareTextColor <colour>`
                // and `-GLShareTextEditor YES` show the design controls.
                let defaults = UserDefaults.standard
                if let picked = defaults.string(forKey: "GLShareSize").flatMap(ShareSize.init(rawValue:)) { size = picked }
                if let picked = defaults.string(forKey: "GLShareBackdrop").flatMap(ShareBackdrop.init(id:)) { backdrop = picked }
                if let words = defaults.string(forKey: "GLShareText"), let slot = format.textSlots.first {
                    drafts[slot] = words
                    commitTexts()
                }
                textFont = defaults.string(forKey: "GLShareFont").flatMap(OverlayFont.init(rawValue:))
                textColor = defaults.string(forKey: "GLShareTextColor").flatMap(OverlayColor.init(rawValue:))
                editsText = defaults.bool(forKey: "GLShareTextEditor") && !format.textSlots.isEmpty
            }
            #endif
        }
        .shareSheet(item: $activityItems)
        // Over the composer, so closing it comes back here.
        .sheet(item: $pollDraft) { draft in
            PollCreateView(draft: draft, startsWithExplainer: !app.polls.hasSeenExplainer)
                .environment(app)
                .presentationDetents([.large])
                .presentationBackground(Palette.background)
                .formSheetOnMacPageOnPad()
        }
    }

    // MARK: Sections

    private var preview: some View {
        ZStack {
            if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.control)
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
        // A tap on a design with words opens its text.
        .contentShape(Rectangle())
        .onTapGesture {
            guard let first = format.textSlots.first else { return }
            withAnimation(.snappy) { editsText = true }
            focusedSlot = first
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(format.title.lowercased()) you're sharing")
        .accessibilityAddTraits(format.textSlots.isEmpty ? .isImage : [.isImage, .isButton])
        .accessibilityHint(format.textSlots.isEmpty ? Text(verbatim: "") : Text("Edits the text on it", comment: "Accessibility hint of the share preview on designs with text"))
    }

    // MARK: Design

    /// Size, background and text, each only where the design uses it.
    @ViewBuilder
    private var designControls: some View {
        if format.offersSizes {
            ShareSizeRow(sizes: format == .photo ? ShareSize.allCases : ShareSize.cardSizes, selected: shownSize) { picked in
                size = picked
            }
            .transition(.opacity)
        }
        if showsBackdrops {
            ShareBackdropRow(photo: payload.image, selected: shownBackdrop) { picked in
                backdrop = picked
            }
            .transition(.opacity)
        }
        if !format.textSlots.isEmpty {
            if editsText {
                ShareTextEditor(slots: format.textSlots, drafts: $drafts, font: $textFont, color: $textColor, notice: textNotice,
                                focus: $focusedSlot) {
                    commitTexts()
                    focusedSlot = nil
                    withAnimation(.snappy) { editsText = false }
                }
                .onSubmit { commitTexts() }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    withAnimation(.snappy) { editsText = true }
                    focusedSlot = format.textSlots.first
                } label: {
                    Label("Edit text", systemImage: "textformat")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Palette.surface, in: .chip)
                        .overlay(RoundedRectangle.chip.strokeBorder(Palette.stroke, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .transition(.opacity)
            }
        }
    }

    /// Draws what she typed once it passes the same rules as text on a
    /// photo; a blocked word keeps the last good text and says why.
    private func commitTexts() {
        var notice: String?
        for slot in ShareTextSlot.allCases {
            let cleaned = slot.clean(drafts[slot] ?? "")
            if cleaned.isEmpty {
                if texts[slot] != nil { texts[slot] = nil }
                continue
            }
            if case .blocked(let reason, _) = ContentPolicy.evaluate(cleaned, operation: .textToImage) {
                notice = L10n.core(reason)
                continue
            }
            if texts[slot] != cleaned { texts[slot] = cleaned }
        }
        if notice != nil && notice != textNotice { Haptics.error() }
        textNotice = notice
    }

    /// Every design in view on the Mac (wrapped), a sideways row elsewhere.
    @ViewBuilder
    private var formatPicker: some View {
        if Platform.isMac {
            FlowLayout {
                formatChips
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        formatChips
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -Metrics.gutter)
                // Keeps the chosen design in view, also one chosen as the
                // composer opens (Cover star, say). Not from onAppear or
                // onChange: that choice lands in the composer's onAppear,
                // after this row's, while the sheet is still being laid
                // out, and a scroll asked for then is lost. The task runs a
                // turn later, once the row has its size.
                .task(id: format) {
                    withAnimation(.snappy) { proxy.scrollTo(format.id, anchor: .center) }
                }
            }
        }
    }

    private var formatChips: some View {
        ForEach(formats) { option in
            SelectableChip(title: LocalizedStringKey(option.title), symbolName: option.symbolName, isSelected: format == option) {
                Haptics.selection()
                withAnimation(.snappy) { format = option }
            }
        }
    }

    /// The Mac has no Instagram app, so there the share menu takes the
    /// Stories spot.
    private var destinations: some View {
        HStack(alignment: .top, spacing: 0) {
            if Platform.isMac {
                ShareTarget(title: "Share", symbol: "square.and.arrow.up", isPrimary: true) {
                    shareToApps()
                }
            } else {
                ShareTarget(title: "Stories", symbol: "camera.circle.fill", isPrimary: true) {
                    Task { await shareToStories() }
                }
            }
            ShareTarget(title: "Save", symbol: "square.and.arrow.down") {
                Task { await save() }
            }
            ShareTarget(title: "Copy image", symbol: "doc.on.doc") {
                copyImage()
            }
            if !Platform.isMac {
                ShareTarget(title: "More apps", symbol: "ellipsis") {
                    shareToApps()
                }
            }
        }
        .disabled(rendered == nil || isWorking)
        .opacity(rendered == nil ? 0.5 : 1)
    }

    /// "Which vibe?" as a poll: a private link where friends vote A or B.
    /// The pictures are the design's two variations, with faces hidden when
    /// she switched that on (never her original against its edit).
    private var askFriendsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Let your friends pick")
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
            } icon: {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Palette.accent)
            }
            Text("Make a private link where friends vote A or B for 24 hours, no app needed.")
                .font(.legibleFootnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await askFriends() }
            } label: {
                Label("Ask friends", systemImage: "paperplane.fill")
            }
            .buttonStyle(.primary)
            .disabled(rendered == nil || isWorking)
        }
        .padding(16)
        .cardStyle()
    }

    private func askFriends() async {
        Haptics.tap()
        let covered = await faces.covering(payload)
        guard let pair = covered.pickPair else { return }
        pollDraft = PollDraft(a: pair.a, b: pair.b, provenanceA: payload.provenance, provenanceB: payload.provenance)
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

    /// Three short captions about the vibe, never about how anyone looks:
    /// from Apple's on-device writer when it answers, otherwise hand-written
    /// ones, and from the server's writing help (Claude) only when she asks.
    /// Instagram can't prefill text, so a tap copies one.
    private var captionIdeasCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Caption ideas")
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    Haptics.tap()
                    Task { await loadCaptionIdeas() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Palette.accent)
                .disabled(isLoadingIdeas)
                .accessibilityLabel("New caption ideas")
            }
            if isLoadingIdeas {
                Label(loadingWriter == .cloud ? "Writing new ideas…" : "Writing new ideas on your device…", systemImage: "sparkles")
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(captionIdeas, id: \.self) { idea in
                Button {
                    copyCaptionIdea(idea)
                } label: {
                    HStack(spacing: 10) {
                        Text(idea)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "doc.on.doc")
                            .font(.legibleFootnote.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Palette.background, in: .control)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Copy caption: \(idea)"))
            }
            ideasFootnote
                .font(.legibleCaption)
                .foregroundStyle(Palette.textTertiary)
            if app.usesCloudWriter {
                askClaude
            }
        }
        .padding(16)
        .cardStyle()
        .animation(.snappy, value: captionIdeas)
    }

    /// Claude writes only when she asks, and the note says what it gets.
    private var askClaude: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.tap()
                Task { await askClaudeForCaptions() }
            } label: {
                Label {
                    Text("More ideas from Aybik", comment: "Button under caption ideas: asks the app's AI helper (Aybik, the server's writing help) for captions. Aybik is the app's AI helper: keep the name Aybik.")
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
            .buttonStyle(.secondary)
            .disabled(isLoadingIdeas)
            (Assist.sendsPrompt(payload.shareablePrompt, madeWithAI: madeWithAI)
                ? Text("Aybik, our AI helper, reads your prompt, never the photo.",
                       comment: "Under the share composer's “More ideas from Aybik” button for a creation from a prompt: the writing help gets the prompt. Aybik is the app's AI helper: keep the name Aybik.")
                : Text("Aybik, our AI helper, never gets your photo or your words.",
                       comment: "Under the share composer's “More ideas from Aybik” button: the writing help gets only the design's name. Aybik is the app's AI helper: keep the name Aybik."))
                .font(.legibleCaption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    /// Says who wrote the ideas, and how to copy one.
    private var ideasFootnote: Text {
        switch ideasWriter {
        case .cloud?:
            return Text(Platform.isMac ? "Written by Aybik, our AI helper. Click one to copy it with the hashtags."
                                       : "Written by Aybik, our AI helper. Tap one to copy it with the hashtags.")
        case .device?:
            return Text(Platform.isMac ? "Written on your device. Click one to copy it with the hashtags."
                                       : "Written on your device. Tap one to copy it with the hashtags.")
        case nil:
            return Text(Platform.isMac ? "Click one to copy it with the hashtags." : "Tap one to copy it with the hashtags.")
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            if branded {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Free exports carry a small \(Brand.name) mark.")
                            .font(.legibleFootnote)
                            .foregroundStyle(Palette.textSecondary)
                        Button("Remove it with Pro") {
                            dismiss()
                            app.presentPaywall(source: "share_watermark")
                        }
                        .font(.legibleFootnote.weight(.bold))
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
            if madeWithAI {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Palette.accent)
                    Text("Posting publicly? Switch on the app's AI label (for example Instagram's “AI info”). Your file already carries an invisible “made with AI” tag.")
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    // MARK: Rendering

    private struct RenderKey: Equatable {
        let format: ShareFormat
        let showPrompt: Bool
        let branded: Bool
        let aiLabel: Bool
        let faces: ShareFaceHiding.Plan?
        let design: ShareDesign
    }

    private func render() async {
        let payload = await faces.covering(payload)
        guard !Task.isCancelled else { return }
        let format = format
        let showPrompt = showPrompt
        let branded = branded
        let aiLabel = showsAILabel
        let design = design
        let image = await Task.detached(priority: .userInitiated) {
            ShareRenderer.render(payload, format: format, branded: branded, showPrompt: showPrompt, aiLabel: aiLabel, design: design)
        }.value
        guard !Task.isCancelled else { return }
        rendered = image
    }

    /// The rendered image as a file with IPTC "made with AI" metadata when
    /// AI was involved.
    private func encodedFile() throws -> URL {
        guard let rendered else { throw CocoaError(.fileWriteUnknown) }
        return try ImageExporter.temporaryFile(for: rendered, sourceType: payload.provenance.sourceType, watermark: false)
    }

    // MARK: Caption ideas

    /// On the device only: hand-written ideas at once (a writer can take a
    /// few seconds), different from the last set where possible, then Apple's
    /// on-device writer's when it answers. Nothing leaves the device.
    private func loadCaptionIdeas() async {
        guard !isLoadingIdeas else { return }
        let context = OnDeviceWriter.IdeaContext.caption(look: nil, madeWithAI: madeWithAI)
        let pool = CuratedIdeas.for(context)
        let unseen = pool.filter { !captionIdeas.contains($0) }
        captionIdeas = Array((unseen.count >= 3 ? unseen : pool).shuffled().prefix(3))
        ideasWriter = nil
        guard app.writer.isAvailable else { return }
        isLoadingIdeas = true
        defer { isLoadingIdeas = false }
        await writeIdeasOnDevice()
    }

    /// Her tap on "More ideas from Aybik": the server's writing help hears
    /// her Create prompt (or a plain line) and the design she picked. When
    /// it's off or fails, the on-device writer answers quietly.
    private func askClaudeForCaptions() async {
        guard !isLoadingIdeas else { return }
        isLoadingIdeas = true
        defer { isLoadingIdeas = false }
        loadingWriter = .cloud
        let fresh = await app.cloudCaptions(prompt: payload.shareablePrompt, madeWithAI: madeWithAI, format: format.rawValue)
        if !fresh.isEmpty {
            captionIdeas = fresh
            ideasWriter = .cloud
            return
        }
        guard app.writer.isAvailable else { return }
        await writeIdeasOnDevice()
    }

    private func writeIdeasOnDevice() async {
        loadingWriter = .device
        let fresh = await app.writer.ideas(.caption(look: nil, madeWithAI: madeWithAI))
        if !fresh.isEmpty {
            captionIdeas = fresh
            ideasWriter = .device
        }
    }

    private func copyCaptionIdea(_ idea: String) {
        // The server's captions may end with a hashtag or two: each tag once.
        let tags = ShareCaption.hashtagLine(app.config.shareHashtags, aiHashtags: app.config.aiShareHashtags, madeWithAI: madeWithAI)
            .split(separator: " ")
            .filter { !idea.localizedCaseInsensitiveContains($0) }
            .joined(separator: " ")
        UIPasteboard.general.string = tags.isEmpty ? idea : idea + "\n" + tags
        Haptics.success()
        app.showToast("Caption copied", style: .success)
    }

    // MARK: Destinations

    private func shareToStories() async {
        guard let rendered else { return }
        let appID = app.config.instagramAppID
        if InstagramStories.isAvailable(appID: appID) {
            UIPasteboard.general.string = caption
            // 9:16 fills the Story; any other size goes on it as a sticker.
            let asBackground = ShareLayout.isStoryShaped(width: rendered.size.width, height: rendered.size.height)
            let opened = await InstagramStories.share(rendered, asBackground: asBackground, sourceType: payload.provenance.sourceType, appID: appID)
            if opened {
                app.noteFinishedExport()
            } else {
                app.showToast("Couldn't open Instagram.", style: .error)
            }
            return
        }
        // No Meta App ID configured (or Instagram missing): the system sheet
        // still offers Instagram → Stories / Feed / Messages. Just the image,
        // so Instagram opens straight in its share options; the caption is on
        // the clipboard to paste.
        do {
            let file = try encodedFile()
            UIPasteboard.general.string = caption
            app.showToast("Tap Instagram, then Stories ✨", style: .info)
            activityItems = ActivityItems(items: [file])
        } catch {
            app.handle(error)
        }
    }

    private func save() async {
        guard let rendered else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await PhotoLibrarySaver.save(rendered, sourceType: payload.provenance.sourceType, watermark: false)
            Haptics.success()
            app.showToast("Saved to Photos", style: .success)
            // An ad, a rating request or the invite card may follow once the
            // composer closes.
            app.noteFinishedExport()
        } catch {
            app.handle(error)
        }
    }

    private func copyImage() {
        guard let rendered else { return }
        let provenance = payload.provenance
        if let encoded = ImageExporter.encode(rendered, sourceType: provenance.sourceType) {
            let type = encoded.fileExtension == "png" ? UTType.png : UTType.jpeg
            UIPasteboard.general.setData(encoded.data, forPasteboardType: type.identifier)
        } else if !provenance.carriesAIProvenance {
            // A plain image has no marking to lose.
            UIPasteboard.general.image = rendered
        } else {
            // Never hand over an AI image stripped of its "made with AI" tag.
            app.showToast("Couldn't prepare the image. Please try again.", style: .error)
            return
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
    let title: LocalizedStringKey
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
                    .font(.legibleCaption.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pressable)
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: symbol)
        }
    }
}
