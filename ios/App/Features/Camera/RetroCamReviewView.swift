import SwiftUI
import StoreKit
import AppCore

/// After a Retro Cam shot or a booth session: the developed photo or the
/// print (strip or grid, caption, date), then Save, Edit, Share or Retake.
struct RetroCamReviewView: View {
    let shot: RetroCamShot
    let onRetake: () -> Void
    let onEdit: (UIImage) -> Void
    let onClose: () -> Void

    @Environment(AppModel.self) private var app
    @State private var layout: BoothLayout = .strip
    @State private var caption = ""
    /// The caption that passed the content policy; only this one is printed.
    @State private var approvedCaption = ""
    @State private var showsDate = true
    @State private var faces: [CGRect?]?
    @State private var printed: UIImage?
    @State private var isSaving = false
    @State private var isSaved = false
    @State private var showDiscardAlert = false
    @State private var captionCheck: Task<Void, Never>?

    private var isBooth: Bool {
        if case .booth = shot.content { return true }
        return false
    }

    /// What Save, Edit and Share use.
    private var image: UIImage? {
        switch shot.content {
        case .photo(let image): return image
        case .booth: return printed
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            picture
            if isBooth {
                boothOptions
            }
            actions
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: PrintKey(layout: layout, caption: approvedCaption, showsDate: showsDate)) {
            await renderPrint()
        }
        .alert("Discard this shot?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive, action: onClose)
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Save it first if you want to keep it.")
        }
        // File › Save (⌘S) on the Mac saves the shot on screen, and File ›
        // Close (⌘W) runs the Close button, which asks before an unsaved shot goes.
        .onAppear {
            app.saveActiveCover = { save() }
            app.closeActiveCover = { requestClose() }
        }
        .onDisappear { app.saveActiveCover = nil }
        #if DEBUG
        .onAppear(perform: applyScreenshotOptions)
        #endif
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Button {
                Haptics.tap()
                onRetake()
            } label: {
                Label("Retake", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.14), in: .pill)
            }
            .buttonStyle(.pressable)
            Spacer()
            Button(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close")
            .macHelp("Close")
            .macKeyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(height: 60)
    }

    private var picture: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
                    .developReveal(id: shot.id)
                    .accessibilityLabel(isBooth ? Text("Your Retro Booth print") : Text("Your photo with \(shot.effect.title)"))
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Printing your strip…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 8)
    }

    private var boothOptions: some View {
        VStack(spacing: 10) {
            // One row when the chips fit; with large text it scrolls instead
            // of pushing the screen wider than the window.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { boothChips }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { boothChips }
                }
                .scrollIndicators(.hidden)
            }
            TextField(text: $caption) {
                Text("Add a caption (optional)", comment: "Placeholder of the one-line caption printed under photo booth shots")
            }
            .accessibilityLabel(Text("Caption"))
            .submitLabel(.done)
            .onSubmit(commitCaption)
            .onChange(of: caption) { _, _ in captionChanged() }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.12), in: .control)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 4)
        .readableWidth(Metrics.compactWidth, alignment: .center)
    }

    @ViewBuilder
    private var boothChips: some View {
        ForEach(BoothLayout.allCases) { option in
            SelectableChip(title: title(of: option),
                           symbolName: option == .strip ? "rectangle.split.1x2" : "square.grid.2x2",
                           isSelected: layout == option) {
                layout = option
                Haptics.selection()
            }
        }
        SelectableChip(title: "Date", symbolName: "calendar", isSelected: showsDate) {
            showsDate.toggle()
            Haptics.selection()
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            ButtonRow(spacing: 10) {
                Button(action: edit) {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.secondary)
            } primary: {
                Button(action: share) {
                    Label("Share", systemImage: "paperplane.fill")
                }
                .buttonStyle(.secondary)
            }
            Button(action: save) {
                if isSaving {
                    ProgressView().tint(Palette.onAccent)
                } else if isSaved {
                    Label("Saved", systemImage: "checkmark")
                } else {
                    Label("Save", systemImage: "arrow.down.to.line")
                }
            }
            .buttonStyle(.primary)
            Text("Free · made on your device")
                .font(.legibleCaption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .disabled(image == nil || isSaving)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .readableWidth(Metrics.compactWidth, alignment: .center)
    }

    private func title(of layout: BoothLayout) -> LocalizedStringKey {
        switch layout {
        case .strip: return "Strip"
        case .grid: return "Grid"
        }
    }

    // MARK: Print

    private struct PrintKey: Equatable {
        var layout: BoothLayout
        var caption: String
        var showsDate: Bool
    }

    private func renderPrint() async {
        guard case .booth(let shots) = shot.content else { return }
        let faces: [CGRect?]
        if let known = self.faces {
            faces = known
        } else {
            faces = await Task.detached(priority: .userInitiated) { BoothPrint.faces(in: shots) }.value
            self.faces = faces
        }
        let layout = layout
        let caption = approvedCaption
        let date: Date? = showsDate ? Date() : nil
        let rendered = await Task.detached(priority: .userInitiated) {
            BoothPrint.render(shots, faces: faces, layout: layout, caption: caption, date: date)
        }.value
        guard !Task.isCancelled else { return }
        printed = rendered
        isSaved = false
    }

    /// Re-prints a moment after she stops typing, not on every key.
    private func captionChanged() {
        captionCheck?.cancel()
        captionCheck = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            commitCaption()
        }
    }

    /// Text printed on the picture: the content policy's text rules apply.
    /// A blocked caption says why and isn't printed.
    private func commitCaption() {
        captionCheck?.cancel()
        let text = PhotoBooth.cleanCaption(caption)
        if case .blocked(let reason, _) = ContentPolicy.evaluate(text, operation: .textToImage) {
            app.showToast(verbatim: L10n.core(reason), style: .error)
            Haptics.error()
            approvedCaption = ""
        } else {
            approvedCaption = text
        }
    }

    // MARK: Actions

    /// On-device effects: no AI marking, no watermark.
    private var payload: SharePayload? {
        image.map { SharePayload(image: $0, original: nil, operation: nil) }
    }

    private var libraryTitle: String {
        guard isBooth else { return shot.effect.title }
        return layout == .strip ? String(localized: "Booth strip") : String(localized: "Booth grid")
    }

    /// The Close button and ⌘W: an unsaved shot asks first.
    private func requestClose() {
        if isSaved { onClose() } else { showDiscardAlert = true }
    }

    private func save() {
        guard let image, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await PhotoLibrarySaver.save(image, sourceType: nil)
                await app.saveToLibrary([image], operation: nil, title: libraryTitle, prompt: nil)
                isSaved = true
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
                // No ad after Retro Cam; a rating request or the invite card
                // may follow once the camera closes.
                app.noteFinishedExport(allowsAd: false)
            } catch {
                app.handleSaveError(error, shareInstead: payload)
            }
        }
    }

    private func share() {
        guard let payload else { return }
        Haptics.tap()
        app.share(payload)
    }

    private func edit() {
        guard let image else { return }
        Haptics.tap()
        Task {
            // The editor works at 2048 px; size it down here, off the main thread.
            let sized = await Task.detached(priority: .userInitiated) { ImageUtilities.normalized(image) }.value
            onEdit(sized)
        }
    }

    #if DEBUG
    /// Screenshots: `-GLBoothLayout grid`, `-GLBoothCaption "…"`, and
    /// `-GLCameraReviewAction edit|share` to go on to the editor or the
    /// share composer.
    private func applyScreenshotOptions() {
        guard ScreenshotScene.current != nil else { return }
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "GLBoothLayout").flatMap(BoothLayout.init(rawValue:)) { layout = value }
        if let text = defaults.string(forKey: "GLBoothCaption") {
            caption = text
            commitCaption()
        }
        guard let action = defaults.string(forKey: "GLCameraReviewAction") else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if action == "edit" { edit() }
            if action == "share" { share() }
        }
    }
    #endif
}
