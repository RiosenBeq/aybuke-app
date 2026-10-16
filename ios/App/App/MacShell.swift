import SwiftUI
import AppCore

// The Mac app's window: a sidebar with the four sections, the quick tools,
// the credit balance and Settings, next to the selected section. iPhone and
// iPad keep `MainTabView`. Compiled for iOS too, so `-exportLocalizations`
// extracts its strings (see `Platform`).

struct MacShellView: View {
    @Environment(AppModel.self) private var app
    @State private var createModel = CreateViewModel()

    var body: some View {
        @Bindable var app = app

        NavigationSplitView(columnVisibility: $app.macSidebarVisibility) {
            MacSidebar()
                // One toggle of our own instead: the system's lives in a
                // navigation bar, which most sections hide.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            // Each section's own toolbar would otherwise bring a second toggle.
            MacSections(createModel: createModel)
                .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .topLeading) {
            sidebarToggle
        }
        .acceptsDroppedPhotos()
        .sheet(isPresented: $app.isSettingsPresented) {
            SettingsView()
                .environment(app)
                .macSheet(.form)
        }
        .task {
            // Let the first screen settle, then offer the tour once.
            try? await Task.sleep(for: .seconds(0.8))
            app.offerTourIfNeeded()
        }
    }
}

private extension MacShellView {
    /// Beside the window's close, minimize and zoom buttons, where the Mac's
    /// own apps keep it, whether the sidebar shows or not.
    var sidebarToggle: some View {
        let isHidden = app.macSidebarVisibility == .detailOnly
        return Button {
            app.toggleMacSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!app.acceptsCommands)
        .accessibilityLabel(isHidden ? "Show Sidebar" : "Hide Sidebar")
        .help(isHidden ? "Show Sidebar" : "Hide Sidebar")
        .padding(.leading, 104)
        .padding(.top, 8)
        .ignoresSafeArea()
    }
}

/// The selected section. A switch rather than a TabView: a TabView in the
/// split view's detail hides the sections' own navigation bars on the Mac.
/// Create's state (her draft, a running job, its results) lives in the shell,
/// so it's still there when she comes back.
private struct MacSections: View {
    let createModel: CreateViewModel
    @Environment(AppModel.self) private var app

    var body: some View {
        let covered = app.isFullScreenCoverPresented
        // Each section is built anew when picked, so it fades up as it appears.
        switch app.selectedTab {
        case .home: HomeView().hidesMacToolbar(covered).sectionEntrance().inviteCardSlot()
        case .create: CreateView(model: createModel).hidesMacToolbar(covered).sectionEntrance().inviteCardSlot()
        case .edit: EditHubView().hidesMacToolbar(covered).sectionEntrance().inviteCardSlot()
        case .library: LibraryView().hidesMacToolbar(covered).sectionEntrance().inviteCardSlot()
        }
    }
}

// MARK: - Sidebar

private struct MacSidebar: View {
    @Environment(AppModel.self) private var app
    @State private var showsCredits = false
    @AppStorage("mac.sidebar.toolsExpanded") private var toolsExpanded = true

    var body: some View {
        List(selection: selection) {
            Section {
                row("Explore", systemImage: "sparkles", tab: .home)
                if app.allowsCloudAI {
                    row("Create", systemImage: "wand.and.stars", tab: .create)
                }
                row("Edit", systemImage: "photo.badge.plus", tab: .edit)
                row("My Works", systemImage: "square.grid.2x2", tab: .library)
            }
            Section("Tools", isExpanded: $toolsExpanded) {
                ForEach(MacTool.available(for: app), id: \.self) { tool in
                    Button {
                        tool.open(in: app)
                    } label: {
                        Label(tool.title, systemImage: tool.symbolName)
                    }
                    .buttonStyle(.plain)
                    .help(tool.help)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .sheet(isPresented: $showsCredits) {
            CreditsSheet()
                .environment(app)
                .macSheet(.form)
                .presentationBackground(Palette.background)
        }
    }

    private var selection: Binding<AppTab?> {
        Binding(get: { app.selectedTab }, set: { if let tab = $0 { app.selectedTab = tab } })
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, tab: AppTab) -> some View {
        Label(title, systemImage: systemImage)
            .tag(tab)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if app.allowsCloudAI {
                Button {
                    showsCredits = true
                } label: {
                    Label("\(app.credits.balance) credits left", systemImage: app.purchases.isPro ? "crown.fill" : "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(app.credits.balance)))
                }
                .buttonStyle(.plain)
                .help("Shows your credits and how they work")
                .tourAnchor(.credits)
            }
            Spacer(minLength: 0)
            Button {
                app.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .help("Settings")
            .tourAnchor(.settings)
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// The quick tools in the sidebar: the same ones, in the same order, as
/// Explore's Quick tools row.
enum MacTool: Hashable {
    case retroCam, editor(EditorTool), collage, video, bestShot

    @MainActor
    static func available(for app: AppModel) -> [MacTool] {
        var tools: [MacTool] = []
        if RetroCam.isAvailable { tools.append(.retroCam) }
        tools += EditorTool.quickTools.filter { app.allowsCloudAI || !$0.usesCloudAI }.map(MacTool.editor)
        tools += [.collage, .video, .bestShot]
        return tools
    }

    var title: LocalizedStringKey {
        switch self {
        case .retroCam: return "Retro Cam"
        case .editor(let tool): return LocalizedStringKey(tool.title)
        case .collage: return "Collage"
        case .video: return "Video"
        case .bestShot: return "Best shot"
        }
    }

    var help: LocalizedStringKey {
        switch self {
        case .retroCam: return "Live effects · booth"
        case .editor(let tool): return LocalizedStringKey(tool.caption)
        case .collage: return "Photo dump · carousel"
        case .video: return "Cut silences · effects"
        case .bestShot: return "Free · sorts by light"
        }
    }

    var symbolName: String {
        switch self {
        case .retroCam: return "camera"
        case .editor(let tool): return tool.symbolName
        case .collage: return "rectangle.3.offgrid"
        case .video: return "video"
        case .bestShot: return "photo.stack"
        }
    }

    @MainActor
    func open(in app: AppModel) {
        guard app.acceptsCommands else { return }
        switch self {
        case .retroCam: app.isRetroCamPresented = true
        case .editor(let tool): app.startEditing(tool: tool)
        case .collage: app.isCollagePresented = true
        case .video: app.isVideoPickerPresented = true
        case .bestShot: app.isBestShotPresented = true
        }
    }
}
