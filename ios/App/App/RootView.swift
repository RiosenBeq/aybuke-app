import SwiftUI
import PhotosUI
import StoreKit
import AppCore

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.requestReview) private var requestReview
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
                if Platform.isMac {
                    MacShellView()
                } else {
                    MainTabView()
                }
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
        .fullScreenCover(item: $app.editorLaunch, onDismiss: { app.editorDidClose() }) { launch in
            EditorView(launch: launch)
                .environment(app)
        }
        .fullScreenCover(item: $app.videoSource, onDismiss: { app.presentationEnded() }) { source in
            VideoEditorView(source: source)
                .environment(app)
        }
        .retroCamCover()
        .fullScreenCover(isPresented: $app.isCollagePresented, onDismiss: { app.presentationEnded() }) {
            CollageView()
                .environment(app)
        }
        .overlay {
            if app.tour.isRunning {
                TourOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.tour.isRunning)
        .modifier(AppPresentations(isActive: !app.isFullScreenCoverPresented))
        .onOpenURL { url in
            if let link = GlowDeepLink(url: url) { app.handle(link) }
        }
        // At a natural break after a finished save or share (`ReviewPromptPolicy`).
        .onChange(of: app.reviewRequests) { _, _ in requestReview() }
        .tint(Palette.accent)
        .overlay {
            if app.isLaunchSplashVisible {
                LaunchSplashView()
                    .transition(LaunchSplash.exit)
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            HomeView()
                .tabEntrance(app.selectedTab == .home)
                .inviteCardSlot()
                .tabItem { Label("Explore", systemImage: "sparkles") }
                .tag(AppTab.home)
            if app.allowsCloudAI {
                CreateView()
                    .tabEntrance(app.selectedTab == .create)
                    .inviteCardSlot()
                    .tabItem { Label("Create", systemImage: "wand.and.stars") }
                    .tag(AppTab.create)
            }
            EditHubView()
                .tabEntrance(app.selectedTab == .edit)
                .inviteCardSlot()
                .tabItem { Label("Edit", systemImage: "photo.badge.plus") }
                .tag(AppTab.edit)
            LibraryView()
                .tabEntrance(app.selectedTab == .library)
                .inviteCardSlot()
                .tabItem { Label("My Works", systemImage: "square.grid.2x2") }
                .tag(AppTab.library)
        }
        .minimizingTabBar()
        .sheet(isPresented: $app.isSettingsPresented) {
            SettingsView()
                .environment(app)
                .sheetCorners()
        }
        .onChange(of: app.selectedTab) { _, _ in Haptics.selection() }
        .task {
            // Let the first screen settle, then offer the tour once.
            try? await Task.sleep(for: .seconds(0.8))
            app.offerTourIfNeeded()
        }
    }
}
