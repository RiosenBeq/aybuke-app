import SwiftUI
import Observation
import PencilKit
import AppCore

/// Text & Stickers while the tool is open: text boxes, stickers and a doodle
/// over the photo, all still editable. Apply (or leaving the tool) draws them
/// into the photo at full size, and one Undo takes them back.
@MainActor
@Observable
final class OverlaySession {
    enum Mode: String, CaseIterable, Identifiable {
        case text, stickers, doodle

        var id: String { rawValue }
    }

    enum Brush: String, CaseIterable, Identifiable {
        case pen, marker, highlighter, eraser

        var id: String { rawValue }
    }

    /// An item's bitmap on the canvas, drawn by `OverlayRenderer`.
    struct Preview {
        let content: OverlayContent
        let pixelsPerUnit: CGFloat
        let image: UIImage
    }

    /// A placement still under her fingers. Kept apart from `items`, so the
    /// panel doesn't redraw on every frame of a drag.
    struct LivePlacement: Equatable {
        let id: EditorOverlay.ID
        var placement: OverlayPlacement
    }

    /// What Apply draws, with typing finished.
    struct Snapshot {
        let layers: [OverlayRenderer.Layer]
        let doodle: OverlayRenderer.Doodle?
        /// A pasted cut-out makes the photo a composite.
        let hasPasted: Bool
        /// The AI marking a pasted cut-out brought along (an AI edit's sticker).
        let pastedAIMarking: DigitalSourceType?

        var isEmpty: Bool { layers.isEmpty && doodle == nil }
    }

    /// Back to front.
    private(set) var items: [EditorOverlay] = []
    private(set) var selectedID: EditorOverlay.ID?
    private(set) var editingID: EditorOverlay.ID?
    private(set) var mode: Mode = .text
    /// The style of the next text box: the last one she picked.
    private(set) var textStyle = TextOverlay(text: "")
    private(set) var live: LivePlacement?
    /// An item is being dragged (the canvas shows the trash).
    private(set) var isMoving = false
    private(set) var isOverTrash = false
    private(set) var previews: [EditorOverlay.ID: Preview] = [:]

    private(set) var doodle = PKDrawing()
    /// Bumped when the drawing changes from here (Undo, Clear), so the
    /// canvas loads it.
    private(set) var doodleRevision = 0
    /// The canvas the doodle is drawn on (screen points), fixed for the session.
    private(set) var doodleSpace: OverlayCanvas?
    private(set) var brush: Brush = .pen
    private(set) var inkColor: OverlayColor = .white
    private(set) var canUndoDoodle = false

    /// For the editor to show: a blocked word, a paste that didn't work.
    var notice: String?

    @ObservationIgnored private var doodleHistory: [PKDrawing] = []
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var renderTasks: [EditorOverlay.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var viewUnit: CGFloat = 0
    @ObservationIgnored private var displayScale: CGFloat = 2
    @ObservationIgnored private var textBeforeEditing: String?
    #if DEBUG
    @ObservationIgnored private var drawsFixtureDoodle = false
    #endif

    var hasContent: Bool { !items.isEmpty || !doodle.strokes.isEmpty }
    var selected: EditorOverlay? { selectedID.flatMap(overlay(_:)) }
    var editing: EditorOverlay? { editingID.flatMap(overlay(_:)) }
    var isEditingText: Bool { editingID != nil }
    /// Something Esc puts away before it closes the editor.
    var hasFocus: Bool { editingID != nil || selectedID != nil }
    var editingText: String { editing?.content.text?.text ?? "" }

    func overlay(_ id: EditorOverlay.ID) -> EditorOverlay? {
        items.first { $0.id == id }
    }

    /// Where an item is on screen right now.
    func placement(of item: EditorOverlay) -> OverlayPlacement {
        if let live, live.id == item.id { return live.placement }
        return item.placement
    }

    func reset() {
        renderTasks.values.forEach { $0.cancel() }
        renderTasks = [:]
        items = []
        selectedID = nil
        editingID = nil
        live = nil
        isMoving = false
        isOverTrash = false
        previews = [:]
        doodle = PKDrawing()
        doodleRevision += 1
        doodleSpace = nil
        doodleHistory = []
        canUndoDoodle = false
        textBeforeEditing = nil
    }

    func setMode(_ mode: Mode) {
        guard mode != self.mode else { return }
        if isEditingText { guard endEditing() else { return } }
        self.mode = mode
        // Drawing takes every touch, so nothing stays picked.
        if mode == .doodle { selectedID = nil }
        Haptics.selection()
    }

    // MARK: Adding

    /// A new text box, ready for typing.
    func addText() {
        if isEditingText { guard endEditing() else { return } }
        var style = textStyle
        style.text = ""
        let item = insert(.text(style))
        beginEditing(item.id)
    }

    func addSticker(_ kind: StickerKind) {
        insert(.sticker(Sticker(kind)))
        Haptics.tap()
    }

    func addPasted(_ sticker: PastedSticker) {
        insert(.pasted(sticker))
        Haptics.tap()
    }

    @discardableResult
    private func insert(_ content: OverlayContent) -> EditorOverlay {
        nextID += 1
        let item = EditorOverlay(id: nextID, content: content, placement: .newItem(index: items.count))
        items.append(item)
        selectedID = item.id
        // A new text box is drawn once she's typed it (an empty pill would flash).
        if content.text?.text.isEmpty != true { refreshPreview(of: item) }
        return item
    }

    // MARK: Picking

    /// Picks an item (nil: nothing). The panel follows: text controls for
    /// text, the sticker tray for stickers.
    func select(_ id: EditorOverlay.ID?) {
        guard id != selectedID else { return }
        if isEditingText { guard endEditing() else { return } }
        selectedID = id
        guard let id, let item = overlay(id) else { return }
        mode = item.content.text == nil ? .stickers : .text
        Haptics.selection()
    }

    /// Esc: stops typing, then lets go of the picked item.
    func dismissFocus() {
        if isEditingText {
            endEditing()
        } else {
            selectedID = nil
        }
    }

    func delete(_ id: EditorOverlay.ID) {
        if editingID == id {
            editingID = nil
            textBeforeEditing = nil
        }
        items.removeAll { $0.id == id }
        previews[id] = nil
        renderTasks.removeValue(forKey: id)?.cancel()
        if selectedID == id { selectedID = nil }
        if live?.id == id {
            live = nil
            isMoving = false
        }
        Haptics.tap()
    }

    func bringToFront(_ id: EditorOverlay.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index < items.count - 1 else { return }
        items.append(items.remove(at: index))
        Haptics.selection()
    }

    // MARK: Moving

    /// `moving`: a drag, which shows the trash.
    func setLive(_ id: EditorOverlay.ID, placement: OverlayPlacement, moving: Bool = false, overTrash: Bool = false) {
        live = LivePlacement(id: id, placement: placement)
        if moving != isMoving { isMoving = moving }
        if overTrash != isOverTrash {
            isOverTrash = overTrash
            if overTrash { Haptics.selection() }
        }
    }

    /// Her fingers lifted: the item stays where it is, or goes in the trash.
    func endLive() {
        guard let live else { return }
        self.live = nil
        isMoving = false
        if isOverTrash {
            isOverTrash = false
            delete(live.id)
            return
        }
        update(live.id) { $0 = live.placement }
    }

    /// VoiceOver's adjustable action and its turn actions.
    func resize(_ id: EditorOverlay.ID, by factor: Double) {
        update(id) { $0 = $0.scaled(by: factor) }
    }

    func rotate(_ id: EditorOverlay.ID, by angle: Double) {
        update(id) { $0 = $0.rotated(by: angle) }
    }

    private func update(_ id: EditorOverlay.ID, _ change: (inout OverlayPlacement) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let scale = items[index].placement.scale
        change(&items[index].placement)
        if items[index].placement.scale != scale { refreshPreview(of: items[index]) }
    }

    // MARK: Text

    func beginEditing(_ id: EditorOverlay.ID) {
        guard let text = overlay(id)?.content.text else { return }
        if let editingID, editingID != id { guard endEditing() else { return } }
        textBeforeEditing = text.text
        selectedID = id
        editingID = id
        mode = .text
    }

    func updateEditingText(_ text: String) {
        guard let id = editingID else { return }
        updateText(id) { $0.text = String(text.prefix(TextOverlay.maxLength)) }
    }

    /// Done typing. Empty text goes away. Words the content policy blocks
    /// aren't drawn: she hears why and keeps typing (false).
    @discardableResult
    func endEditing() -> Bool {
        guard let id = editingID, let text = overlay(id)?.content.text else {
            editingID = nil
            return true
        }
        let trimmed = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(id)
            return true
        }
        // Text drawn over the photo, like a Film Still subtitle: the text rules apply.
        if case .blocked(let reason, _) = ContentPolicy.evaluate(trimmed, operation: .textToImage) {
            notice = L10n.core(reason)
            Haptics.error()
            return false
        }
        editingID = nil
        textBeforeEditing = nil
        updateText(id) { $0.text = trimmed }
        return true
    }

    /// Font, colour, look and alignment change the text being typed or the
    /// picked one, and become the style of the next text box.
    var currentStyle: TextOverlay {
        styledID.flatMap { overlay($0)?.content.text } ?? textStyle
    }

    func setFont(_ font: OverlayFont) { restyle { $0.font = font } }
    func setColor(_ color: OverlayColor) { restyle { $0.color = color } }
    func cycleLook() { restyle { $0.look = $0.look.next } }
    func cycleAlignment() { restyle { $0.alignment = $0.alignment.next } }

    private var styledID: EditorOverlay.ID? {
        guard let id = editingID ?? selectedID, overlay(id)?.content.text != nil else { return nil }
        return id
    }

    private func restyle(_ change: (inout TextOverlay) -> Void) {
        var style = currentStyle
        change(&style)
        style.text = ""
        textStyle = style
        if let id = styledID { updateText(id, change) }
        Haptics.selection()
    }

    private func updateText(_ id: EditorOverlay.ID, _ change: (inout TextOverlay) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }), var text = items[index].content.text else { return }
        change(&text)
        items[index].content = .text(text)
        items[index].size = OverlayRenderer.artworkSize(of: items[index].content)
        // While she types, the editor shows the words; the bitmap waits for Done.
        if editingID != id { refreshPreview(of: items[index]) }
    }

    // MARK: Doodle

    func setBrush(_ brush: Brush) {
        guard brush != self.brush else { return }
        self.brush = brush
        Haptics.selection()
    }

    func setInkColor(_ color: OverlayColor) {
        inkColor = color
        if brush == .eraser { brush = .pen }
        Haptics.selection()
    }

    /// The tool for the canvas. Widths are in the doodle's points, which
    /// match the screen when drawing starts.
    var tool: PKTool {
        switch brush {
        case .pen: return inking(.pen, width: 5)
        case .marker: return inking(.monoline, width: 12)
        case .highlighter: return inking(.marker, width: 24)
        case .eraser: return PKEraserTool(.bitmap, width: 28)
        }
    }

    private func inking(_ type: PKInkingTool.InkType, width: CGFloat) -> PKInkingTool {
        let range = type.validWidthRange
        return PKInkingTool(type, color: inkColor.uiColor, width: min(max(width, range.lowerBound), range.upperBound))
    }

    /// Fixed when the canvas first lays out, so later layout changes (a
    /// turned iPad, a resized window) only zoom the drawing. Before the first
    /// stroke it follows the photo's shape (an Undo of a crop, say).
    func setDoodleSpaceIfNeeded(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        if let doodleSpace {
            let sameShape = abs(doodleSpace.width / doodleSpace.height - size.width / size.height) < 0.01
            guard !sameShape, doodle.strokes.isEmpty else { return }
        }
        doodleSpace = OverlayCanvas(width: size.width, height: size.height)
        #if DEBUG
        if drawsFixtureDoodle { drawFixtureDoodle() }
        #endif
    }

    /// A stroke went on or came off on the canvas.
    func doodleChanged(_ drawing: PKDrawing) {
        doodleHistory.append(doodle)
        if doodleHistory.count > 40 { doodleHistory.removeFirst() }
        doodle = drawing
        canUndoDoodle = true
    }

    func undoDoodle() {
        guard let previous = doodleHistory.popLast() else { return }
        doodle = previous
        doodleRevision += 1
        canUndoDoodle = !doodleHistory.isEmpty
        Haptics.tap()
    }

    func clearDoodle() {
        guard !doodle.strokes.isEmpty else { return }
        doodleHistory.append(doodle)
        doodle = PKDrawing()
        doodleRevision += 1
        canUndoDoodle = true
        Haptics.tap()
    }

    // MARK: Apply

    /// Everything to draw. Typing ends first; text the policy blocks is
    /// left out (or goes back to what it said before).
    func snapshot() -> Snapshot {
        if let id = editingID, !endEditing() {
            if let previous = textBeforeEditing, !previous.isEmpty,
               ContentPolicy.evaluate(previous, operation: .textToImage).isAllowed {
                editingID = nil
                updateText(id) { $0.text = previous }
            } else {
                delete(id)
            }
            editingID = nil
            textBeforeEditing = nil
        }
        endLive()
        let layers = items.map { OverlayRenderer.Layer(content: $0.content, size: $0.size, placement: $0.placement) }
        let pasted = items.compactMap { item -> PastedSticker? in
            if case .pasted(let sticker) = item.content { return sticker }
            return nil
        }
        let doodleLayer = doodleSpace.flatMap { space in
            doodle.strokes.isEmpty ? nil : OverlayRenderer.Doodle(drawing: doodle, space: space)
        }
        return Snapshot(
            layers: layers,
            doodle: doodleLayer,
            hasPasted: !pasted.isEmpty,
            pastedAIMarking: pasted.contains { $0.sourceType?.isGenerative == true } ? .compositeWithTrainedAlgorithmicMedia : nil
        )
    }

    // MARK: Previews

    /// The canvas reports its scale, so bitmaps match the screen.
    func setViewUnit(_ unit: CGFloat, displayScale: CGFloat) {
        guard unit > 0, abs(unit - viewUnit) > 0.0001 || displayScale != self.displayScale else { return }
        viewUnit = unit
        self.displayScale = displayScale
        items.forEach(refreshPreview(of:))
    }

    /// Renders an item's bitmap off the main actor when its look or size
    /// changed enough to matter.
    private func refreshPreview(of item: EditorOverlay) {
        guard viewUnit > 0 else { return }
        let id = item.id
        let content = item.content
        let size = item.size
        let pixelsPerUnit = Self.previewResolution(viewUnit * displayScale * CGFloat(item.placement.scale), size: size)
        if let preview = previews[id], preview.content == content, preview.pixelsPerUnit == pixelsPerUnit { return }
        renderTasks[id]?.cancel()
        renderTasks[id] = Task {
            let image = await Task.detached(priority: .userInitiated) {
                OverlayRenderer.image(of: content, size: size, pixelsPerUnit: pixelsPerUnit)
            }.value
            guard !Task.isCancelled, self.overlay(id)?.content == content else { return }
            previews[id] = Preview(content: content, pixelsPerUnit: pixelsPerUnit, image: image)
            renderTasks[id] = nil
        }
    }

    /// Steps of a third of an octave, so small pinches reuse the bitmap, and
    /// at most about 4 million pixels however big a sticker gets.
    private static func previewResolution(_ wanted: CGFloat, size: CGSize) -> CGFloat {
        let stepped = pow(2, ceil(log2(max(wanted, 0.05)) * 3) / 3)
        let cap = sqrt(4_000_000 / max(size.width * size.height, 1))
        return min(stepped, cap)
    }

    // MARK: Screenshots

    #if DEBUG
    /// Text, stickers and a doodle on the demo photo (`textStickers` scene).
    func loadScreenshotFixture(mode: Mode) {
        reset()
        let fixtures: [(OverlayContent, OverlayPlacement)] = [
            (.text(TextOverlay(text: "golden hour club", font: .script, color: .blush, look: .neon)),
             OverlayPlacement(x: 0.5, y: 0.16, scale: 1.3, rotation: -0.05)),
            (.sticker(Sticker(.butterfly)), OverlayPlacement(x: 0.17, y: 0.36, scale: 0.75, rotation: -0.3)),
            (.sticker(Sticker(.chromeHeart)), OverlayPlacement(x: 0.82, y: 0.38, scale: 1.05, rotation: 0.22)),
            (.sticker(Sticker(.sparkles)), OverlayPlacement(x: 0.62, y: 0.3, scale: 0.5)),
            (.text(TextOverlay(text: "core memory", font: .poppins, color: .butter, look: .pill)),
             OverlayPlacement(x: 0.32, y: 0.63, scale: 0.95, rotation: -0.1)),
            (.sticker(Sticker(.omg)), OverlayPlacement(x: 0.74, y: 0.74, scale: 0.85, rotation: 0.12)),
            (.sticker(Sticker(.dateStamp)), OverlayPlacement(x: 0.78, y: 0.94, scale: 0.9)),
        ]
        for (content, placement) in fixtures {
            nextID += 1
            items.append(EditorOverlay(id: nextID, content: content, placement: placement))
        }
        self.mode = mode
        // Text: "core memory" and its style; stickers: the OMG bubble.
        if mode != .doodle { selectedID = items[mode == .text ? 4 : 5].id }
        drawsFixtureDoodle = true
        // -GLOverlayEdit YES: the typing screen on "core memory".
        if mode == .text, UserDefaults.standard.bool(forKey: "GLOverlayEdit") { beginEditing(items[4].id) }
    }

    /// A hand-drawn heart and an underline, once the canvas size is known.
    private func drawFixtureDoodle() {
        guard let space = doodleSpace else { return }
        func stroke(_ points: [CGPoint], color: UIColor, width: CGFloat) -> PKStroke {
            let samples = points.enumerated().map { index, point in
                PKStrokePoint(location: CGPoint(x: point.x * space.width, y: point.y * space.height),
                              timeOffset: TimeInterval(index) * 0.016, size: CGSize(width: width, height: width),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: samples, creationDate: Date()))
        }
        // The classic heart curve, around the chrome heart.
        let heart = (0...72).map { step -> CGPoint in
            let t = Double(step) / 72 * 2 * .pi
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            return CGPoint(x: 0.82 + x / 16 * 0.15, y: 0.39 - y / 17 * 0.12)
        }
        let underline = (0...40).map { step -> CGPoint in
            let t = Double(step) / 40
            return CGPoint(x: 0.24 + t * 0.52, y: 0.235 + sin(t * .pi * 5) * 0.006)
        }
        doodle = PKDrawing(strokes: [
            stroke(heart, color: .white, width: 5),
            stroke(underline, color: .auraPink, width: 6),
        ])
        doodleRevision += 1
        drawsFixtureDoodle = false
    }
    #endif
}
