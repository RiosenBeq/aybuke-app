import SwiftUI
import SwiftData

@main
struct GlowlitApp: App {
    @State private var app: AppModel
    private let container: ModelContainer

    init() {
        FontRegistrar.registerBundledFonts()
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Creation.self)
        } catch {
            fatalError("Couldn't open the library database: \(error)")
        }
        self.container = container
        _app = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .task { await app.start() }
        }
        .modelContainer(container)
    }
}
