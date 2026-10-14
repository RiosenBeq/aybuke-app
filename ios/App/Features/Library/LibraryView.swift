import SwiftUI
import SwiftData
import AppCore

/// "My Works": everything the user created, stored only on this device.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Creation.createdAt, order: .reverse) private var creations: [Creation]
    @State private var showsFavoritesOnly = false

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 6)]

    private var visible: [Creation] {
        showsFavoritesOnly ? creations.filter(\.isFavorite) : creations
    }

    var body: some View {
        NavigationStack {
            Group {
                if creations.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        HStack(spacing: 8) {
                            SelectableChip(title: "All", symbolName: "square.grid.2x2", isSelected: !showsFavoritesOnly) {
                                Haptics.selection()
                                showsFavoritesOnly = false
                            }
                            SelectableChip(title: "Favorites", symbolName: "heart.fill", isSelected: showsFavoritesOnly) {
                                Haptics.selection()
                                showsFavoritesOnly = true
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .tourAnchor(.library)

                        if visible.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "heart")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .frame(width: 72, height: 72)
                                    .background(Palette.blush, in: Circle())
                                    .floating(distance: 4)
                                Text("Tap ♡ on a creation to keep it here.")
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .padding(.top, 60)
                        }

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(visible) { creation in
                                NavigationLink(value: creation) {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay { ThumbnailView(fileName: creation.imageFileName) }
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            if creation.isFavorite {
                                                Image(systemName: "heart.fill")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(Palette.blush)
                                                    .padding(6)
                                                    .background(Palette.ink.opacity(0.55), in: Circle())
                                                    .padding(6)
                                            }
                                        }
                                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .accessibilityLabel(creation.isFavorite
                                            ? String(localized: "\(L10n.core(creation.title)), favorite")
                                            : L10n.core(creation.title))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    .animation(.snappy, value: showsFavoritesOnly)
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
            emptyStateMessage
                .tourAnchor(.library)
            Button("Create something") {
                app.selectedTab = .create
            }
            .buttonStyle(.primary)
            .frame(maxWidth: 260)
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraBackground(intensity: 0.4))
    }

    private var emptyStateMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 104, height: 104)
                .background(Palette.blush, in: Circle())
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.white)
                        .twinkle()
                        .offset(x: 4, y: -4)
                }
                .floating()
            Text("Nothing here yet")
                .font(.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("Your creations are saved here — privately, on this device.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
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
    @Environment(\.requestReview) private var requestReview
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var confirmDelete = false
    @State private var heartPop = false

    var body: some View {
        VStack(spacing: 16) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Palette.shadow, radius: 16, y: 8)
                    .overlay {
                        // Double-tap to heart, like everywhere else she posts.
                        Image(systemName: "heart.fill")
                            .font(.system(size: 96, weight: .bold))
                            .foregroundStyle(Palette.white)
                            .shadow(color: Palette.ink.opacity(0.25), radius: 12, y: 4)
                            .scaleEffect(heartPop ? 1 : 0.3)
                            .opacity(heartPop ? 1 : 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .onTapGesture(count: 2) {
                        if !creation.isFavorite { toggleFavorite() } else { Haptics.heartbeat() }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { heartPop = true }
                        Task {
                            try? await Task.sleep(for: .milliseconds(650))
                            withAnimation(.easeOut(duration: 0.25)) { heartPop = false }
                        }
                    }
                    .accessibilityAction(named: "Add to favorites") {
                        if !creation.isFavorite { toggleFavorite() }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.core(creation.title))
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                Text("\(creation.kindTitle) · \(creation.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.gutter)

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
                    if let image { app.openEditor(with: image, tool: .magicEdit, provenance: creation.provenance) }
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: creation.isFavorite ? "heart.fill" : "heart")
                        .symbolEffect(.bounce, value: creation.isFavorite)
                }
                .accessibilityLabel(creation.isFavorite ? "Remove from favorites" : "Add to favorites")
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
        .confirmationDialog("Delete this creation?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func save() {
        guard let image else { return }
        Task {
            do {
                // Apple made Image Playground pictures, so they don't carry Glowlit's mark.
                let provenance = creation.provenance
                try await PhotoLibrarySaver.save(image, sourceType: provenance.sourceType, watermark: provenance.showsMark(isPro: app.purchases.isPro))
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
            } catch {
                app.handle(error)
            }
        }
    }

    private func toggleFavorite() {
        creation.isFavorite.toggle()
        try? modelContext.save()
        if creation.isFavorite { Haptics.heartbeat() } else { Haptics.selection() }
        app.syncWidgets()
        if creation.isFavorite, app.registerHappyMoment() {
            requestReview()
        }
    }

    private func share() {
        guard let image else { return }
        Haptics.tap()
        let provenance = creation.provenance
        app.share(SharePayload(image: image, operation: provenance.operation, prompt: creation.prompt,
                               inheritedSourceType: provenance.inheritedSourceType))
    }

    private func delete() {
        ImageStore.delete(creation.imageFileName)
        modelContext.delete(creation)
        try? modelContext.save()
        app.syncWidgets()
        dismiss()
    }
}
