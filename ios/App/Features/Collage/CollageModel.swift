import SwiftUI
import PhotosUI
import Observation
import AppCore

/// The collage maker's state: the picked photos (in slot order), their pan
/// and zoom, the design and the layout made from them. Free and on the
/// device: nothing here is uploaded or costs credits.
@MainActor
@Observable
final class CollageModel {
    struct Photo: Identifiable {
        let id = UUID()
        let image: UIImage
        let sourceType: DigitalSourceType?
        let swatch: UIColor
        var crop = CollageCrop.fill
        /// The picker item it came from; nil for a dropped file.
        var item: PhotosPickerItem?

        var aspect: Double { Double(image.size.width / max(image.size.height, 1)) }
    }

    static let minPhotos = 2
    static let maxPhotos = 9

    private(set) var photos: [Photo] = []
    var design = CollageDesign() {
        didSet {
            guard design != oldValue else { return }
            hasUnsavedChanges = true
            if design.style != oldValue.style || design.variant != oldValue.variant || design.format != oldValue.format
                || design.spacing != oldValue.spacing || design.showsCaption != oldValue.showsCaption {
                relayout()
            }
            if design.background != oldValue.background { refreshBackdrop() }
        }
    }
    private(set) var layout = CollageLayout.empty
    /// The blurred first photo, for the "Blurred photo" background.
    private(set) var backdrop: UIImage?
    private(set) var isImporting = false
    private(set) var isExporting = false
    private(set) var hasUnsavedChanges = false
    /// The picker's ordered selection; `scheduleImport()` follows it.
    var pickerItems: [PhotosPickerItem] = []
    /// A tapped photo (its slot): Fit, Swap and Remove show for it.
    var selection: Int?
    /// After "Swap": the next photo tapped trades places with this one.
    var swapping: Int?
    /// A photo held and dragged to swap, and the one under the finger.
    var lifted: Int?
    var dropTarget: Int?

    /// The photos' shapes when the set last changed. Swaps keep them, so
    /// trading two photos never rearranges the whole grid.
    @ObservationIgnored private var layoutAspects: [Double] = []
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var backdropTask: Task<Void, Never>?
    @ObservationIgnored private var backdropPhotoID: UUID?

    /// Marked only when a source already was (see `Provenance.collage(of:)`).
    var provenance: Provenance { Provenance.collage(of: photos.map(\.sourceType)) }

    var isReady: Bool { photos.count >= Self.minPhotos }

    /// Room left in the picker after dropped files.
    var pickerLimit: Int { max(1, Self.maxPhotos - photos.filter { $0.item == nil }.count) }

    // MARK: Photos

    /// Follows the picker: photos still picked keep their place, unpicked
    /// ones go, new ones join at the end. Imports run one after another.
    /// `completion` gets how many photos couldn't be read.
    func scheduleImport(completion: @escaping (Int) -> Void) {
        let previous = importTask
        importTask = Task {
            await previous?.value
            completion(await importPicked())
        }
    }

    private func importPicked() async -> Int {
        let kept = stillPicked()
        let known = kept.compactMap(\.item)
        let fresh = Array(pickerItems.filter { !known.contains($0) }.prefix(Self.maxPhotos - kept.count))
        guard kept.count != photos.count || !fresh.isEmpty else { return 0 }
        isImporting = true
        defer { isImporting = false }
        let decoded = await Self.load(fresh, maxPixel: CollageImaging.decodeSize(forCount: kept.count + fresh.count))
        // Start again from the photos as they are now: she may have moved
        // one, or dropped a file, while these loaded.
        var next = stillPicked()
        var failed = 0
        for (item, result) in zip(fresh, decoded) where next.count < Self.maxPhotos && !next.contains(where: { $0.item == item }) {
            guard let result else {
                failed += 1
                continue
            }
            next.append(Photo(image: result.image, sourceType: result.sourceType, swatch: result.swatch, item: item))
        }
        setPhotos(next)
        return failed
    }

    /// The photos the picker still selects, plus every dropped file.
    private func stillPicked() -> [Photo] {
        photos.filter { photo in photo.item.map { pickerItems.contains($0) } ?? true }
    }

    /// Three at a time: each holds a whole file's data until it's decoded.
    private static func load(_ items: [PhotosPickerItem], maxPixel: Int) async -> [CollageImaging.Decoded?] {
        var results = [CollageImaging.Decoded?](repeating: nil, count: items.count)
        await withTaskGroup(of: (Int, CollageImaging.Decoded?).self) { group in
            var next = 0
            func add() {
                let index = next, item = items[index]
                next += 1
                group.addTask {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return (index, nil) }
                    return (index, CollageImaging.decode(data, maxPixel: maxPixel))
                }
            }
            while next < min(3, items.count) { add() }
            while let (index, result) = await group.next() {
                results[index] = result
                if next < items.count { add() }
            }
        }
        return results
    }

    /// Files dropped on the canvas (Mac, iPad): onto a photo replaces it,
    /// anywhere else adds them. Returns how many couldn't be read.
    func addDropped(_ files: [Data], replacing index: Int? = nil) async -> Int {
        let files = index == nil ? Array(files.prefix(Self.maxPhotos - photos.count)) : Array(files.prefix(1))
        guard !files.isEmpty else { return 0 }
        isImporting = true
        defer { isImporting = false }
        let size = CollageImaging.decodeSize(forCount: index == nil ? photos.count + files.count : photos.count)
        let decoded = await Task.detached(priority: .userInitiated) {
            files.map { CollageImaging.decode($0, maxPixel: size) }
        }.value
        var next = photos
        for result in decoded.compactMap({ $0 }) {
            let photo = Photo(image: result.image, sourceType: result.sourceType, swatch: result.swatch)
            if let index, next.indices.contains(index) {
                if let item = next[index].item { pickerItems.removeAll { $0 == item } }
                next[index] = photo
            } else {
                next.append(photo)
            }
        }
        setPhotos(next)
        return decoded.filter { $0 == nil }.count
    }

    func remove(_ index: Int) {
        guard photos.indices.contains(index), photos.count > Self.minPhotos else { return }
        let removed = photos[index]
        var next = photos
        next.remove(at: index)
        if let item = removed.item { pickerItems.removeAll { $0 == item } }
        clearSelection()
        withAnimation(.snappy) { setPhotos(next) }
    }

    func swap(_ first: Int, _ second: Int) {
        guard first != second, photos.indices.contains(first), photos.indices.contains(second) else { return }
        photos.swapAt(first, second)
        hasUnsavedChanges = true
        refreshBackdrop()
    }

    private func setPhotos(_ next: [Photo]) {
        let changed = next.map(\.id) != photos.map(\.id)
        photos = next
        layoutAspects = next.map(\.aspect)
        relayout()
        refreshBackdrop()
        if changed { hasUnsavedChanges = true }
        if let selection, selection >= next.count { self.selection = nil }
    }

    // MARK: Layout

    private func relayout() {
        layout = CollageLayout.make(style: design.style, count: photos.count, format: design.format, spacing: design.spacing,
                                    variant: design.variant, photoAspects: layoutAspects, caption: design.showsCaption)
    }

    /// Picks a style; picking the current one again shows its next arrangement.
    func choose(_ style: CollageStyle) {
        withAnimation(.snappy) {
            if design.style == style {
                design.variant = (design.variant + 1) % style.variantCount(for: photos.count)
            } else {
                design.style = style
                design.variant = 0
            }
        }
    }

    /// A random style, arrangement and look, never the same style twice in a row.
    func surprise() {
        var next = design
        next.style = CollageStyle.allCases.filter { $0 != design.style }.randomElement() ?? .grid
        next.variant = Int.random(in: 0..<next.style.variantCount(for: photos.count))
        next.background = CollageBackground.allCases.filter { $0 != design.background }.randomElement() ?? .blush
        next.spacing = [0.15, 0.3, 0.45, 0.6].randomElement() ?? 0.35
        next.corners = [0, 0.25, 0.5, 1].randomElement() ?? 0.2
        withAnimation(.snappy) { design = next }
    }

    /// The window's width over height, for clamping a photo's pan and zoom.
    func windowAspect(at index: Int) -> Double {
        guard layout.slots.indices.contains(index) else { return 1 }
        let window = layout.slots[index].window
        return window.height > 0 ? window.width * design.format.widthOverHeight / window.height : 1
    }

    func setCrop(_ crop: CollageCrop, at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos[index].crop = crop.clamped(photoAspect: photos[index].aspect, windowAspect: windowAspect(at: index))
        hasUnsavedChanges = true
    }

    /// Double-tap: the whole photo, or back to filling its frame.
    func toggleFit(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        withAnimation(.snappy) {
            setCrop(photos[index].crop.toggledFit(photoAspect: photos[index].aspect, windowAspect: windowAspect(at: index)), at: index)
        }
    }

    func isFitting(_ index: Int) -> Bool {
        guard photos.indices.contains(index) else { return false }
        let fit = CollageCrop.fitZoom(photoAspect: photos[index].aspect, windowAspect: windowAspect(at: index))
        return fit < 0.999 && photos[index].crop.zoom <= fit + 0.001
    }

    /// A tap: picks the photo, or finishes a swap started with "Swap".
    func tap(_ index: Int) {
        if let swapping {
            withAnimation(.snappy) { swap(swapping, index) }
            Haptics.success()
            clearSelection()
            return
        }
        Haptics.selection()
        selection = selection == index ? nil : index
    }

    func clearSelection() {
        selection = nil
        swapping = nil
    }

    // MARK: Background

    private func refreshBackdrop() {
        guard design.background == .photo, let first = photos.first, first.id != backdropPhotoID else { return }
        backdropPhotoID = first.id
        let image = first.image
        backdropTask?.cancel()
        backdropTask = Task {
            let blurred = await CollageImaging.backdrop(from: image)
            guard !Task.isCancelled else { return }
            backdrop = blurred
        }
    }

    // MARK: Export

    private func snapshot() -> CollageSnapshot {
        CollageSnapshot(
            layout: layout,
            design: design,
            photos: photos.map { CollageSnapshot.Photo(image: $0.image, crop: $0.crop, swatch: $0.swatch) },
            backgroundColors: design.background.colors.map { UIColor($0) },
            backdrop: design.background == .photo ? backdrop : nil,
            date: Date()
        )
    }

    /// The whole collage, rendered off the main actor: 2160 px on the long
    /// side, or `size` (a carousel's copy for My Works).
    private func renderImage(longEdge: Int = 2160, size: PixelSize? = nil) async -> UIImage? {
        guard isReady else { return nil }
        let snapshot = snapshot()
        let size = size ?? design.format.pixelSize(longEdge: longEdge)
        return await Task.detached(priority: .userInitiated) {
            CollageRenderer.image(snapshot, size: size)
        }.value
    }

    /// Carousel slides, left to right, encoded with the collage's marking.
    /// Each is drawn, encoded and released before the next.
    private func renderSlides() async -> [(data: Data, fileExtension: String)]? {
        guard isReady else { return nil }
        let snapshot = snapshot()
        let format = design.format
        let sourceType = provenance.sourceType
        return await Task.detached(priority: .userInitiated) { () -> [(data: Data, fileExtension: String)]? in
            let canvas = format.pixelSize()
            var files: [(data: Data, fileExtension: String)] = []
            for slice in CarouselSlicer.slices(of: canvas, count: format.slides) {
                let encoded = autoreleasepool {
                    CollageRenderer.slide(snapshot, slice, canvas: canvas).flatMap { ImageExporter.encode($0, sourceType: sourceType) }
                }
                guard let encoded else { return nil }
                files.append(encoded)
            }
            return files
        }.value
    }

    /// A carousel's copy in My Works: the whole strip at Instagram's own size.
    private var carouselLibrarySize: PixelSize {
        PixelSize(width: 1080 * design.format.slides, height: 1350)
    }

    /// One export at a time, with the progress showing while it runs.
    private func exporting<T>(_ work: () async throws -> T?) async rethrows -> T? {
        guard isReady, !isExporting else { return nil }
        isExporting = true
        defer { isExporting = false }
        // A blurred background picked a moment ago may still be on its way.
        await backdropTask?.value
        return try await work()
    }

    /// Photos gets the collage (or every slide, in order); My Works a copy.
    /// Returns how many pictures went to Photos.
    func save(app: AppModel) async throws -> Int {
        try await exporting { () async throws -> Int? in
            let provenance = self.provenance
            let title: String
            let saved: Int
            let libraryCopy: UIImage?
            if design.format.isCarousel {
                guard let slides = await renderSlides() else { throw PhotoLibrarySaver.SaveError.encodingFailed }
                try await PhotoLibrarySaver.saveInOrder(slides.map(\.data))
                libraryCopy = await renderImage(size: carouselLibrarySize)
                title = String(localized: "Carousel")
                saved = slides.count
            } else {
                guard let image = await renderImage() else { throw PhotoLibrarySaver.SaveError.encodingFailed }
                let sourceType = provenance.sourceType
                let encoded = await Task.detached(priority: .userInitiated) {
                    ImageExporter.encode(image, sourceType: sourceType)
                }.value
                guard let encoded else { throw PhotoLibrarySaver.SaveError.encodingFailed }
                try await PhotoLibrarySaver.save(data: encoded.data)
                libraryCopy = image
                title = String(localized: "Collage")
                saved = 1
            }
            if let libraryCopy {
                await app.saveToLibrary([libraryCopy], operation: nil, title: title, prompt: nil,
                                        inheritedSourceType: provenance.storedSourceType)
            }
            hasUnsavedChanges = false
            return saved
        } ?? 0
    }

    /// The collage for the share composer or the editor.
    func exportImage(longEdge: Int = 2160) async -> UIImage? {
        await exporting { await renderImage(longEdge: longEdge) }
    }

    /// The slides as numbered temporary files for the share sheet, in order.
    func slideFiles() async -> [URL]? {
        await exporting { () async -> [URL]? in
            guard let slides = await renderSlides() else { return nil }
            return await Task.detached(priority: .userInitiated) { () -> [URL]? in
                let stamp = Int(Date().timeIntervalSince1970)
                var urls: [URL] = []
                for (index, slide) in slides.enumerated() {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("glowlit-carousel-\(stamp)-\(index + 1).\(slide.fileExtension)")
                    guard (try? slide.data.write(to: url, options: .atomic)) != nil else { return nil }
                    urls.append(url)
                }
                return urls
            }.value
        }
    }
}

#if DEBUG
extension CollageModel {
    /// The `collage` screenshot scene: synthetic photos (never real people)
    /// and the design from launch arguments (see `ScreenshotScene.collage`).
    func loadScreenshotFixtures() {
        let defaults = UserDefaults.standard
        let requested = defaults.integer(forKey: "GLCollagePhotos")
        let count = min(max(requested == 0 ? 6 : requested, Self.minPhotos), Self.maxPhotos)
        let art = ScreenshotFixtures.generatedArt(count: 6)
        let pool = [ScreenshotFixtures.goldenLandscape, art[0], ScreenshotFixtures.groupPhoto, art[1], art[2],
                    ScreenshotFixtures.cutoutPhoto, art[3], art[4], art[5]]
        // `-GLCollageAI YES`: the first photo carries an AI marking, to check
        // that the export is marked as a composite with AI.
        let marked = defaults.bool(forKey: "GLCollageAI")
        let next = pool.prefix(count).enumerated().map { index, image in
            Photo(image: image, sourceType: marked && index == 0 ? .trainedAlgorithmicMedia : nil, swatch: CollageImaging.swatch(of: image))
        }
        var design = CollageDesign()
        if let style = defaults.string(forKey: "GLCollageStyle").flatMap(CollageStyle.init(rawValue:)) { design.style = style }
        design.variant = defaults.integer(forKey: "GLCollageVariant")
        switch defaults.string(forKey: "GLCollageFormat") {
        case "square": design.format = .square
        case "story": design.format = .story
        case "classic": design.format = .classic
        case "carousel":
            let slides = defaults.integer(forKey: "GLCollageSlides")
            design.format = .carousel(slides: slides == 0 ? 3 : slides)
        default: break
        }
        if let background = defaults.string(forKey: "GLCollageBackground").flatMap(CollageBackground.init(rawValue:)) {
            design.background = background
        }
        if let caption = defaults.string(forKey: "GLCollageCaption") {
            design.showsCaption = true
            design.caption = caption
        }
        self.design = design
        setPhotos(next)
        hasUnsavedChanges = false
    }

    /// `-GLCollageExport YES`: writes what Save would, into tmp/glowlit-collage-qa,
    /// so the export can be checked without the Photos library.
    func writeQAExport() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glowlit-collage-qa", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await backdropTask?.value
        if design.format.isCarousel {
            for (index, slide) in (await renderSlides() ?? []).enumerated() {
                try? slide.data.write(to: folder.appendingPathComponent("slide-\(index + 1).\(slide.fileExtension)"))
            }
        } else if let image = await renderImage(), let encoded = ImageExporter.encode(image, sourceType: provenance.sourceType) {
            try? encoded.data.write(to: folder.appendingPathComponent("collage.\(encoded.fileExtension)"))
        }
    }
}
#endif
