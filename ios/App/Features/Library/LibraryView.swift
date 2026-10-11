import SwiftUI
import SwiftData
import AppCore

/// "My Works": everything the user created, stored only on this device.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Creation.createdAt, order: .reverse) private var creations: [Creation]

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 4)]

    var body: some View {
        NavigationStack {
            Group {
                if creations.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(creations) { creation in
                                NavigationLink(value: creation) {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay { ThumbnailView(fileName: creation.imageFileName) }
                                        .clipShape(Rectangle())
                                        .contentShape(Rectangle())
                                        .accessibilityLabel(creation.title)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("My Works")
            .navigationDestination(for: Creation.self) { creation in
                CreationDetailView(creation: creation)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Palette.brandGradient)
            Text("Nothing here yet")
                .font(.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("Your creations are saved here — privately, on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Create something") {
                app.selectedTab = .create
            }
            .buttonStyle(.primary)
            .frame(maxWidth: 260)
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ThumbnailView: View {
    let fileName: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.surface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: fileName) {
            let loaded = await ThumbnailCache.shared.thumbnail(for: fileName)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

struct CreationDetailView: View {
    let creation: Creation

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var shareItem: ShareItem?
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 16) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, Metrics.gutter)
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(creation.title)
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                Text("\(creation.operation.displayName) · \(creation.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.gutter)

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
                    if let image { app.openEditor(with: image, tool: .magicEdit) }
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(IconButtonStyle(size: 56))
                .accessibilityLabel("Edit")
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
            }
        }
        .task {
            let name = creation.imageFileName
            image = await Task.detached(priority: .userInitiated) { ImageStore.load(name) }.value
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete this creation?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func save() {
        guard let image else { return }
        Task {
            do {
                try await PhotoLibrarySaver.save(image, operation: creation.operation, watermark: !app.purchases.isPro)
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
            } catch {
                app.handle(error)
            }
        }
    }

    private func share() {
        guard let image else { return }
        do {
            shareItem = ShareItem(url: try ImageExporter.temporaryFile(for: image, operation: creation.operation, watermark: !app.purchases.isPro))
        } catch {
            app.handle(error)
        }
    }

    private func delete() {
        ImageStore.delete(creation.imageFileName)
        modelContext.delete(creation)
        try? modelContext.save()
        dismiss()
    }
}
