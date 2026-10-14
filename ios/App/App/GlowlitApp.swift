import SwiftUI
import SwiftData

@main
struct GlowlitApp: App {
    @State private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    init() {
        FontRegistrar.registerBundledFonts()
        let (container, outcome) = LibraryStore.open()
        self.container = container
        let app = AppModel(container: container)
        app.libraryOutcome = outcome
        _app = State(initialValue: app)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.appearance.colorScheme)
                .task { await app.start() }
                #if targetEnvironment(macCatalyst)
                // One window on the Mac: links from widgets and notifications
                // go to the open window instead of opening another one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .background { MacWindowSetup() }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.becameActive() }
        }
        .modelContainer(container)
        #if targetEnvironment(macCatalyst)
        .commands { GlowlitCommands(app: app) }
        #endif
    }
}
