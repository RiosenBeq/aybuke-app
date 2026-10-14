import SwiftUI
import StoreKit
import AppCore

/// Generated images with save / share / edit actions.
struct ResultsView: View {
    let images: [UIImage]
    let prompt: String?
    let operation: AIOperation
    var requestID: String?
    /// `Creation.imagePlaygroundSource` for Apple-made images: no mark, no
    /// report to Aybuke (we never see them), credited to Image Playground.
    var source: String? = nil
    /// Create's results: run the same job again, after a confirm with its cost.
    var regenerate: Regenerate? = nil
    /// In Create's preview column on a wide Mac window rather than pushed:
    /// no title bar of its own, so the report menu sits with the actions.
    var isEmbedded = false

    struct Regenerate {
        let cost: Int
        let perform: () -> Void
    }

    @Environment(AppModel.self) private var app
    @Environment(\.requestReview) private var requestReview
    @State private var selection = 0
    @State private var showReport = false
    @State private var confirmRegenerate = false
    @State private var isSavingAll = false
    /// Keys the develop reveal, so each image of this batch plays it once.
    @State private var batch = UUID()

    private var current: UIImage? {
        images.indices.contains(selection) ? images[selection] : images.first
    }

    var body: some View {
        VStack(spacing: 16) {
            if Platform.isMac {
                macPager
            } else {
                TabView(selection: $selection) {
                    ForEach(images.indices, id: \.self) { index in
                        page(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            }

            // One block, so the note doesn't take the picture's room twice.
            VStack(spacing: 0) {
                if isFromImagePlayground {
                    Label("Made with Image Playground", systemImage: "apple.image.playground")
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Metrics.gutter)
                } else if let prompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .padding(.horizontal, Metrics.gutter)
                }
                savedNote
                    .reveal(1)
            }

            HStack(spacing: 12) {
                Button {
                    share()
                } label: {
                    // One word in every language: it shrinks rather than breaks.
                    Label("Share", systemImage: "paperplane.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .buttonStyle(.primary)

                Button {
                    save()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(IconButtonStyle(size: 56))
                .accessibilityLabel("Save to Photos")
                .macHelp("Save to Photos")

                Button {
                    guard let current else { return }
                    app.openEditor(with: current, tool: .magicEdit, provenance: provenance)
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(IconButtonStyle(size: 56))
                .accessibilityLabel("Edit this image")
                .macHelp("Edit this image")

                if isEmbedded && !isFromImagePlayground {
                    reportMenu
                        .buttonStyle(IconButtonStyle(size: 56))
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, regenerate == nil && images.count < 2 ? 12 : 0)
            .readableWidth(Metrics.compactWidth, alignment: .center)
            .reveal(2)

            if regenerate != nil || images.count > 1 {
                moreActions
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 12)
                    .readableWidth(Metrics.compactWidth, alignment: .center)
                    .reveal(3)
            }
        }
        .background {
            if !isEmbedded { AuroraBackground(intensity: 0.35) }
        }
        .navigationTitle("Your creation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !isFromImagePlayground && !isEmbedded { reportMenu }
            }
        }
        .reportDialog(isPresented: $showReport, requestID: requestID)
        .confirmationDialog("Regenerate?", isPresented: $confirmRegenerate, titleVisibility: .visible, presenting: regenerate) { action in
            Button("Regenerate") { action.perform() }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(regenerateMessage(cost: action.cost))
        }
        // A regenerate brings new pictures: start at the first, with the reveal.
        .onChange(of: images.map { ObjectIdentifier($0) }) { _, _ in
            selection = 0
            batch = UUID()
        }
    }

    /// Create keeps every result in My Works as it arrives, so Save (to
    /// Photos) is never the only way to keep it. A tap opens My Works.
    private var savedNote: some View {
        Button {
            // The tab change plays its own haptic.
            app.selectedTab = .library
        } label: {
            HStack(spacing: 4) {
                Label("Saved to My Works", systemImage: "checkmark.circle.fill")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens My Works")
    }

    /// Regenerate and, with more than one image, Save all.
    private var moreActions: some View {
        ButtonRow(spacing: 10) {
            if regenerate != nil {
                Button {
                    // A cool-down or a block would refuse the job after she confirmed.
                    if let pause = app.cloudPause, pause.isActive() {
                        Haptics.error()
                        app.explain(pause)
                    } else {
                        confirmRegenerate = true
                    }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.secondary)
            }
        } primary: {
            if images.count > 1 {
                Button {
                    saveAll()
                } label: {
                    if isSavingAll {
                        ProgressView()
                            .accessibilityLabel("Saving…")
                    } else {
                        Label("Save all", systemImage: "square.and.arrow.down.on.square")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(isSavingAll)
                .accessibilityHint("Saves every image here to Photos")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private func regenerateMessage(cost: Int) -> String {
        switch cost {
        case 0: return String(localized: "Same prompt and style, new pictures.")
        case 1: return String(localized: "Same prompt and style, new pictures. Uses 1 credit, refunded if it fails.")
        default: return String(localized: "Same prompt and style, new pictures. Uses \(cost) credits; any that fail are refunded.")
        }
    }

    private var isFromImagePlayground: Bool { source == Creation.imagePlaygroundSource }
    private var provenance: Provenance { Creation.provenance(operation: operation, source: source) }

    private var reportMenu: some View {
        Menu {
            Button(role: .destructive) {
                showReport = true
            } label: {
                Label("Report this image", systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
        .macHelp("More")
    }

    /// Mac: the picture with a row of thumbnails to pick from, since a mouse
    /// can't swipe between pages.
    private var macPager: some View {
        VStack(spacing: 12) {
            if images.indices.contains(selection) {
                page(selection)
                    .id(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if images.count > 1 {
                HStack(spacing: 10) {
                    ForEach(images.indices, id: \.self) { index in
                        Button {
                            selection = index
                        } label: {
                            Image(uiImage: images[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(.control)
                                .overlay(RoundedRectangle.control.strokeBorder(selection == index ? Palette.accent : Palette.stroke,
                                                                               lineWidth: selection == index ? 2.5 : 1))
                        }
                        .buttonStyle(.pressable)
                        .macHoverLift(scale: 1.05)
                        .accessibilityLabel("Generated image \(index + 1) of \(images.count)")
                        .accessibilityAddTraits(selection == index ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.top, isEmbedded ? 0 : 12)
    }

    private func page(_ index: Int) -> some View {
        let key = batch.uuidString + "-" + String(index)
        return Image(uiImage: images[index])
            .resizable()
            .scaledToFit()
            .clipShape(.card)
            .developReveal(id: key, haptic: index == 0)
            .shadow(color: Palette.shadow, radius: 16, y: 8)
            .padding(.horizontal, Metrics.gutter)
            .tag(index)
            .accessibilityLabel("Generated image \(index + 1) of \(images.count)")
    }

    private func save() {
        guard let current else { return }
        Task {
            do {
                try await PhotoLibrarySaver.save(current, sourceType: provenance.sourceType, watermark: provenance.showsMark(isPro: app.purchases.isPro))
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
                if app.registerHappyMoment() {
                    requestReview()
                }
                app.ads.noteFinishedExport()
            } catch {
                app.handleSaveError(error, shareInstead: sharePayload(for: current))
            }
        }
    }

    /// Every image of this batch, one after another, each with its marking.
    private func saveAll() {
        guard !isSavingAll else { return }
        let images = images
        let provenance = provenance
        let watermark = provenance.showsMark(isPro: app.purchases.isPro)
        isSavingAll = true
        Task {
            defer { isSavingAll = false }
            do {
                for image in images {
                    try await PhotoLibrarySaver.save(image, sourceType: provenance.sourceType, watermark: watermark)
                }
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
                if app.registerHappyMoment() {
                    requestReview()
                }
                app.ads.noteFinishedExport()
            } catch {
                app.handleSaveError(error, shareInstead: current.map(sharePayload(for:)))
            }
        }
    }

    private func share() {
        guard let current else { return }
        Haptics.tap()
        app.share(sharePayload(for: current))
    }

    private func sharePayload(for current: UIImage) -> SharePayload {
        let others = images.indices.filter { $0 != selection }.map { images[$0] }
        let provenance = provenance
        return SharePayload(image: current, operation: provenance.operation, prompt: prompt, alternatives: others,
                            inheritedSourceType: provenance.inheritedSourceType, offersHidingFaces: true)
    }
}

extension View {
    /// "Report this image" reasons; sends the report with the result's request id.
    func reportDialog(isPresented: Binding<Bool>, requestID: String?) -> some View {
        modifier(ReportDialog(isPresented: isPresented, requestID: requestID))
    }
}

private struct ReportDialog: ViewModifier {
    @Binding var isPresented: Bool
    let requestID: String?
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.confirmationDialog("Report this image", isPresented: Binding(
            get: { isPresented && app.canSendReports },
            set: { isPresented = $0 }
        ), titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in
                Button(L10n.core(reason.title)) {
                    Task { await app.report(reason, requestID: requestID) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reports help us review results and improve our safety filters.")
        }
        // Preview builds can't send reports: no reasons to pick, just say so.
        .onChange(of: isPresented) { _, shown in
            guard shown, !app.canSendReports else { return }
            isPresented = false
            app.noteReportingUnavailable()
        }
    }
}
