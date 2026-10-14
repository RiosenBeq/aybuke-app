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
    /// report to Glowlit (we never see them), credited to Image Playground.
    var source: String? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.requestReview) private var requestReview
    @State private var selection = 0
    @State private var showReport = false
    /// Keys the develop reveal, so each image of this batch plays it once.
    @State private var batch = UUID()

    private var current: UIImage? {
        images.indices.contains(selection) ? images[selection] : images.first
    }

    var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $selection) {
                ForEach(images.indices, id: \.self) { index in
                    page(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))

            if isFromImagePlayground {
                Label("Made with Image Playground", systemImage: "apple.image.playground")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.gutter)
            } else if let prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, Metrics.gutter)
            }

            HStack(spacing: 12) {
                Button {
                    share()
                } label: {
                    Label("Share", systemImage: "paperplane.fill")
                }
                .buttonStyle(.primary)

                Button {
                    save()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(IconButtonStyle(size: 56))
                .accessibilityLabel("Save to Photos")

                Button {
                    guard let current else { return }
                    app.openEditor(with: current, tool: .magicEdit)
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(IconButtonStyle(size: 56))
                .accessibilityLabel("Edit this image")
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 12)
            .readableWidth(Metrics.compactWidth, alignment: .center)
            .reveal(2)
        }
        .background(AuroraBackground(intensity: 0.35))
        .navigationTitle("Your creation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !isFromImagePlayground { reportMenu }
            }
        }
        .reportDialog(isPresented: $showReport, requestID: requestID)
    }

    private var isFromImagePlayground: Bool { source == Creation.imagePlaygroundSource }

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
    }

    private func page(_ index: Int) -> some View {
        let key = batch.uuidString + "-" + String(index)
        return Image(uiImage: images[index])
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                try await PhotoLibrarySaver.save(current, operation: operation, watermark: !app.purchases.isPro && !isFromImagePlayground)
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
                if app.registerHappyMoment() {
                    requestReview()
                }
            } catch {
                app.handle(error)
            }
        }
    }

    private func share() {
        guard let current else { return }
        Haptics.tap()
        let others = images.indices.filter { $0 != selection }.map { images[$0] }
        app.share(SharePayload(image: current, operation: operation, prompt: prompt, alternatives: others))
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
        content.confirmationDialog("Report this image", isPresented: $isPresented, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.title) {
                    Task { await app.report(reason, requestID: requestID) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reports help us review results and improve our safety filters.")
        }
    }
}
