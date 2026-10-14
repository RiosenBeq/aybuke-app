import SwiftUI
import Photos
import PhotosUI
import StoreKit
import AppCore

/// "Make a collage": 2–9 photos as a photo dump grid, a mosaic, film strips,
/// instant prints, a scrapbook page or a moodboard, in a feed or story shape
/// or as a seamless carousel. Free, on the device, no credits.
struct CollageView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var model = CollageModel()
    @State private var panel = CollagePanel.layout
    @State private var isPickerPresented = false
    @State private var showDiscardAlert = false
    @State private var shareItems: ActivityItems?
    @State private var sharedFiles: [URL] = []
    @State private var lastSlides = 3

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if model.isReady {
                editor
                    .transition(.opacity)
            } else {
                welcome
                    .transition(.opacity)
            }
            if model.isImporting || model.isExporting {
                progress
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isReady)
        .animation(.easeInOut(duration: 0.2), value: model.isImporting || model.isExporting)
        .photosPicker(isPresented: $isPickerPresented, selection: $model.pickerItems, maxSelectionCount: model.pickerLimit,
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
        .onChange(of: model.pickerItems) { _, _ in
            model.scheduleImport { failed in
                if failed > 0 {
                    app.showToast("Couldn't open that photo. Try another one.", style: .error)
                } else if model.photos.count == 1 {
                    app.showToast("Pick at least 2 photos for a collage.", style: .info)
                }
            }
        }
        .task { await prepare() }
        .alert("Discard your collage?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Save it first if you want to keep it.")
        }
        .shareSheet(item: $shareItems) {
            let files = sharedFiles
            sharedFiles = []
            Task.detached(priority: .utility) {
                for file in files { try? FileManager.default.removeItem(at: file) }
            }
        }
        .modifier(AppPresentations(isActive: true))
    }

    /// Opens the picker straight away: choosing photos is the first step.
    private func prepare() async {
        #if DEBUG
        if ScreenshotScene.current == .collage {
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: "GLCollageEmpty") { model.loadScreenshotFixtures() }
            if let raw = defaults.string(forKey: "GLCollagePanel"), let option = CollagePanel(rawValue: raw) { panel = option }
            // `-GLCollageSelect <slot>` shows a photo's Fit / Swap / Remove bar.
            if defaults.object(forKey: "GLCollageSelect") != nil { model.selection = defaults.integer(forKey: "GLCollageSelect") }
            if defaults.bool(forKey: "GLCollageExport") { await model.writeQAExport() }
            return
        }
        #endif
        try? await Task.sleep(for: .milliseconds(400))
        if model.photos.isEmpty { isPickerPresented = true }
    }

    // MARK: Before photos

    private var welcome: some View {
        VStack(spacing: 0) {
            HStack {
                closeButton
                Spacer()
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Free · on your device")
                            .eyebrowStyle()
                        Text(styled: "Make a *photo dump*", size: 32)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Grids, instant prints, film strips and seamless carousels. Your photos never leave your device.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Button {
                        Haptics.tap()
                        isPickerPresented = true
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.3.offgrid.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 84, height: 84)
                                .background(Palette.blush, in: Circle())
                                .floating(distance: 4)
                            Text("Choose \(CollageModel.minPhotos)–\(CollageModel.maxPhotos) photos")
                                .font(.cardTitle)
                                .foregroundStyle(Palette.textPrimary)
                            Text(Platform.isMac ? "Or drop photo files here" : "They appear in the order you pick them")
                                .font(.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .cardStyle()
                    }
                    .buttonStyle(.pressable)
                    HStack(spacing: 10) {
                        ForEach(CollageStyle.allCases, id: \.self) { style in
                            CollageLayoutThumbnail(style: style, count: 4)
                                .padding(6)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .frame(maxWidth: 420)
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .readableWidth(Metrics.compactWidth)
            }
            .scrollIndicators(.hidden)
        }
        .dropDestination(for: DroppedPhoto.self) { files, _ in
            add(files)
        }
    }

    // MARK: Editing

    private var editor: some View {
        VStack(spacing: 0) {
            topBar
            CollageCanvas(model: model)
                .shadow(color: Palette.shadow, radius: 16, y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 10)
                .dropDestination(for: DroppedPhoto.self) { files, _ in
                    add(files)
                }
            VStack(spacing: 6) {
                hint
                    .frame(minHeight: 44)
                Group {
                    switch panel {
                    case .layout: layoutPanel
                    case .size: sizePanel
                    case .style: stylePanel
                    case .text: textPanel
                    }
                }
                .frame(height: 122, alignment: .top)
            }
            .padding(.horizontal, Metrics.gutter)
            .readableWidth(Metrics.compactWidth, alignment: .center)
            panelBar
        }
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            closeButton
            Button {
                isPickerPresented = true
            } label: {
                Image(systemName: "photo.badge.plus")
            }
            .buttonStyle(.icon)
            .accessibilityLabel("Add or remove photos")

            Spacer(minLength: 0)

            if !model.design.format.isCarousel {
                Button { edit() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.icon)
                    .accessibilityLabel("Open in the editor")
            }
            Button { share() } label: { Image(systemName: "paperplane.fill") }
                .buttonStyle(.icon)
                .accessibilityLabel("Share")
                .padKeyboardShortcut("e")
            Button { save() } label: {
                ViewThatFits(in: .horizontal) {
                    saveLabel(showsText: true)
                    saveLabel(showsText: false)
                }
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel("Save to Photos")
            .accessibilityInputLabels(["Save", "Save to Photos"])
            .keyboardShortcut("s")
        }
        .disabled(model.isExporting || model.isImporting)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
    }

    private func saveLabel(showsText: Bool) -> some View {
        HStack(spacing: 6) {
            if !showsText {
                Image(systemName: "square.and.arrow.down")
            }
            if showsText {
                Text("Save")
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Palette.onAccent)
        .padding(.horizontal, showsText ? 16 : 0)
        .frame(minWidth: 44, minHeight: 44)
        .background(Palette.accent, in: Capsule())
        .fixedSize()
    }

    private var closeButton: some View {
        Button {
            if model.hasUnsavedChanges && model.isReady { showDiscardAlert = true } else { dismiss() }
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.icon)
        .accessibilityLabel("Close")
        .keyboardShortcut(.cancelAction)
    }

    /// How to handle the photos, or the tapped photo's buttons.
    @ViewBuilder
    private var hint: some View {
        if model.swapping != nil {
            HStack(spacing: 10) {
                Label("Tap another photo to swap", systemImage: "arrow.left.arrow.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Button("Cancel") { model.clearSelection() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.accent)
            }
        } else if let selection = model.selection, model.photos.indices.contains(selection) {
            let fitting = model.isFitting(selection)
            HStack(spacing: 8) {
                pill(fitting ? "Fill" : "Fit", symbol: fitting ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") {
                    model.toggleFit(selection)
                }
                pill("Swap", symbol: "arrow.left.arrow.right") {
                    Haptics.tap()
                    model.selection = nil
                    model.swapping = selection
                }
                if model.photos.count > CollageModel.minPhotos {
                    pill("Remove", symbol: "trash") { model.remove(selection) }
                }
                Spacer(minLength: 0)
                Button("Done") { model.clearSelection() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.accent)
            }
        } else {
            Text(Platform.isMac ? "Drag to move · pinch to zoom · hold to swap · drop a file on a photo to replace it"
                                : "Drag to move · pinch to zoom · hold to swap")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func pill(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .fixedSize()
    }

    private var progress: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Palette.accent)
            Text(model.isImporting ? "Getting your photos…" : "Making your collage…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassPanel(radius: 18)
    }

    // MARK: Panels

    private var layoutPanel: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    Haptics.tap()
                    model.surprise()
                } label: {
                    tile(String(localized: "Surprise me"), isSelected: false) {
                        Image(systemName: "sparkles")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AuraFill(palette: .bubblegum))
                    }
                }
                .buttonStyle(.pressable)
                ForEach(CollageStyle.allCases, id: \.self) { style in
                    let isSelected = model.design.style == style
                    let shuffles = isSelected && style.variantCount(for: model.photos.count) > 1
                    Button {
                        Haptics.selection()
                        model.choose(style)
                    } label: {
                        tile(style.title, isSelected: isSelected) {
                            CollageLayoutThumbnail(style: style, count: model.photos.count)
                                .padding(7)
                        }
                        .overlay(alignment: .topTrailing) {
                            if shuffles {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.blush)
                                    .padding(5)
                                    .background(Palette.ink, in: Circle())
                                    .offset(x: 2, y: -4)
                            }
                        }
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(style.title)
                    .accessibilityHint(shuffles ? String(localized: "Tap again for another arrangement") : "")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Metrics.gutter)
    }

    private func tile<Art: View>(_ title: String, isSelected: Bool, @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: 6) {
            art()
                .frame(width: 64, height: 64)
                .background(isSelected ? Palette.primary : Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Palette.ink : Palette.stroke, lineWidth: isSelected ? 1.5 : 1))
            Text(title)
                .font(.caption.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 74)
    }

    private var sizePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(CollageFormat.presets, id: \.self) { format in
                        SelectableChip(title: LocalizedStringKey(format.ratioText), symbolName: format.symbolName,
                                       isSelected: model.design.format == format) {
                            Haptics.selection()
                            withAnimation(.snappy) { model.design.format = format }
                        }
                    }
                    SelectableChip(title: "Carousel", symbolName: "rectangle.split.3x1", isSelected: model.design.format.isCarousel) {
                        Haptics.selection()
                        withAnimation(.snappy) { model.design.format = .carousel(slides: lastSlides) }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Metrics.gutter)

            if model.design.format.isCarousel {
                HStack(spacing: 6) {
                    Text("Slides")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                    ForEach(Array(CollageFormat.slideRange), id: \.self) { count in
                        let isSelected = model.design.format.slides == count
                        Button {
                            Haptics.selection()
                            lastSlides = count
                            withAnimation(.snappy) { model.design.format = .carousel(slides: count) }
                        } label: {
                            Text(verbatim: "\(count)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(isSelected ? Palette.onPrimary : Palette.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(isSelected ? Palette.primary : Palette.surface, in: Circle())
                                .overlay(Circle().strokeBorder(isSelected ? Palette.ink : Palette.stroke, lineWidth: isSelected ? 1.5 : 1))
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(Text("\(count) slides"))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                Text("One wide picture, cut into 4:5 slides that swipe as one.")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var stylePanel: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(CollageBackground.allCases) { background in
                        let isSelected = model.design.background == background
                        Button {
                            Haptics.selection()
                            model.design.background = background
                        } label: {
                            swatch(background)
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Palette.strokeStrong, lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().strokeBorder(isSelected ? Palette.accent : Color.clear, lineWidth: 2))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(background.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Metrics.gutter)
            sliderRow("Spacing", value: $model.design.spacing)
            sliderRow("Corners", value: $model.design.corners)
        }
    }

    @ViewBuilder
    private func swatch(_ background: CollageBackground) -> some View {
        if background == .photo {
            if let first = model.photos.first {
                Image(uiImage: first.image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 3)
            } else {
                Palette.petal
            }
        } else {
            CollageBackdropView(background: background, backdrop: nil)
        }
    }

    private func sliderRow(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(minWidth: 64, alignment: .leading)
                .fixedSize()
            Slider(value: value, in: 0...1)
                .tint(Palette.accent)
                .accessibilityLabel(Text(title))
        }
    }

    private var textPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $model.design.showsCaption.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Date & caption")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("A typewriter line under your photos")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .tint(Palette.accent)
            TextField("Caption (optional)", text: Binding(
                get: { model.design.caption },
                set: { model.design.caption = String($0.prefix(CollageDesign.captionLimit)) }
            ))
            .font(.subheadline)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.stroke, lineWidth: 1))
            .disabled(!model.design.showsCaption)
            .opacity(model.design.showsCaption ? 1 : 0.5)
        }
    }

    private var panelBar: some View {
        HStack(spacing: 2) {
            ForEach(CollagePanel.allCases) { option in
                let isActive = panel == option
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) { panel = option }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                        Text(option.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(isActive ? Palette.onPrimary : Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(isActive ? Palette.primary : Color.clear, in: Capsule())
                    // Blush alone is too faint on the glass to mark the panel.
                    .overlay(Capsule().strokeBorder(isActive ? Palette.ink : Color.clear, lineWidth: 1.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(5)
        .liquidGlass(in: Capsule(), tint: Palette.white.opacity(0.4))
        .frame(maxWidth: 440)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .shadow(color: Palette.shadow, radius: 14, y: 6)
    }

    // MARK: Actions

    /// Dropped files: added to the collage (up to nine).
    private func add(_ files: [DroppedPhoto]) -> Bool {
        guard !files.isEmpty, model.photos.count < CollageModel.maxPhotos else { return false }
        Task {
            if await model.addDropped(files.map(\.data)) > 0 {
                app.showToast("Couldn't open that photo. Try another one.", style: .error)
            }
        }
        return true
    }

    private func save() {
        guard model.isReady, !model.isExporting else { return }
        Task {
            do {
                let saved = try await model.save(app: app)
                guard saved > 0 else { return }
                Haptics.success()
                if saved > 1 {
                    app.showToast("Saved \(saved) slides to Photos", style: .success)
                } else {
                    app.showToast("Saved to Photos", style: .success)
                }
                if app.registerHappyMoment() {
                    requestReview()
                }
            } catch {
                app.handleSaveError(error, onShareInstead: { share() })
            }
        }
    }

    /// A collage goes to the share composer; a carousel's slides go to the
    /// share sheet together, in order.
    private func share() {
        guard model.isReady, !model.isExporting else { return }
        Haptics.tap()
        Task {
            if model.design.format.isCarousel {
                guard let files = await model.slideFiles() else {
                    app.showToast("Couldn't prepare the image. Please try again.", style: .error)
                    return
                }
                sharedFiles = files
                shareItems = ActivityItems(items: files)
                app.countHappyMoment()
            } else if let image = await model.exportImage() {
                app.share(SharePayload(image: image, operation: nil, inheritedSourceType: model.provenance.inheritedSourceType))
            }
        }
    }

    /// The editor works on one picture, so carousels don't offer it.
    private func edit() {
        guard model.isReady, !model.isExporting, !model.design.format.isCarousel else { return }
        Haptics.tap()
        Task {
            let provenance = model.provenance
            guard let image = await model.exportImage(longEdge: 2048) else { return }
            dismiss()
            // Let the cover finish closing before the editor's opens.
            try? await Task.sleep(for: .milliseconds(450))
            app.openEditor(with: image, provenance: provenance)
        }
    }
}

enum CollagePanel: String, CaseIterable, Identifiable {
    case layout, size, style, text

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .layout: return "Layout"
        case .size: return "Size"
        case .style: return "Style"
        case .text: return "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .layout: return "rectangle.3.offgrid"
        case .size: return "aspectratio"
        case .style: return "paintpalette"
        case .text: return "textformat"
        }
    }
}

extension CollageStyle {
    var title: String {
        switch self {
        case .grid: return String(localized: "Grid")
        case .mosaic: return String(localized: "Mosaic")
        case .filmStrip: return String(localized: "Film strip")
        case .polaroid: return String(localized: "Instant")
        case .scrapbook: return String(localized: "Scrapbook")
        case .moodboard: return String(localized: "Moodboard")
        }
    }
}

extension CollageFormat {
    /// "4:5", the same in every language.
    var ratioText: String { "\(ratio.width):\(ratio.height)" }

    var symbolName: String {
        switch self {
        case .portrait: return "rectangle.portrait"
        case .square: return "square"
        case .story: return "rectangle.ratio.9.to.16"
        case .classic: return "rectangle.ratio.3.to.4"
        case .carousel: return "rectangle.split.3x1"
        }
    }
}

/// The Edit tab's way in.
struct CollageHubCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            Haptics.tap()
            app.isCollagePresented = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.3.offgrid.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 54, height: 54)
                    .background(AuraFill(palette: .lilac).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Make a collage")
                            .font(.cardTitle)
                            .foregroundStyle(Palette.textPrimary)
                        NewBadge()
                    }
                    Text("Photo dumps & carousels · free, on-device")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }
}
