import SwiftUI
import StoreKit
import AppCore

/// Generated images with save / share / edit actions.
struct ResultsView: View {
    let images: [UIImage]
    let prompt: String?
    let operation: AIOperation

    @Environment(AppModel.self) private var app
    @Environment(\.requestReview) private var requestReview
    @State private var selection = 0
    @State private var shareItem: ShareItem?
    @State private var showReport = false

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
                        .padding(.horizontal, Metrics.gutter)
                        .tag(index)
                        .accessibilityLabel("Generated image \(index + 1) of \(images.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))

            if let prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, Metrics.gutter)
            }

            HStack(spacing: 12) {
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.primary)

                Button {
                    share()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(IconButtonStyle(size: 56))
                .accessibilityLabel("Share")

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
        .background(Palette.background.ignoresSafeArea())
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
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Report this image", isPresented: $showReport, titleVisibility: .visible) {
            Button("Offensive or harmful") { report() }
            Button("Sexual content") { report() }
            Button("Doesn't match my request") { report() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reports help us improve our safety filters.")
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
        do {
            shareItem = ShareItem(url: try ImageExporter.temporaryFile(for: current, operation: operation, watermark: !app.purchases.isPro))
        } catch {
            app.handle(error)
        }
    }

    private func report() {
        // TODO(backend): POST the request id + reason to /functions/v1/report.
        app.showToast("Thanks — we'll review this image.", style: .success)
    }
}
