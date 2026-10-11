import SwiftUI
import PhotosUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        @Bindable var app = app

        Group {
            if app.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .photosPicker(isPresented: $app.isPhotoPickerPresented, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await app.handlePickedPhoto(newItem)
                pickerItem = nil
            }
        }
        .fullScreenCover(item: $app.editorLaunch) { launch in
            EditorView(launch: launch)
                .environment(app)
        }
        .modifier(AppPresentations(isActive: app.editorLaunch == nil))
        .tint(Palette.primary)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        TabView(selection: $app.selectedTab) {
            HomeView()
                .tabItem { Label("Explore", systemImage: "sparkles") }
                .tag(AppTab.home)
            CreateView()
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
                .tag(AppTab.create)
            EditHubView()
                .tabItem { Label("Edit", systemImage: "photo.badge.plus") }
                .tag(AppTab.edit)
            LibraryView()
                .tabItem { Label("My Works", systemImage: "square.grid.2x2") }
                .tag(AppTab.library)
        }
        .onChange(of: app.selectedTab) { _, _ in Haptics.selection() }
    }
}
