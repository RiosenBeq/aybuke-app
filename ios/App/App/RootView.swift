import SwiftUI
import PhotosUI
import AppCore

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var pickerItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?

    var body: some View {
        @Bindable var app = app

        Group {
            if app.hasCompletedOnboarding && app.needsAgeStep {
                // Once, for people who finished onboarding before the age step.
                ZStack {
                    AuroraBackground(intensity: 0.9)
                    AgeStepView(mode: .returning) { app.recordAge($0) }
                        .readableWidth(Metrics.compactWidth, alignment: .center)
                }
            } else if app.hasCompletedOnboarding {
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
        .photosPicker(isPresented: $app.isVideoPickerPresented, selection: $videoItem, matching: .videos)
        .onChange(of: videoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await app.handlePickedVideo(newItem)
                videoItem = nil
            }
        }
        .fullScreenCover(item: $app.editorLaunch) { launch in
            EditorView(launch: launch)
                .environment(app)
        }
        .fullScreenCover(item: $app.videoSource) { source in
            VideoEditorView(source: source)
                .environment(app)
        }
        .overlay {
            if app.tour.isRunning {
                TourOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.tour.isRunning)
        .modifier(AppPresentations(isActive: app.editorLaunch == nil && app.videoSource == nil))
        .onOpenURL { url in
            if let link = GlowDeepLink(url: url) { app.handle(link) }
        }
        .tint(Palette.accent)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let isCovered = app.editorLaunch != nil || app.videoSource != nil

        TabView(selection: $app.selectedTab) {
            HomeView()
                .hidesMacTabs(isCovered)
                .tabItem { Label("Explore", systemImage: "sparkles") }
                .tag(AppTab.home)
            if app.allowsCloudAI {
                CreateView()
                    .hidesMacTabs(isCovered)
                    .tabItem { Label("Create", systemImage: "wand.and.stars") }
                    .tag(AppTab.create)
            }
            EditHubView()
                .hidesMacTabs(isCovered)
                .tabItem { Label("Edit", systemImage: "photo.badge.plus") }
                .tag(AppTab.edit)
            LibraryView()
                .hidesMacTabs(isCovered)
                .tabItem { Label("My Works", systemImage: "square.grid.2x2") }
                .tag(AppTab.library)
        }
        .minimizingTabBar()
        .acceptsDroppedPhotos()
        .sheet(isPresented: $app.isSettingsPresented) {
            SettingsView()
                .environment(app)
        }
        .onChange(of: app.selectedTab) { _, _ in Haptics.selection() }
        .task {
            // Let the first screen settle, then offer the tour once.
            try? await Task.sleep(for: .seconds(0.8))
            app.offerTourIfNeeded()
        }
    }
}
