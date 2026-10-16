import SwiftUI
import AppCore

/// Auto edit at the top of the video editor's controls: one button per
/// platform, each making a ready-to-post vertical cut in one tap; once it's
/// made, what it's for, its options, the words to post it with, and Undo.
struct AutoEditCard: View {
    let model: VideoEditorModel
    /// Free ones left today; nil with Pro, or when this clip is already counted.
    let freeLeft: Int?
    /// The paywall can open (never under 13).
    let canUpgrade: Bool
    let start: (SocialPlatform) -> Void
    let showOptions: () -> Void
    let showPost: () -> Void

    var body: some View {
        Group {
            if let edit = model.autoEdit.edit {
                made(edit)
            } else {
                offer
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .animation(.easeInOut(duration: 0.2), value: model.autoEdit.edit == nil)
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    header
                    Spacer(minLength: 8)
                    badge
                }
                VStack(alignment: .leading, spacing: 6) {
                    header
                    badge
                }
            }
            Text("Best moments, framed on you, with captions. Made on your device.")
                .font(.legibleCaption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(SocialPlatform.allCases) { platform in
                    Button {
                        start(platform)
                    } label: {
                        Text(verbatim: platform.shortName)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CaptionPillButtonStyle(prominent: true))
                    .accessibilityLabel(Text("Auto edit for \(platform.name)"))
                    .disabled(model.isAnalyzing || model.duration <= 0)
                }
            }
        }
    }

    private var header: some View {
        Label("Auto edit", systemImage: "wand.and.stars")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.textPrimary)
    }

    @ViewBuilder
    private var badge: some View {
        if let freeLeft {
            Group {
                if freeLeft > 0 {
                    Text("\(freeLeft) free today")
                } else if canUpgrade {
                    Label("Pro", systemImage: "crown.fill")
                } else {
                    Text("Next one tomorrow")
                }
            }
            .font(.legibleCaption2.weight(.bold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Palette.blush, in: .chip)
        }
    }

    private func made(_ edit: VideoAutoEdit.Edit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label {
                    Text("Auto edit for \(edit.platform.name)")
                } icon: {
                    Image(systemName: "wand.and.stars")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    model.undoAutoEdit()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(CaptionPillButtonStyle())
                .accessibilityLabel(Text("Undo auto edit"))
            }
            summary(edit)
                .font(.legibleCaption)
                .foregroundStyle(Palette.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: showOptions) {
            Label("Options", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(CaptionPillButtonStyle())
        Button(action: showPost) {
            Label("Caption & hashtags", systemImage: "number")
        }
        .buttonStyle(CaptionPillButtonStyle())
    }

    private func summary(_ edit: VideoAutoEdit.Edit) -> Text {
        let base = Text("Vertical 9:16 · up to \(Int(edit.length)) s")
        guard let look = edit.look else { return base }
        return base + Text(verbatim: " · " + L10n.core(look.name))
    }
}

/// Auto edit's choices after it's made: the platform, the length and a
/// colour look. Each change shows on the video at once (the analysis is
/// kept, so nothing is looked at again).
struct AutoEditOptionsSheet: View {
    let model: VideoEditorModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let edit = model.autoEdit.edit {
                    VStack(alignment: .leading, spacing: 20) {
                        section("Made for") {
                            ForEach(SocialPlatform.allCases) { platform in
                                SelectableChip(verbatim: platform.name, isSelected: edit.platform == platform) {
                                    Haptics.selection()
                                    model.changeAutoEdit(platform: platform)
                                }
                            }
                        }
                        section("Length") {
                            ForEach(edit.platform.lengths, id: \.self) { length in
                                SelectableChip(title: "\(Int(length)) s", isSelected: edit.length == length) {
                                    Haptics.selection()
                                    model.changeAutoEdit(length: length)
                                }
                            }
                        }
                        section("Look") {
                            SelectableChip(title: "None", isSelected: edit.look == nil) {
                                Haptics.selection()
                                model.changeAutoEdit(look: nil)
                            }
                            ForEach(AdjustVibes.all) { vibe in
                                SelectableChip(verbatim: L10n.core(vibe.name), symbolName: vibe.symbolName, isSelected: edit.look == vibe) {
                                    Haptics.selection()
                                    model.changeAutoEdit(look: vibe)
                                }
                            }
                        }
                        Text("When the video is longer, Auto edit keeps its liveliest moments, in order.")
                            .font(.legibleFootnote)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(role: .destructive) {
                            model.undoAutoEdit()
                            dismiss()
                        } label: {
                            Label("Undo auto edit", systemImage: "arrow.uturn.backward")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(Metrics.gutter)
                    .readableWidth(Metrics.compactWidth)
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Auto edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        // Undo from elsewhere (⌘W's discard, the card) leaves nothing to show.
        .onChange(of: model.autoEdit.edit == nil) { _, gone in
            if gone { dismiss() }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            ChipRow { content() }
        }
    }
}

/// The export sheet for an Auto edit: the words to post it with (a title
/// for Shorts, caption ideas, hashtags), each with Copy, then Share. Ideas
/// are written on the device; Claude writes some only when she asks.
struct AutoEditPostSheet: View {
    struct Request: Identifiable {
        let id = UUID()
        let platform: SocialPlatform
        /// Just saved to Photos.
        let saved: Bool
        /// The exported video, for Share video.
        let file: URL?
    }

    let request: Request
    let post: AutoEditPostText
    /// What she says in the video, from its captions; empty while they're off.
    let transcript: String
    let onShare: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if request.saved {
                        Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Text("Copy a caption, then post the video on \(request.platform.name).")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let title = post.title {
                        titleCard(title)
                    }
                    captionsCard
                    if !post.hashtags.isEmpty {
                        hashtagsCard
                    }
                    if request.file != nil {
                        Button {
                            onShare()
                            dismiss()
                        } label: {
                            Label("Share video", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.primary)
                    }
                }
                .padding(Metrics.gutter)
                .readableWidth(Metrics.compactWidth)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Ready to post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .tint(Palette.accent)
        .presentationBackground(Palette.background)
        .task { await post.load(platform: request.platform, app: app) }
    }

    private func titleCard(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Title")
                .font(.cardTitle)
                .foregroundStyle(Palette.textPrimary)
            copyRow(title) {
                copy(title, toast: "Copied")
            }
            .accessibilityLabel(Text("Copy title: \(title)"))
        }
        .padding(16)
        .cardStyle()
    }

    private var captionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Caption ideas")
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    Haptics.tap()
                    Task { await post.load(platform: request.platform, app: app, fresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Palette.accent)
                .disabled(post.isLoading)
                .accessibilityLabel("New caption ideas")
            }
            if post.isLoading {
                Label(post.loadingWriter == .cloud ? "Writing new ideas…" : "Writing new ideas on your device…", systemImage: "sparkles")
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(Array(post.captions.enumerated()), id: \.element) { index, caption in
                copyRow(caption) {
                    copy(post.clipboard(for: caption), toast: "Caption copied")
                }
                .accessibilityLabel(Text("Copy caption: \(caption)"))
                .arrival(index)
            }
            footnote
                .font(.legibleCaption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if app.usesCloudWriter {
                askClaude
            }
        }
        .padding(16)
        .cardStyle()
        .animation(.snappy, value: post.captions)
    }

    /// Claude writes only when she asks, and the note says what it gets.
    private var askClaude: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.tap()
                Task { await post.askClaude(platform: request.platform, transcript: transcript, app: app) }
            } label: {
                Label {
                    Text("More ideas from Aybik", comment: "Button under caption ideas: asks the app's AI helper (Aybik, the server's writing help) for captions. Aybik is the app's AI helper: keep the name Aybik.")
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
            .buttonStyle(.secondary)
            .disabled(post.isLoading)
            (Assist.sendsVideoWords(transcript: transcript)
                ? Text("Aybik, our AI helper, reads your video’s captions, never the video.",
                       comment: "Under Auto edit's “More ideas from Aybik” button while captions are on: what the writing help gets. Aybik is the app's AI helper: keep the name Aybik.")
                : Text("Aybik, our AI helper, never gets your video or what you say in it.",
                       comment: "Under Auto edit's “More ideas from Aybik” button while captions are off: the writing help gets only the platform. Aybik is the app's AI helper: keep the name Aybik."))
                .font(.legibleCaption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var hashtagsCard: some View {
        let line = post.hashtags.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 10) {
            Text("Hashtags")
                .font(.cardTitle)
                .foregroundStyle(Palette.textPrimary)
            copyRow(line) {
                copy(line, toast: "Copied")
            }
            .accessibilityLabel(Text("Copy hashtags"))
        }
        .padding(16)
        .cardStyle()
    }

    private var footnote: Text {
        let howTo = Platform.isMac ? Text("Click one to copy it with the hashtags.") : Text("Tap one to copy it with the hashtags.")
        switch post.writer {
        case .cloud? where post.heardCaptions:
            return Text("Written by Aybik, our AI helper, from what you say in the video.") + Text(verbatim: " ") + howTo
        case .cloud?:
            return Text(Platform.isMac ? "Written by Aybik, our AI helper. Click one to copy it with the hashtags."
                                       : "Written by Aybik, our AI helper. Tap one to copy it with the hashtags.")
        case .device?: return Text("Written on your device.") + Text(verbatim: " ") + howTo
        case nil: return howTo
        }
    }

    private func copyRow(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(verbatim: text)
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
    }

    private func copy(_ text: String, toast: LocalizedStringResource) {
        UIPasteboard.general.string = text
        Haptics.success()
        app.showToast(toast, style: .success)
    }
}
