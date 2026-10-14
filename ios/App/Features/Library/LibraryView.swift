import SwiftUI
import SwiftData
import AppCore

/// "My Works": everything the user created, stored only on this device.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Creation> { $0.deletedAt == nil }, sort: \Creation.createdAt, order: .reverse)
    private var creations: [Creation]
    /// Recently deleted, last deleted first.
    @Query(filter: #Predicate<Creation> { $0.deletedAt != nil }, sort: [SortDescriptor(\Creation.deletedAt, order: .reverse)])
    private var deleted: [Creation]

    @State private var filter = Filter.all
    @State private var path = NavigationPath()
    @State private var isSelecting = false
    @State private var selection = LibrarySelection()
    /// A sideways drag across the tiles is selecting them; scrolling waits.
    @State private var isDragSelecting = false
    @State private var dragTracker = LibraryDragTracker()
    /// True while a finger drags in select mode. It resets even when the
    /// system takes the touch, so scrolling always comes back.
    @GestureState private var isDragging = false
    /// Image files found missing while their tiles loaded.
    @State private var missingFiles: Set<String> = []
    /// Waiting for "Delete" (to Recently deleted) to be confirmed.
    @State private var pendingDelete: [Creation] = []
    /// Waiting for "Delete now" to be confirmed.
    @State private var pendingPurge: [Creation] = []
    /// A tapped tile in Recently deleted: restore it or delete it now.
    @State private var trashChoice: Creation?
    @State private var shareItems: ActivityItems?
    @State private var sharedFolder: URL?
    @State private var isWorking = false
    /// Mac: the grid's width, for bigger tiles in a bigger window.
    @State private var gridWidth: CGFloat = 0

    private static let phoneColumns = [GridItem(.adaptive(minimum: 108), spacing: 6)]

    /// Three or more columns on iPhone and iPad; on the Mac the tiles grow
    /// with the window, about seven to a row.
    private var columns: [GridItem] {
        guard Platform.isMac else { return Self.phoneColumns }
        let minimum = min(max((gridWidth - Self.gridMargin * 2) / 7 - Self.tileSpacing, 150), 250)
        return [GridItem(.adaptive(minimum: minimum), spacing: Self.tileSpacing)]
    }

    private static let tileSpacing: CGFloat = Platform.isMac ? 10 : 6
    /// The grid's side margin; on the Mac, in line with the large title.
    private static let gridMargin: CGFloat = Platform.isMac ? 20 : 12
    /// The grid's coordinate space, shared by the tile frames and the drag.
    static let gridSpace = "libraryGrid"

    enum Filter {
        case all, favorites, recentlyDeleted
    }

    private var visible: [Creation] {
        switch filter {
        case .all:
            return creations
        case .favorites:
            return creations.filter(\.isFavorite)
        case .recentlyDeleted:
            // Due ones are removed after the next launch; until then they
            // can't be restored, so they aren't shown.
            let now = Date()
            return deleted.filter { creation in
                creation.deletedAt.map { !RecentlyDeleted.isExpired(deletedAt: $0, now: now) } ?? false
            }
        }
    }

    /// What's picked, in grid order: what the actions work on.
    private var selected: [Creation] {
        visible.filter { selection.contains($0.id) }
    }

    /// What's picked, in the order she picked it: the collage's order.
    private var pickedInOrder: [Creation] {
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selection.order.compactMap { byID[$0] }
    }

    /// iPhone: the floating bar takes the tab bar's place while she picks,
    /// like Photos. iPad and the Mac keep their tabs at the top.
    private var hidesTabBar: Bool {
        isSelecting && horizontalSizeClass == .compact && !Platform.isMac
    }

    /// Into and out of select mode; a plain fade with Reduce Motion.
    private var modeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : Motion.reveal
    }

    var body: some View {
        // In three parts: one modifier chain this long is too slow to type-check.
        NavigationStack(path: $path) {
            tracking(dialogs(screen))
                #if DEBUG
                .onAppear(perform: applyScreenshotState)
                #endif
        }
    }

    private var screen: some View {
        Group {
            if creations.isEmpty && deleted.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(title)
        .toolbar { toolbar }
        // The Mac has no tab bar: its sections are in the sidebar.
        #if !targetEnvironment(macCatalyst)
        .toolbar(hidesTabBar ? .hidden : .automatic, for: .tabBar)
        #endif
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationDestination(for: Creation.self) { creation in
            CreationDetailView(creation: creation)
        }
    }

    private func dialogs(_ content: some View) -> some View {
        content
            // `presenting:` hands the actions the creations as they were when
            // asked: the binding clears the pending list before an action runs.
            .confirmationDialog(deleteTitle, isPresented: isPresented($pendingDelete), titleVisibility: .visible,
                                presenting: pendingDelete.isEmpty ? nil : pendingDelete) { items in
                Button("Delete", role: .destructive) { moveToRecentlyDeleted(items) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Deleted creations stay in Recently deleted for 30 days.")
            }
            .confirmationDialog(purgeTitle, isPresented: isPresented($pendingPurge), titleVisibility: .visible,
                                presenting: pendingPurge.isEmpty ? nil : pendingPurge) { items in
                Button("Delete now", role: .destructive) { deleteForGood(items) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This can't be undone.")
            }
            .confirmationDialog("Restore this creation?", isPresented: Binding(
                get: { trashChoice != nil },
                set: { if !$0 { trashChoice = nil } }
            ), titleVisibility: .visible, presenting: trashChoice) { creation in
                Button("Restore") { restore([creation]) }
                Button("Delete now", role: .destructive) { deleteForGood([creation]) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Deleting it now can't be undone.")
            }
            .shareSheet(item: $shareItems) { removeSharedFiles() }
    }

    /// Keeps the selection in step with what's on screen.
    private func tracking(_ content: some View) -> some View {
        content
            // Another filter shows other creations: start that pick afresh.
            .onChange(of: filter) { _, _ in selection.removeAll() }
            .onChange(of: visible.isEmpty) { _, isEmpty in
                if isEmpty { endSelecting() }
            }
            // Only what's on screen stays picked.
            .onChange(of: visible.map(\.id)) { _, ids in
                selection.keepOnly(Set(ids))
            }
            .onChange(of: isDragging) { _, dragging in
                if !dragging { finishDrag() }
            }
    }

    private var title: Text {
        guard isSelecting else { return Text("My Works") }
        let count = selected.count
        return count == 0 ? Text("Select items") : Text("\(count) selected")
    }

    private var deleteTitle: Text {
        pendingDelete.count > 1 ? Text("Delete \(pendingDelete.count) creations?") : Text("Delete this creation?")
    }

    private var purgeTitle: Text {
        pendingPurge.count > 1 ? Text("Delete \(pendingPurge.count) creations for good?") : Text("Delete this creation for good?")
    }

    private func isPresented(_ pending: Binding<[Creation]>) -> Binding<Bool> {
        Binding(get: { !pending.wrappedValue.isEmpty }, set: { if !$0 { pending.wrappedValue = [] } })
    }

    // MARK: Grid

    private var grid: some View {
        let items = visible
        return ScrollView {
            filterChips
            if filter == .recentlyDeleted, !items.isEmpty {
                Text("Creations stay here for 30 days, then they're deleted for good.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Platform.isMac ? Self.gridMargin : 16)
                    .padding(.bottom, 6)
            }
            if items.isEmpty {
                emptyFilterMessage
            }
            LazyVGrid(columns: columns, spacing: Self.tileSpacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, creation in
                    tile(for: creation, position: index + 1, of: items.count)
                }
            }
            .simultaneousGesture(dragToSelect, including: isSelecting ? .all : .subviews)
            .coordinateSpace(.named(Self.gridSpace))
            .padding(.horizontal, Self.gridMargin)
            .padding(.bottom, 12)
        }
        .scrollDisabled(isDragSelecting)
        .animation(.snappy, value: filter)
        .modifier(MacPageWidthReader(width: $gridWidth))
        .background { deleteKeys }
    }

    /// Mac: ⌘Delete in select mode, like Delete on the bar's Delete button,
    /// asks the same question: to Recently deleted, or for good from there.
    @ViewBuilder
    private var deleteKeys: some View {
        if Platform.isMac && isSelecting && !selected.isEmpty {
            let items = selected
            let action: LibrarySelectionBar.Action = filter == .recentlyDeleted ? .deleteNow : .delete
            Button("Delete") { handle(action, on: items) }
                .keyboardShortcut(.delete, modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                SelectableChip(title: "All", symbolName: "square.grid.2x2", isSelected: filter == .all) {
                    show(.all)
                }
                SelectableChip(title: "Favorites", symbolName: "heart.fill", isSelected: filter == .favorites) {
                    show(.favorites)
                }
                if !deleted.isEmpty || filter == .recentlyDeleted {
                    SelectableChip(title: "Recently deleted", symbolName: "trash", isSelected: filter == .recentlyDeleted) {
                        show(.recentlyDeleted)
                    }
                }
            }
            .padding(.horizontal, Self.gridMargin)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 6)
        .tourAnchor(.library)
    }

    private func show(_ newFilter: Filter) {
        Haptics.selection()
        filter = newFilter
    }

    @ViewBuilder
    private var emptyFilterMessage: some View {
        switch filter {
        case .all:
            VStack(spacing: 16) {
                emptyStateMessage
                Button("Create something") {
                    app.selectedTab = .create
                }
                .buttonStyle(.primary)
                .frame(maxWidth: 260)
            }
            .padding(.top, 40)
            .padding(.horizontal, 32)
        case .favorites:
            VStack(spacing: 10) {
                Image(systemName: "heart")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 72, height: 72)
                    .background(Palette.blush, in: Circle())
                    .floating(distance: 4)
                Text(Platform.isMac ? "Click ♡ on a creation to keep it here." : "Tap ♡ on a creation to keep it here.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.top, 60)
        case .recentlyDeleted:
            VStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 72, height: 72)
                    .background(Palette.blush, in: Circle())
                Text("Nothing in Recently deleted")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.top, 60)
        }
    }

    @ViewBuilder
    private func tile(for creation: Creation, position: Int, of total: Int) -> some View {
        let id = creation.id
        let name = creation.imageFileName
        let isMissing = missingFiles.contains(name)
        let isSelected = selection.contains(id)
        let space = Self.gridSpace
        let tile = LibraryTile(
            creation: creation,
            isMissing: isMissing,
            isSelecting: isSelecting,
            isSelected: isSelected,
            daysLeft: filter == .recentlyDeleted ? creation.deletedAt.map { RecentlyDeleted.daysLeft(deletedAt: $0, now: Date()) } : nil,
            onMissing: { missingFiles.insert(name) },
            onRemove: { removeMissing(creation) }
        )
        ZStack {
            if isMissing && !isSelecting {
                // Its own "Remove" button; nothing to open.
                tile
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Image missing")
            } else {
                Button {
                    open(creation)
                } label: {
                    tile
                }
                .buttonStyle(.pressable)
                .macHoverLift(scale: 1.03)
                .accessibilityLabel(accessibilityLabel(for: creation, isMissing: isMissing))
                // While she picks: where it is, "3 of 12" (and "Selected" from the trait).
                .accessibilityValue(isSelecting ? Text("\(position) of \(total)") : Text(verbatim: ""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .contextMenu {
            if !isSelecting { menu(for: creation, isMissing: isMissing) }
        }
        // Where the tile is, for drag to select (only tiles on screen).
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(space))
        } action: { frame in
            dragTracker.frames[id] = frame
        }
        .onDisappear { dragTracker.frames[id] = nil }
    }

    private func accessibilityLabel(for creation: Creation, isMissing: Bool) -> String {
        if isMissing { return String(localized: "Image missing") }
        let title = L10n.core(creation.title)
        if filter == .recentlyDeleted, let deletedAt = creation.deletedAt {
            let days = RecentlyDeleted.daysLeft(deletedAt: deletedAt, now: Date())
            return days == 1 ? String(localized: "\(title), 1 day left") : String(localized: "\(title), \(days) days left")
        }
        return creation.isFavorite ? String(localized: "\(title), favorite") : title
    }

    @ViewBuilder
    private func menu(for creation: Creation, isMissing: Bool) -> some View {
        if isMissing {
            Button(role: .destructive) {
                removeMissing(creation)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        } else {
            // A long press keeps opening this menu, as everywhere on iOS;
            // Select starts select mode with this tile picked.
            Button {
                beginSelecting(with: creation)
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            Divider()
            actions(for: creation)
        }
    }

    @ViewBuilder
    private func actions(for creation: Creation) -> some View {
        if creation.isInRecentlyDeleted {
            Button {
                restore([creation])
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                pendingPurge = [creation]
            } label: {
                Label("Delete now", systemImage: "trash")
            }
        } else {
            Button {
                shareOne(creation)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                saveToPhotos([creation])
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
            Button {
                setFavorite(!creation.isFavorite, for: [creation])
            } label: {
                if creation.isFavorite {
                    Label("Remove from favorites", systemImage: "heart.slash")
                } else {
                    Label("Add to favorites", systemImage: "heart")
                }
            }
            Button {
                edit(creation)
            } label: {
                Label("Edit", systemImage: "wand.and.stars")
            }
            Button {
                duplicate(creation)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Divider()
            Button(role: .destructive) {
                pendingDelete = [creation]
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Select mode

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                let ids = visible.map(\.id)
                let allSelected = !ids.isEmpty && ids.allSatisfy { selection.contains($0) }
                Button(allSelected ? "Deselect all" : "Select all") {
                    Haptics.selection()
                    // Ones already picked keep their place in the pick order.
                    selection = allSelected ? LibrarySelection() : selection.applying(ids, selected: true)
                }
                // ⌘A picks everything, like Photos; it never unpicks.
                .keyboardShortcut(allSelected ? nil : KeyboardShortcut("a", modifiers: .command))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { endSelecting() }
                    .fontWeight(.semibold)
                    .keyboardShortcut(.cancelAction)
            }
        } else if !visible.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { beginSelecting() }
            }
        }
    }

    private var selectionBar: some View {
        let items = selected
        let picked = pickedInOrder
        return LibrarySelectionBar(
            count: items.count,
            collageCount: picked.filter { !missingFiles.contains($0.imageFileName) }.count,
            isRecentlyDeleted: filter == .recentlyDeleted,
            allFavorite: !items.isEmpty && items.allSatisfy(\.isFavorite),
            isWorking: isWorking,
            stack: picked.suffix(3).map(\.imageFileName),
            perform: { handle($0, on: items) }
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        // Wider on the Mac, so the count beside the buttons stays on one line.
        .readableWidth(Platform.isMac ? 780 : Metrics.compactWidth, alignment: .center)
    }

    private func handle(_ action: LibrarySelectionBar.Action, on items: [Creation]) {
        switch action {
        case .share: share(items)
        case .save: saveToPhotos(items)
        case .favorite: setFavorite(true, for: items)
        case .unfavorite: setFavorite(false, for: items)
        case .collage: makeCollage(pickedInOrder)
        case .delete: pendingDelete = items
        case .restore: restore(items)
        case .deleteNow: pendingPurge = items
        }
    }

    /// Select mode, from the toolbar or with one tile picked from its menu.
    private func beginSelecting(with creation: Creation? = nil) {
        Haptics.selection()
        withAnimation(modeAnimation) {
            isSelecting = true
            if let creation { selection.set([creation.id]) }
        }
    }

    private func open(_ creation: Creation) {
        if isSelecting {
            // The finger that drag-selected lifted over a tile: not a tap.
            guard !dragTracker.isSelecting, Date().timeIntervalSince(dragTracker.endedAt) > 0.35 else { return }
            Haptics.selection()
            selection.toggle(creation.id)
        } else if creation.isInRecentlyDeleted {
            trashChoice = creation
        } else {
            path.append(creation)
        }
    }

    private func endSelecting() {
        guard isSelecting || !selection.isEmpty else { return }
        finishDrag()
        withAnimation(modeAnimation) {
            isSelecting = false
            selection.removeAll()
        }
    }

    // MARK: Drag to select

    /// In select mode a drag that starts sideways on a tile picks every tile
    /// from there to the finger (or unpicks them, if it started on a picked
    /// one), like Photos. A drag that starts up or down stays a scroll.
    private var dragToSelect: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named(Self.gridSpace))
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { dragChanged($0) }
            .onEnded { _ in finishDrag() }
    }

    private func dragChanged(_ value: DragGesture.Value) {
        switch dragTracker.phase {
        case .scrolling:
            return
        case .idle:
            let order = visible.map(\.id)
            let positions = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
            guard abs(value.translation.width) > abs(value.translation.height),
                  let id = dragTracker.tile(at: value.startLocation), let anchor = positions[id]
            else {
                dragTracker.phase = .scrolling
                return
            }
            let run = LibraryDragTracker.Run(order: order, positions: positions, anchor: anchor, current: anchor,
                                             selects: !selection.contains(id), baseline: selection)
            dragTracker.phase = .selecting(run)
            // Up and down now move the selection, not the page.
            isDragSelecting = true
            applyDrag(run)
        case .selecting(var run):
            guard let id = dragTracker.tile(at: value.location), let index = run.positions[id], index != run.current else { return }
            run.current = index
            dragTracker.phase = .selecting(run)
            applyDrag(run)
        }
    }

    private func applyDrag(_ run: LibraryDragTracker.Run) {
        let next = run.selection
        guard next != selection else { return }
        selection = next
        Haptics.selection()
    }

    /// The finger lifted, or the system took the touch: scrolling comes back.
    private func finishDrag() {
        if dragTracker.isSelecting { dragTracker.endedAt = Date() }
        dragTracker.phase = .idle
        if isDragSelecting { isDragSelecting = false }
    }

    // MARK: Actions

    /// Full-size pixels for an action, decoded off the main thread. Actions
    /// read a creation's fields before they await: it could be deleted meanwhile.
    private func loadImage(named name: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            ImageStore.load(name).map { $0.preparingForDisplay() ?? $0 }
        }.value
    }

    private func shareOne(_ creation: Creation) {
        let name = creation.imageFileName
        let provenance = creation.provenance
        let prompt = creation.prompt
        Task {
            guard let image = await loadImage(named: name) else { return couldNotOpen() }
            Haptics.tap()
            app.share(SharePayload(image: image, operation: provenance.operation, prompt: prompt,
                                   inheritedSourceType: provenance.inheritedSourceType, offersHidingFaces: true))
        }
    }

    /// One creation opens the share designs; several go to the share sheet
    /// as files, each with its AI marking (and the free mark where it applies).
    private func share(_ items: [Creation]) {
        let items = items.filter { !missingFiles.contains($0.imageFileName) }
        guard !items.isEmpty, !isWorking else { return }
        if items.count == 1 { return shareOne(items[0]) }
        let exports = items.map { (name: $0.imageFileName, provenance: $0.provenance) }
        let isPro = app.purchases.isPro
        isWorking = true
        Task {
            let export = await Task.detached(priority: .userInitiated) { () -> (folder: URL, files: [URL])? in
                // Own folder, so the files can have plain names.
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("glowlit-share-\(UUID().uuidString)", isDirectory: true)
                guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
                var files: [URL] = []
                for (index, item) in exports.enumerated() {
                    autoreleasepool {
                        guard let image = ImageStore.load(item.name),
                              let encoded = ImageExporter.encode(image, sourceType: item.provenance.sourceType,
                                                                 watermark: item.provenance.showsMark(isPro: isPro))
                        else { return }
                        let file = folder.appendingPathComponent("\(Brand.name)-\(index + 1).\(encoded.fileExtension)")
                        if (try? encoded.data.write(to: file, options: .atomic)) != nil { files.append(file) }
                    }
                }
                return (folder, files)
            }.value
            isWorking = false
            guard let export, !export.files.isEmpty else {
                if let export { try? FileManager.default.removeItem(at: export.folder) }
                return couldNotOpen()
            }
            Haptics.tap()
            app.countHappyMoment()
            sharedFolder = export.folder
            shareItems = ActivityItems(items: export.files)
        }
    }

    private func removeSharedFiles() {
        guard let folder = sharedFolder else { return }
        sharedFolder = nil
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: folder) }
    }

    private func saveToPhotos(_ items: [Creation]) {
        let entries = items.filter { !missingFiles.contains($0.imageFileName) }
            .map { (name: $0.imageFileName, provenance: $0.provenance, prompt: $0.prompt) }
        guard !entries.isEmpty, !isWorking else { return }
        let isPro = app.purchases.isPro
        isWorking = true
        Task {
            defer { isWorking = false }
            var saved = 0
            for entry in entries {
                guard let image = await loadImage(named: entry.name) else { continue }
                do {
                    try await PhotoLibrarySaver.save(image, sourceType: entry.provenance.sourceType,
                                                     watermark: entry.provenance.showsMark(isPro: isPro))
                    saved += 1
                } catch {
                    let shareInstead = entries.count == 1
                        ? SharePayload(image: image, operation: entry.provenance.operation, prompt: entry.prompt,
                                       inheritedSourceType: entry.provenance.inheritedSourceType, offersHidingFaces: true)
                        : nil
                    app.handleSaveError(error, shareInstead: shareInstead)
                    return
                }
            }
            guard saved > 0 else { return couldNotOpen() }
            app.showToast("Saved to Photos", style: .success)
            Haptics.success()
        }
    }

    private func setFavorite(_ isFavorite: Bool, for items: [Creation]) {
        guard !items.isEmpty else { return }
        for creation in items { creation.isFavorite = isFavorite }
        try? modelContext.save()
        if isFavorite { Haptics.heartbeat() } else { Haptics.selection() }
        app.syncWidgets()
    }

    /// The collage maker with exactly these pictures, in the order she picked
    /// them. Each goes in as its export would: with its AI marking and, for a
    /// free cloud result, the free mark, so the collage keeps both
    /// (`Provenance.collage(of:)` reads the marking from each file).
    private func makeCollage(_ items: [Creation]) {
        let entries = items.filter { !missingFiles.contains($0.imageFileName) }
            .map { (name: $0.imageFileName, provenance: $0.provenance) }
        guard (CollageModel.minPhotos...CollageModel.maxPhotos).contains(entries.count), !isWorking else { return }
        let isPro = app.purchases.isPro
        let maxPixel = CollageImaging.decodeSize(forCount: entries.count)
        isWorking = true
        Haptics.tap()
        Task {
            let files = await Task.detached(priority: .userInitiated) { () -> [Data] in
                var encoded: [Data] = []
                for entry in entries {
                    let file = autoreleasepool { () -> Data? in
                        guard let image = ImageStore.decoded(entry.name, maxPixel: maxPixel) else { return nil }
                        return ImageExporter.encode(image, sourceType: entry.provenance.sourceType,
                                                    watermark: entry.provenance.showsMark(isPro: isPro))?.data
                    }
                    if let file { encoded.append(file) }
                }
                return encoded
            }.value
            isWorking = false
            guard files.count >= CollageModel.minPhotos else { return couldNotOpen() }
            endSelecting()
            app.openCollage(with: files)
        }
    }

    private func edit(_ creation: Creation) {
        let provenance = creation.provenance
        let name = creation.imageFileName
        Task {
            // Decoded and sized for the editor off the main thread, so opening
            // it doesn't decode or redraw there.
            let image = await Task.detached(priority: .userInitiated) { ImageStore.decoded(name) }.value
            guard let image else { return couldNotOpen() }
            app.openEditor(with: image, tool: .magicEdit, provenance: provenance)
        }
    }

    private func duplicate(_ creation: Creation) {
        let name = creation.imageFileName
        let newestBefore = app.newestCreationFile()
        let copy = Creation(
            operation: creation.operation,
            title: creation.title,
            prompt: creation.prompt,
            imageFileName: name,
            pixelWidth: creation.pixelWidth,
            pixelHeight: creation.pixelHeight,
            source: creation.source
        )
        // Exactly the original's marking, even values this build doesn't know.
        copy.operationRaw = creation.operationRaw
        copy.sourceTypeRaw = creation.sourceTypeRaw
        Task {
            let copyName = await Task.detached(priority: .userInitiated) { try? ImageStore.duplicate(name) }.value
            guard let copyName else {
                app.showToast("Couldn't duplicate that image.", style: .error)
                return
            }
            copy.imageFileName = copyName
            modelContext.insert(copy)
            try? modelContext.save()
            Haptics.success()
            app.libraryDidChange(newestBefore: newestBefore)
            app.showToast("Added a copy to My Works", style: .success)
        }
    }

    private func moveToRecentlyDeleted(_ items: [Creation]) {
        guard !items.isEmpty else { return }
        let newestBefore = app.newestCreationFile()
        LibraryTrash.moveToRecentlyDeleted(items, in: modelContext)
        endSelecting()
        Haptics.success()
        app.libraryDidChange(newestBefore: newestBefore)
        app.showToast("Moved to Recently deleted", style: .success)
    }

    private func restore(_ items: [Creation]) {
        guard !items.isEmpty else { return }
        let newestBefore = app.newestCreationFile()
        LibraryTrash.restore(items, in: modelContext)
        endSelecting()
        Haptics.success()
        app.libraryDidChange(newestBefore: newestBefore)
        app.showToast("Back in My Works", style: .success)
    }

    private func deleteForGood(_ items: [Creation]) {
        guard !items.isEmpty else { return }
        LibraryTrash.deleteForGood(items, in: modelContext)
        endSelecting()
        Haptics.success()
    }

    /// The file is already gone, so there's nothing to keep in Recently deleted.
    private func removeMissing(_ creation: Creation) {
        let newestBefore = app.newestCreationFile()
        missingFiles.remove(creation.imageFileName)
        LibraryTrash.deleteForGood([creation], in: modelContext)
        Haptics.selection()
        app.libraryDidChange(newestBefore: newestBefore)
    }

    private func couldNotOpen() {
        app.showToast("Couldn't open that image.", style: .error)
    }

    // MARK: Empty library

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

    #if DEBUG
    /// `-GLScreenshotScene librarySelect` and `libraryTrash`. QA:
    /// `-GLLibraryAction favorite|delete|duplicate|collage` acts on the
    /// selection, `drag` drag-selects the first six tiles as a finger would,
    /// `selectAll|clear` picks every tile or none; `restore|purge` act on the
    /// newest creation in Recently deleted.
    private func applyScreenshotState() {
        let action = UserDefaults.standard.string(forKey: "GLLibraryAction")
        switch ScreenshotScene.current {
        case .librarySelect where !isSelecting && selection.isEmpty:
            isSelecting = true
            selection.set(creations.enumerated().filter { [1, 2, 4].contains($0.offset) }.map(\.element.id))
            guard let action else { return }
            Task {
                try? await Task.sleep(for: .seconds(1))
                switch action {
                case "favorite": setFavorite(true, for: selected)
                case "delete": moveToRecentlyDeleted(selected)
                case "duplicate": if let first = selected.first { duplicate(first) }
                case "collage": makeCollage(pickedInOrder)
                case "drag": simulateDrag(from: 0, to: 5)
                case "selectAll": selection = selection.applying(visible.map(\.id), selected: true)
                case "clear": selection.removeAll()
                default: break
                }
            }
        case .libraryTrash where filter != .recentlyDeleted:
            filter = .recentlyDeleted
            guard let action else { return }
            Task {
                try? await Task.sleep(for: .seconds(1))
                guard let newest = visible.first else { return }
                if action == "restore" { restore([newest]) } else if action == "purge" { deleteForGood([newest]) }
            }
        default:
            break
        }
    }

    /// What a finger dragging sideways from tile `start` to tile `end` leaves
    /// picked, through the same steps as the gesture.
    private func simulateDrag(from start: Int, to end: Int) {
        let order = visible.map(\.id)
        guard start <= end, order.indices.contains(start), order.indices.contains(end) else { return }
        let positions = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var run = LibraryDragTracker.Run(order: order, positions: positions, anchor: start, current: start,
                                         selects: !selection.contains(order[start]), baseline: selection)
        for index in start...end {
            run.current = index
            applyDrag(run)
        }
    }
    #endif
}

struct ThumbnailView: View {
    let fileName: String
    /// The file is gone (not just locked), so the tile can offer "Remove".
    var onMissing: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase
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
        .task(id: fileName) { await load() }
        // Protected files can't be read while the device is locked, so try
        // again when the app comes back instead of leaving a blank tile.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, image == nil { Task { await load() } }
        }
    }

    private func load() async {
        switch await ThumbnailCache.shared.load(fileName) {
        case .image(let loaded):
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        case .missing:
            onMissing?()
        case .unreadable:
            break
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
    /// The image file is gone; "Remove" takes the row away.
    @State private var isMissing = false
    @State private var confirmDelete = false
    @State private var heartPop = false

    var body: some View {
        VStack(spacing: 16) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.card)
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
            } else if isMissing {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                    Text("This image is missing")
                        .font(.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Button("Remove") { removeMissing() }
                        .buttonStyle(.secondary)
                        .frame(maxWidth: 220)
                }
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
                .macHelp("Save to Photos")
                Button {
                    if let image { app.openEditor(with: image, tool: .magicEdit, provenance: creation.provenance) }
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(IconButtonStyle(size: 56))
                .accessibilityLabel("Edit")
                .macHelp("Edit")
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
                .macHelp(creation.isFavorite ? "Remove from favorites" : "Add to favorites")
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
                .macHelp("Delete")
            }
        }
        .task {
            let name = creation.imageFileName
            // Decoded here, off the main thread, rather than when it's first drawn.
            let (loaded, exists) = await Task.detached(priority: .userInitiated) {
                let loaded = ImageStore.load(name).map { $0.preparingForDisplay() ?? $0 }
                return (loaded, loaded != nil || ImageStore.exists(name))
            }.value
            image = loaded
            isMissing = !exists
        }
        .confirmationDialog("Delete this creation?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleted creations stay in Recently deleted for 30 days.")
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
                let provenance = creation.provenance
                app.handleSaveError(error, shareInstead: SharePayload(image: image, operation: provenance.operation, prompt: creation.prompt,
                                                                      inheritedSourceType: provenance.inheritedSourceType, offersHidingFaces: true))
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
                               inheritedSourceType: provenance.inheritedSourceType, offersHidingFaces: true))
    }

    /// To Recently deleted: the file stays for 30 days.
    private func delete() {
        let newestBefore = app.newestCreationFile()
        LibraryTrash.moveToRecentlyDeleted([creation], in: modelContext)
        app.libraryDidChange(newestBefore: newestBefore)
        app.showToast("Moved to Recently deleted", style: .success)
        dismiss()
    }

    private func removeMissing() {
        let newestBefore = app.newestCreationFile()
        LibraryTrash.deleteForGood([creation], in: modelContext)
        app.libraryDidChange(newestBefore: newestBefore)
        dismiss()
    }
}
