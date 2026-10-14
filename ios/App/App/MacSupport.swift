import SwiftUI
import UniformTypeIdentifiers

// The Mac app is the iPad app running in Mac Catalyst ("Scale Interface to
// Match iPad"). Everything here only switches on in the Mac app, but the
// parts with text are compiled for iOS too: `-exportLocalizations` builds for
// iOS, and this way it still extracts their strings.

enum Platform {
    /// True in the Mac app. Copy that says "iPhone" picks its Mac wording
    /// with this at runtime rather than `#if`, for the reason above.
    static let isMac = ProcessInfo.processInfo.isMacCatalystApp
}

// MARK: - Menu bar

/// The Mac menu bar: Aybuke › Settings…; File › New Creation, Open Photo…
/// and Open Video…; Edit › Undo and Redo for the editor's steps; View › the
/// sidebar and the four sections; Help › Contact support. Each item uses the
/// same entry point as the matching button in the app.
struct GlowlitCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { perform { app.isSettingsPresented = true } }
                .keyboardShortcut(",")
                .disabled(!app.acceptsCommands)
        }
        // Replaces File › New Window: the app keeps one window, whose state
        // (sheets, the editor) lives in the shared AppModel.
        CommandGroup(replacing: .newItem) {
            if app.allowsCloudAI {
                Button("New Creation") {
                    perform {
                        app.handle(.create)
                        app.wantsPromptFocus = true
                    }
                }
                .keyboardShortcut("n")
                .disabled(!app.acceptsCommands)
            }
            Button("Open Photo…") { perform { app.handle(.magicEdit) } }
                .keyboardShortcut("o")
                .disabled(!app.acceptsCommands)
            Button("Open Video…") { perform { app.handle(.video) } }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(!app.acceptsCommands)
        }
        // Not a document app: no Export. Close and Save act on what's on
        // screen. This group also holds the system's Close, so it's written
        // out again here. Neither is gated by acceptsCommands: covers are up.
        CommandGroup(replacing: .saveItem) {
            Button("Close") { app.closePresented() }
                .keyboardShortcut("w")
                .disabled(!app.canClosePresented)
            Button("Save") { app.saveActiveCover?() }
                .keyboardShortcut("s")
                .disabled(app.saveActiveCover == nil)
        }
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .undoRedo) {
            EditorUndoCommands(app: app)
        }
        CommandGroup(replacing: .sidebar) {
            Button(app.macSidebarVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar") {
                perform { app.toggleMacSidebar() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(!app.acceptsCommands)
        }
        // The sections live in the sidebar, so View lists them instead of
        // Show and Customize Toolbar. (`before: .toolbar` would list them backwards.)
        CommandGroup(replacing: .toolbar) {
            tabButton("Explore", tab: .home, key: "1")
            if app.allowsCloudAI {
                tabButton("Create", tab: .create, key: "2")
            }
            tabButton("Edit", tab: .edit, key: "3")
            tabButton("My Works", tab: .library, key: "4")
        }
        // There's no Help book; the default item would only say so.
        CommandGroup(replacing: .help) {
            if let support = app.config.supportURL {
                Button("Contact support") { UIApplication.shared.open(support) }
            }
        }
    }

    private func tabButton(_ title: LocalizedStringKey, tab: AppTab, key: KeyEquivalent) -> some View {
        Button(title) { perform { app.selectedTab = tab } }
            .keyboardShortcut(key)
            .disabled(!app.acceptsCommands)
    }

    /// Screens keep some sheets and alerts in their own state (Invite, legal
    /// pages, confirmations), so also ask UIKit whether one is up.
    private func perform(_ action: () -> Void) {
        guard app.acceptsCommands, !MacResponders.isPresenting else { return }
        action()
    }
}

/// Edit › Undo and Redo. While she types, they undo her typing, as anywhere
/// on the Mac; in the editor they step through its history, like its Undo
/// and Redo buttons.
private struct EditorUndoCommands: View {
    let app: AppModel

    var body: some View {
        let editor = app.activeEditor
        let typing = MacTextEditing.shared.isEditing
        Button("Undo") {
            if let editor, !MacResponders.isEditingText {
                if editor.canUndo && !editor.isProcessing { editor.undo() }
            } else {
                MacResponders.firstResponderUndoManager?.undo()
            }
        }
        .keyboardShortcut("z")
        .disabled(!typing && !(editor.map { $0.canUndo && !$0.isProcessing } ?? false))
        Button("Redo") {
            if let editor, !MacResponders.isEditingText {
                if editor.canRedo && !editor.isProcessing { editor.redo() }
            } else {
                MacResponders.firstResponderUndoManager?.redo()
            }
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!typing && !(editor.map { $0.canRedo && !$0.isProcessing } ?? false))
    }
}

/// Whether she's typing in a text field, kept current from UIKit's editing
/// notifications so the Edit menu can follow it.
@MainActor
@Observable
final class MacTextEditing {
    static let shared = MacTextEditing()
    private(set) var isEditing = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    static func startWatching() {
        guard shared.observers.isEmpty else { return }
        let names: [(Notification.Name, Bool)] = [
            (UITextField.textDidBeginEditingNotification, true), (UITextField.textDidEndEditingNotification, false),
            (UITextView.textDidBeginEditingNotification, true), (UITextView.textDidEndEditingNotification, false),
        ]
        shared.observers = names.map { name, editing in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { shared.isEditing = editing }
            }
        }
    }
}

/// What UIKit has in focus: a text field she's typing in, a sheet that's up.
@MainActor
enum MacResponders {
    static var isPresenting: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }

    static var isEditingText: Bool { firstResponder is UITextInput }

    static var firstResponderUndoManager: UndoManager? { firstResponder?.undoManager }

    private static weak var found: UIResponder?

    /// The first responder, found by sending it an action (UIKit has no getter).
    static var firstResponder: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.glowlitCaptureFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    fileprivate static func capture(_ responder: UIResponder) { found = responder }
}

extension UIResponder {
    @objc fileprivate func glowlitCaptureFirstResponder() {
        MacResponders.capture(self)
    }
}

// MARK: - Window

/// The Mac window's sizes, in the app's (iPad) points: 77% of these on screen.
enum MacWindow {
    /// The sidebar, a section of comfortable width and the editor's panels.
    static let minimumSize = CGSize(width: 960, height: 660)
    /// The first window: roomy, but never past most of the screen.
    static let preferredSize = CGSize(width: 1560, height: 1040)

    /// The window's size in the app's points (zero before there is one).
    @MainActor
    static var currentSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.coordinateSpace.bounds.size ?? .zero
    }
}

#if targetEnvironment(macCatalyst)
/// Sets up each Mac window once it's on screen: no title text (each section
/// has its own heading, and the sidebar names it), a minimum size that keeps
/// the sidebar, the editor and sheets usable, and a roomy first size.
struct MacWindowSetup: UIViewRepresentable {
    func makeUIView(context: Context) -> SetupView {
        let view = SetupView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SetupView, context: Context) {}

    final class SetupView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene else { return }
            scene.titlebar?.titleVisibility = .hidden
            scene.sizeRestrictions?.minimumSize = MacWindow.minimumSize
            MacTextEditing.startWatching()
            #if DEBUG
            // `-GLWindowSize 1280x800` pins the window to one size, so Mac App
            // Store screenshots come out alike.
            let parts = UserDefaults.standard.string(forKey: "GLWindowSize")?.split(separator: "x").compactMap { Double($0) }
            if let parts, parts.count == 2 {
                let size = CGSize(width: parts[0], height: parts[1])
                scene.sizeRestrictions?.minimumSize = size
                scene.sizeRestrictions?.maximumSize = size
                return
            }
            #endif
            MacWindow.sizeFirstWindow(scene)
        }
    }
}

extension MacWindow {
    private static let sizedKey = "mac.window.firstSizeApplied"

    /// Once, on the first launch: a roomy window in the middle of the screen
    /// (the system's first one is small for a photo app). Later launches keep
    /// the size and place she left it at.
    @MainActor
    static func sizeFirstWindow(_ scene: UIWindowScene) {
        guard !UserDefaults.standard.bool(forKey: sizedKey) else { return }
        Task { @MainActor in
            // The window's frame on the screen is known a moment after it appears.
            for _ in 0..<20 where scene.effectiveGeometry.systemFrame.width == 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            let frame = scene.effectiveGeometry.systemFrame
            let bounds = scene.coordinateSpace.bounds
            guard frame.width > 0, bounds.width > 0 else { return }
            UserDefaults.standard.set(true, forKey: sizedKey)
            // The screen and the frame are in the Mac's points; the app's
            // points are larger (it draws at 77%).
            let screen = scene.screen.bounds.size
            let scale = frame.width / bounds.width
            let size = CGSize(width: min(preferredSize.width * scale, screen.width * 0.9),
                              height: min(preferredSize.height * scale, screen.height * 0.85))
            let origin = CGPoint(x: ((screen.width - size.width) / 2).rounded(), y: ((screen.height - size.height) / 2).rounded())
            scene.requestGeometryUpdate(.Mac(systemFrame: CGRect(origin: origin, size: size)))
        }
    }
}
#endif

extension View {
    /// A keyboard shortcut in the Mac app only (Esc to close, ⌘S to save),
    /// so iPhone and iPad keep their behavior.
    @ViewBuilder
    func macKeyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        #if targetEnvironment(macCatalyst)
        keyboardShortcut(shortcut)
        #else
        self
        #endif
    }

    /// A shortcut for iPad hardware keyboards only. On the Mac the same keys
    /// are menu items (Edit › Undo, ⌘Z), which reach the same action.
    func padKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        keyboardShortcut(key, modifiers: modifiers)
        #endif
    }

    /// Mac: a tooltip, so an icon-only button says what it does under the
    /// pointer. iPhone and iPad are unchanged.
    /// Literals pick the `LocalizedStringKey` form, which is what the string
    /// catalogs extract. The `Text` form is disfavored so a literal isn't
    /// ambiguous; it stays for callers that already hold a `Text`.
    @ViewBuilder
    func macHelp(_ text: LocalizedStringKey) -> some View {
        if Platform.isMac {
            help(text)
        } else {
            self
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    func macHelp(_ text: Text) -> some View {
        if Platform.isMac {
            help(text)
        } else {
            self
        }
    }

    /// Mac: a card fills its grid cell, so cards in a row line up.
    @ViewBuilder
    func macFillsCell(alignment: Alignment = .leading) -> some View {
        if Platform.isMac {
            frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        } else {
            self
        }
    }

    /// Mac: a page no wider than `Metrics.pageWidth`, centred in the window.
    @ViewBuilder
    func macPageWidth() -> some View {
        if Platform.isMac {
            frame(maxWidth: Metrics.pageWidth).frame(maxWidth: .infinity)
        } else {
            self
        }
    }

    /// Mac: a paragraph on a wide page keeps a readable line length.
    @ViewBuilder
    func macTextWidth() -> some View {
        if Platform.isMac {
            frame(maxWidth: Metrics.textWidth, alignment: .leading)
        } else {
            self
        }
    }

    /// Mac: cards and tiles lift a little under the pointer, so it's clear
    /// what a click opens. iPhone and iPad are unchanged.
    func macHoverLift(scale: CGFloat = 1.02) -> some View {
        modifier(MacHoverLift(scale: scale))
    }

    /// Mac: the title bar stays above full-window covers, so a section's
    /// toolbar items (Library's Select) hide while one is up. iPhone and iPad
    /// are unchanged.
    @ViewBuilder
    func hidesMacToolbar(_ hidden: Bool) -> some View {
        #if targetEnvironment(macCatalyst)
        toolbar(hidden ? .hidden : .automatic, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Mac: drop a photo file anywhere on the main screens to open it in the
    /// editor, as if it had been picked from Explore's Magic Edit card.
    func acceptsDroppedPhotos() -> some View {
        modifier(PhotoDropTarget())
    }
}

private struct MacHoverLift: ViewModifier {
    let scale: CGFloat
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if Platform.isMac {
            content
                .scaleEffect(isHovering && !reduceMotion ? scale : 1)
                .brightness(isHovering ? 0.02 : 0)
                .animation(.snappy(duration: 0.2), value: isHovering)
                .onHover { isHovering = $0 }
        } else {
            content
        }
    }
}

// MARK: - Sheets

enum MacSheetSize {
    /// Settings, credits, consent, account: a column of rows and text.
    case form
    /// Paywall, share composer, invite, Best shot: pictures and plans.
    case page

    var size: CGSize {
        switch self {
        case .form: return CGSize(width: 700, height: 840)
        case .page: return CGSize(width: 880, height: 1000)
        }
    }
}

extension View {
    /// A Mac sheet: a fixed, comfortable size instead of the iPad's (which
    /// grows with the window), and Esc closes it, as Mac sheets do. iPhone
    /// and iPad are unchanged. Applied to the sheet's content.
    @ViewBuilder
    func macSheet(_ size: MacSheetSize) -> some View {
        if Platform.isMac {
            modifier(MacSheet(size: size))
        } else {
            self
        }
    }
}

private struct MacSheet: ViewModifier {
    let size: MacSheetSize
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        sized(content)
            .background {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    @ViewBuilder
    private func sized(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(FixedSheetSizing(size: size.size))
        } else {
            content
        }
    }
}

/// A fixed size, with room around it in a small window. Asked again as the
/// window changes, so it reads the window then rather than when the sheet
/// was made (which can be before the window is on screen).
@available(iOS 18.0, *)
private struct FixedSheetSizing: PresentationSizing {
    let size: CGSize

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        var window = CGSize.zero
        if Thread.isMainThread {
            window = MainActor.assumeIsolated { MacWindow.currentSize }
        }
        guard window.width > 0, window.height > 0 else { return ProposedViewSize(size) }
        return ProposedViewSize(width: min(size.width, window.width - 96), height: min(size.height, window.height - 80))
    }
}

// MARK: - Drag and drop

/// Any image file (JPEG, PNG, HEIC, RAW…) dragged in from Finder or Photos.
struct DroppedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { DroppedPhoto(data: $0) }
    }
}

private struct PhotoDropTarget: ViewModifier {
    @Environment(AppModel.self) private var app
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if Platform.isMac {
            content
                .overlay {
                    if isTargeted {
                        DropHint().transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
                .dropDestination(for: DroppedPhoto.self) { photos, _ in
                    guard let photo = photos.first, app.acceptsCommands else { return false }
                    Task { await app.openDroppedPhoto(photo.data) }
                    return true
                } isTargeted: { targeted in
                    isTargeted = targeted && app.acceptsCommands
                }
        } else {
            content
        }
    }
}

private struct DropHint: View {
    var body: some View {
        ZStack {
            Palette.background.opacity(0.75)
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                .padding(Metrics.gutter)
            Label("Drop a photo to edit it", systemImage: "photo.badge.plus")
                .font(.headline)
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Palette.accent, in: .chip)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
