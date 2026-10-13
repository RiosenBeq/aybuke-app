import SwiftUI
import StoreKit
import AppCore

/// Generated images with save / share / edit actions.
struct ResultsView: View {
    let images: [UIImage]
    let prompt: String?
    let operation: AIOperation
    var requestID: String?

    @Environment(AppModel.self) private var app
    @Environment(\.requestReview) private var requestReview
    @State private var selection = 0
    @State private var showReport = false
    @State private var celebrate = 0

    private var current: UIImage? {
        images.indices.contains(selection) ? images[selection] : images.first
    }

    var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $selection) {
                ForEach(images.indices, id: \.self) { index in
                    Image(uiImage: images[index])
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Palette.shadow, radius: 16, y: 8)
                        .padding(.horizontal, Metrics.gutter)
                        .tag(index)
                        .accessibilityLabel("Generated image \(index + 1) of \(images.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            .overlay { SparkleBurst(trigger: celebrate) }

            if let prompt, !prompt.isEmpty {
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
        }
        .background(AuroraBackground(intensity: 0.35))
        .navigationTitle("Your creation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        }
        .reportDialog(isPresented: $showReport, requestID: requestID)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            celebrate += 1
        }
    }

    private func save() {
        guard let current else { return }
        Task {
            do {
                try await PhotoLibrarySaver.save(current, operation: operation, watermark: !app.purchases.isPro)
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
                if app.registerSuccessfulSave() {
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
        app.share(SharePayload(image: current, operation: operation, prompt: prompt))
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
