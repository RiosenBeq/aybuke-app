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

/// The Mac menu bar: Glowlit › Settings…, File › New Creation and Open
/// Photo…, the tabs in View, and Help › Contact support. Each item uses the
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
            Button("New Creation") { perform { app.handle(.create) } }
                .keyboardShortcut("n")
                .disabled(!app.acceptsCommands)
            Button("Open Photo…") { perform { app.handle(.magicEdit) } }
                .keyboardShortcut("o")
                .disabled(!app.acceptsCommands)
        }
        // The tabs live in the toolbar, so View lists them instead of Show and
        // Customize Toolbar. (`before: .toolbar` would list them backwards.)
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
        let isPresenting = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
        guard app.acceptsCommands, !isPresenting else { return }
        action()
    }
}

// MARK: - Window

#if targetEnvironment(macCatalyst)
/// Sets up each Mac window once it's on screen: no title text (Explore's
/// header already says Glowlit, and the tabs sit in the title bar) and a
/// minimum size that keeps the editor and sheets usable.
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
            scene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 640)
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

    /// A shortcut for iPad hardware keyboards only. On the Mac, keys such as
    /// ⌘Z already belong to the system's Edit menu.
    func padKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        keyboardShortcut(key, modifiers: modifiers)
        #endif
    }

    /// Mac: the tabs sit in the title bar, which stays above full-window
    /// covers such as the editor, so they hide while one is up. (On iPhone and
    /// iPad the cover already hides the tab bar.)
    @ViewBuilder
    func hidesMacTabs(_ hidden: Bool) -> some View {
        #if targetEnvironment(macCatalyst)
        toolbar(hidden ? .hidden : .automatic, for: .tabBar)
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
                .background(Palette.accent, in: Capsule())
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
