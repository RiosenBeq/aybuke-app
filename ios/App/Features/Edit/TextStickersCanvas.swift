import SwiftUI
import PencilKit
import AppCore

/// Text & Stickers on the photo: drag to move, pinch (or the corner handle)
/// to resize and turn, tap to pick, tap picked text to retype it, drop on
/// the trash to delete. In Doodle every touch goes to PencilKit.
struct TextStickersCanvas: View {
    let image: UIImage
    let session: OverlaySession

    @Environment(\.displayScale) private var displayScale

    static let space = "textStickersCanvas"

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let canvas = OverlayCanvas(width: size.width, height: size.height)
            ZStack(alignment: .topLeading) {
                // The shadow sits on a still shape, so dragging doesn't redraw it.
                RoundedRectangle.control
                    .fill(Palette.surface)
                    .shadow(color: Palette.shadow, radius: 16, y: 8)
                    .frame(width: size.width, height: size.height)
                    .accessibilityHidden(true)
                ZStack(alignment: .topLeading) {
                    if ImageUtilities.hasAlpha(image) {
                        CheckerboardBackground()
                    }
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .accessibilityLabel("Photo")
                    ForEach(session.items) { item in
                        OverlayItemView(
                            item: item,
                            placement: session.placement(of: item),
                            preview: session.previews[item.id],
                            canvas: canvas,
                            isEditing: session.editingID == item.id,
                            isSelected: session.selectedID == item.id,
                            session: session
                        )
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(.control)

                // Touches, and the doodle above the items as in the final photo.
                OverlayInteractionLayer(session: session, size: size)
                    .frame(width: size.width, height: size.height)

                if let selected = session.selected, !session.isEditingText, session.mode != .doodle, !session.isMoving {
                    SelectionChrome(item: selected, placement: session.placement(of: selected), canvas: canvas, session: session)
                }

                // Only the trash animates; the dragged item follows the finger.
                ZStack {
                    if session.isMoving {
                        trash
                            .position(OverlayGestureView.trashCenter(in: size))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
                .animation(.snappy, value: session.isMoving)
            }
            .coordinateSpace(.named(Self.space))
            .onAppear { layout(size) }
            .onChange(of: size) { _, size in layout(size) }
            .onChange(of: displayScale) { layout(size) }
            // Apply starts a fresh session on the same canvas.
            .onChange(of: session.doodleSpace == nil) { layout(size) }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
    }

    private func layout(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        session.setViewUnit(CGFloat(OverlayCanvas(width: size.width, height: size.height).unit), displayScale: displayScale)
        session.setDoodleSpaceIfNeeded(size)
    }

    private var trash: some View {
        Image(systemName: session.isOverTrash ? "trash.fill" : "trash")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Palette.white)
            .frame(width: 52, height: 52)
            .background(session.isOverTrash ? Palette.danger : Palette.ink.opacity(0.6), in: Circle())
            .overlay(Circle().strokeBorder(Palette.white.opacity(0.8), lineWidth: 1.5))
            .scaleEffect(session.isOverTrash ? 1.18 : 1)
            .animation(.snappy, value: session.isOverTrash)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: Items

/// One text box or sticker: its bitmap, placed and turned like the photo
/// will get it. Touches go to the gesture layer; VoiceOver gets actions.
private struct OverlayItemView: View {
    let item: EditorOverlay
    let placement: OverlayPlacement
    let preview: OverlaySession.Preview?
    let canvas: OverlayCanvas
    let isEditing: Bool
    let isSelected: Bool
    let session: OverlaySession

    var body: some View {
        let points = canvas.unit * placement.scale
        Group {
            if let preview {
                Image(uiImage: preview.image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: item.size.width * points, height: item.size.height * points)
        .rotationEffect(.radians(placement.rotation))
        .position(x: placement.x * canvas.width, y: placement.y * canvas.height)
        // While she types, the full-screen editor shows the words.
        .opacity(isEditing ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.content.accessibilityName))
        .accessibilityValue(Text(placement.scale, format: .percent.precision(.fractionLength(0))))
        .accessibilityHint("Adjust to change the size")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: session.resize(item.id, by: 1.2)
            case .decrement: session.resize(item.id, by: 1 / 1.2)
            @unknown default: break
            }
        }
        .accessibilityAction { session.select(item.id) }
        .accessibilityActions {
            if item.content.text != nil {
                Button("Edit text") { session.beginEditing(item.id) }
            }
            Button("Delete") { session.delete(item.id) }
            Button("Bring to front") { session.bringToFront(item.id) }
            Button("Turn left") { session.rotate(item.id, by: -.pi / 12) }
            Button("Turn right") { session.rotate(item.id, by: .pi / 12) }
        }
    }
}

/// A dashed box around the picked item with delete, bring-to-front and a
/// corner handle that resizes and turns with one finger (or a mouse).
private struct SelectionChrome: View {
    let item: EditorOverlay
    let placement: OverlayPlacement
    let canvas: OverlayCanvas
    let session: OverlaySession

    @State private var handleStart: OverlayPlacement?

    var body: some View {
        let points = canvas.unit * placement.scale
        let width = item.size.width * points + 8
        let height = item.size.height * points + 8
        RoundedRectangle.chip
            .strokeBorder(Palette.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .shadow(color: .black.opacity(0.4), radius: 1.5)
            .allowsHitTesting(false)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                chromeButton("xmark", label: "Delete") { session.delete(item.id) }
                    .offset(x: -22, y: -22)
            }
            .overlay(alignment: .topTrailing) {
                chromeButton("square.3.layers.3d.top.filled", label: "Bring to front") { session.bringToFront(item.id) }
                    .offset(x: 22, y: -22)
            }
            .overlay(alignment: .bottomTrailing) {
                handle.offset(x: 22, y: 22)
            }
            .rotationEffect(.radians(placement.rotation))
            .position(x: placement.x * canvas.width, y: placement.y * canvas.height)
    }

    private func chromeButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 26, height: 26)
                .background(Palette.white, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var handle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.onPrimary)
            .frame(width: 26, height: 26)
            .background(Palette.blush, in: Circle())
            .overlay(Circle().strokeBorder(Palette.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .gesture(
                // The canvas's own space: the handle turns with the box.
                DragGesture(minimumDistance: 0, coordinateSpace: .named(TextStickersCanvas.space))
                    .onChanged { value in
                        let start = handleStart ?? item.placement
                        if handleStart == nil { handleStart = start }
                        var next = start.dragged(handleFrom: (Double(value.startLocation.x), Double(value.startLocation.y)),
                                                 to: (Double(value.location.x), Double(value.location.y)), in: canvas)
                        next.rotation = OverlayPlacement.snapped(next.rotation)
                        session.setLive(item.id, placement: next)
                    }
                    .onEnded { _ in
                        handleStart = nil
                        session.endLive()
                    }
            )
            .accessibilityHidden(true)
    }
}

// MARK: Touches and the doodle

/// Multi-touch in UIKit (SwiftUI on iOS 17 can't move with the pinch), with
/// the PencilKit canvas inside, so one view decides who gets each touch:
/// the items, or the doodle in Doodle mode.
private struct OverlayInteractionLayer: UIViewRepresentable {
    let session: OverlaySession
    let size: CGSize

    func makeUIView(context: Context) -> OverlayGestureView {
        OverlayGestureView()
    }

    func updateUIView(_ view: OverlayGestureView, context: Context) {
        view.update(session: session, size: size)
    }
}

/// Moves, pinches and turns one item at a time, all at once; a tap picks.
/// Pinching away from every item works on the picked one.
final class OverlayGestureView: UIView, UIGestureRecognizerDelegate, PKCanvasViewDelegate {
    private weak var session: OverlaySession?
    private var canvasSize = CGSize.zero
    private var recognizers: [UIGestureRecognizer] = []

    private var target: EditorOverlay.ID?
    private var start = OverlayPlacement()
    private var joined = Set<ObjectIdentifier>()
    private var translation = CGPoint.zero
    private var scale: CGFloat = 1
    private var rotation: CGFloat = 0
    private var isRotating = false
    private var wasSnapped = false

    /// The doodle's own space is the canvas size when drawing started;
    /// later layouts only zoom it, so strokes stay put.
    private let doodleView = DoodleCanvasView()
    private var doodleSpace: OverlayCanvas?
    private var doodleRevision = -1
    private var isLoadingDoodle = false

    static func trashCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height - 44)
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        doodleView.delegate = self
        doodleView.drawingPolicy = .anyInput
        doodleView.backgroundColor = .clear
        doodleView.isOpaque = false
        // Inks keep their colours in Dark Mode, as they will in the photo.
        doodleView.overrideUserInterfaceStyle = .light
        doodleView.isScrollEnabled = false
        doodleView.bouncesZoom = false
        doodleView.showsVerticalScrollIndicator = false
        doodleView.showsHorizontalScrollIndicator = false
        doodleView.contentInsetAdjustmentBehavior = .never
        doodleView.accessibilityLabel = String(localized: "Drawing")
        doodleView.accessibilityHint = String(localized: "Draw on the photo")
        addSubview(doodleView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        recognizers = [pan, pinch, rotate, tap]
        for recognizer in recognizers {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(session: OverlaySession, size: CGSize) {
        self.session = session
        canvasSize = size
        let isDrawing = session.mode == .doodle
        // In Doodle every touch is a stroke; nothing else may claim it.
        for recognizer in recognizers where recognizer.isEnabled == isDrawing {
            recognizer.isEnabled = !isDrawing
        }
        doodleView.isUserInteractionEnabled = isDrawing
        accessibilityElementsHidden = !isDrawing
        doodleSpace = session.doodleSpace
        doodleView.isHidden = doodleSpace == nil
        if doodleRevision != session.doodleRevision {
            doodleRevision = session.doodleRevision
            isLoadingDoodle = true
            doodleView.drawing = session.doodle
            isLoadingDoodle = false
        }
        doodleView.tool = session.tool
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        doodleView.frame = bounds
        guard let doodleSpace, bounds.width > 1 else { return }
        let fit = bounds.width / CGFloat(doodleSpace.width)
        if doodleView.minimumZoomScale != fit || doodleView.maximumZoomScale != fit {
            doodleView.minimumZoomScale = fit
            doodleView.maximumZoomScale = fit
        }
        if abs(doodleView.zoomScale - fit) > 0.0001 { doodleView.zoomScale = fit }
        doodleView.contentSize = CGSize(width: CGFloat(doodleSpace.width) * fit, height: CGFloat(doodleSpace.height) * fit)
        doodleView.contentOffset = .zero
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isLoadingDoodle else { return }
        session?.doodleChanged(canvasView.drawing)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other.view === self
    }

    private var canvas: OverlayCanvas { OverlayCanvas(width: canvasSize.width, height: canvasSize.height) }

    private var isActive: Bool {
        guard let session else { return false }
        return session.mode != .doodle && !session.isEditingText
    }

    /// The topmost item under a point, a little generous for small stickers.
    private func item(at point: CGPoint) -> EditorOverlay? {
        session?.items.reversed().first { item in
            item.placement.contains(x: point.x, y: point.y, artworkWidth: item.size.width, artworkHeight: item.size.height,
                                    slop: 10, in: canvas)
        }
    }

    // MARK: Taps

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard isActive, let session else { return }
        guard let hit = item(at: recognizer.location(in: self)) else {
            session.select(nil)
            return
        }
        // A tap on the picked text opens it for typing.
        if hit.id == session.selectedID, hit.content.text != nil {
            session.beginEditing(hit.id)
        } else {
            session.select(hit.id)
        }
    }

    // MARK: Manipulation

    /// A recognizer joins the item being handled, or picks one: the item
    /// under the touch, else (pinch and turn only) the picked one.
    private func join(_ recognizer: UIGestureRecognizer, at point: CGPoint, usesSelection: Bool) -> Bool {
        guard isActive, let session else { return false }
        if target == nil {
            guard let id = item(at: point)?.id ?? (usesSelection ? session.selectedID : nil),
                  let item = session.overlay(id) else { return false }
            target = id
            start = item.placement
            translation = .zero
            scale = 1
            rotation = 0
            isRotating = false
            session.select(id)
        }
        joined.insert(ObjectIdentifier(recognizer))
        return true
    }

    private func leave(_ recognizer: UIGestureRecognizer) {
        guard joined.remove(ObjectIdentifier(recognizer)) != nil, joined.isEmpty else { return }
        target = nil
        session?.endLive()
    }

    /// `trashPoint`: a one-finger drag's location, which shows the trash.
    private func update(trashPoint: CGPoint? = nil) {
        guard let target, let session else { return }
        var next = start.moved(dx: translation.x, dy: translation.y, in: canvas)
            .scaled(by: Double(scale))
            .rotated(by: Double(rotation))
        if isRotating {
            let snapped = OverlayPlacement.snapped(next.rotation)
            let isSnapped = snapped != next.rotation
            if isSnapped && !wasSnapped { Haptics.selection() }
            wasSnapped = isSnapped
            next.rotation = snapped
        }
        // Only a drag on its own can delete, so a pinch never does.
        let moving = trashPoint != nil && joined.count == 1
        var overTrash = false
        if moving, let trashPoint {
            let center = Self.trashCenter(in: canvasSize)
            overTrash = hypot(trashPoint.x - center.x, trashPoint.y - center.y) < 40
        }
        session.setLive(target, placement: next, moving: moving, overTrash: overTrash)
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let oneFinger = recognizer.numberOfTouches == 1
        switch recognizer.state {
        case .began:
            // Where the finger came down, before the pan's first few points.
            let point = recognizer.location(in: self)
            let moved = recognizer.translation(in: self)
            guard join(recognizer, at: CGPoint(x: point.x - moved.x, y: point.y - moved.y), usesSelection: false) else { return }
            translation = moved
            update(trashPoint: oneFinger ? point : nil)
        case .changed:
            guard joined.contains(ObjectIdentifier(recognizer)) else { return }
            translation = recognizer.translation(in: self)
            update(trashPoint: oneFinger ? recognizer.location(in: self) : nil)
        case .ended, .cancelled, .failed:
            leave(recognizer)
        default:
            break
        }
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard join(recognizer, at: recognizer.location(in: self), usesSelection: true) else { return }
            recognizer.scale = 1
        case .changed:
            guard joined.contains(ObjectIdentifier(recognizer)) else { return }
            scale = recognizer.scale
            update()
        case .ended, .cancelled, .failed:
            leave(recognizer)
        default:
            break
        }
    }

    @objc private func rotated(_ recognizer: UIRotationGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard join(recognizer, at: recognizer.location(in: self), usesSelection: true) else { return }
            recognizer.rotation = 0
            isRotating = true
            wasSnapped = false
        case .changed:
            guard joined.contains(ObjectIdentifier(recognizer)) else { return }
            rotation = recognizer.rotation
            update()
        case .ended, .cancelled, .failed:
            leave(recognizer)
        default:
            break
        }
    }
}

final class DoodleCanvasView: PKCanvasView {
    /// The panel's Undo takes strokes back. PencilKit's own undo would mix
    /// them into Edit › Undo and shake to undo, so it registers nothing.
    private let quietUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.disableUndoRegistration()
        return manager
    }()

    override var undoManager: UndoManager? { quietUndoManager }
}

// MARK: Typing

/// Typing over the dimmed photo: her words big enough to read, in her font,
/// colour and style, with the style rows above the keyboard. Done (or a tap
/// outside) puts the text back on the photo.
struct OverlayTextEditor: View {
    let session: OverlaySession

    @FocusState private var isFocused: Bool

    var body: some View {
        let style = session.currentStyle
        ZStack {
            Palette.ink.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { session.endEditing() }
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    Button {
                        session.endEditing()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(Palette.blush, in: .chip)
                    }
                    .buttonStyle(.pressable)
                }
                // The field hugs her words, so a pill looks like the photo's.
                GeometryReader { proxy in
                    TextField(
                        "",
                        text: Binding(get: { session.editingText }, set: { session.updateEditingText($0) }),
                        prompt: Text(Self.placeholder).foregroundStyle(Palette.white.opacity(0.6)),
                        axis: .vertical
                    )
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .font(Font(style.font.uiFont(size: Self.fontSize) as CTFont))
                    .multilineTextAlignment(style.alignment.swiftUIAlignment)
                    .frame(width: fieldWidth(style, available: proxy.size.width))
                    .modifier(TextLookPreview(style: style))
                    .tint(Palette.blush)
                    .accessibilityLabel("Text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                TextStyleRows(session: session)
                    .padding(12)
                    .background(Palette.surface, in: .card)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
            .readableWidth(Metrics.compactWidth, alignment: .center)
            // VoiceOver stays here, not on the dimmed editor behind.
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { isFocused = true }
    }

    private static let fontSize: CGFloat = 32
    private static var placeholder: String { String(localized: "Type something") }

    /// The words' width in the field's font, with room for the caret, within
    /// the space the pill's padding leaves.
    private func fieldWidth(_ style: TextOverlay, available: CGFloat) -> CGFloat {
        let limit = max(available - 48, 80)
        let text = session.editingText.isEmpty ? Self.placeholder : session.editingText
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: limit, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: style.font.uiFont(size: Self.fontSize)], context: nil
        )
        return min(ceil(bounds.width) + 16, limit)
    }
}

/// The text's look in SwiftUI, close to what `TextArt` draws: for the
/// editor's field and the style button.
struct TextLookPreview: ViewModifier {
    let style: TextOverlay
    var scale: CGFloat = 1

    func body(content: Content) -> some View {
        let color = Color(hex: style.color.hex)
        let contrast = style.color.isLight ? Palette.ink : Palette.white
        switch style.look {
        case .plain:
            content
                .foregroundStyle(color)
                .shadow(color: (style.color.isLight ? Color.black : Color.white).opacity(0.35), radius: 3 * scale)
        case .outline:
            let width = 1.6 * scale
            content
                .foregroundStyle(color)
                .shadow(color: contrast, radius: 0, x: width, y: width)
                .shadow(color: contrast, radius: 0, x: -width, y: -width)
                .shadow(color: contrast, radius: 0, x: width, y: -width)
                .shadow(color: contrast, radius: 0, x: -width, y: width)
        case .pill:
            content
                .foregroundStyle(contrast)
                .padding(.horizontal, 14 * scale)
                .padding(.vertical, 5 * scale)
                .background(color, in: RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
        case .neon:
            content
                .foregroundStyle(Color(uiColor: style.color.uiColor.mixed(with: .white, amount: 0.6)))
                .shadow(color: color, radius: 10 * scale)
                .shadow(color: color, radius: 4 * scale)
        }
    }
}

extension OverlayAlignment {
    var swiftUIAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
