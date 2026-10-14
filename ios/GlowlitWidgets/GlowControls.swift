import AppIntents
import SwiftUI
import WidgetKit
import AppCore

// Controls for Control Center, the Lock Screen and the Action button
// (iOS 18). Each opens the app right where it's needed, through the same
// `glowlit://` routes as the app's Siri and Shortcuts intents (those live in
// the app target, which a control can't run). The Mac build only gets them
// with the Xcode 26 SDK, which declares controls for Mac Catalyst.
#if !targetEnvironment(macCatalyst) || compiler(>=6.2)

@available(iOS 18.0, *)
struct MagicEditControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.glowlit.ios.control.magic-edit") {
            // Under 13 (her age band, shared by the app) no cloud AI: the
            // free Cut out instead. The app reloads controls when it changes.
            let cloud = GlowSharedStore.load()?.showsCloudAI ?? true
            ControlWidgetButton(action: OpenURLIntent((cloud ? GlowDeepLink.magicEdit : .removeBackground).url)) {
                Label(cloud ? LocalizedStringKey("Magic Edit") : LocalizedStringKey("Cut out"),
                      systemImage: cloud ? "wand.and.stars" : "scissors")
            }
        }
        .displayName("Magic Edit")
        .description("Pick a photo and say what to change.")
    }
}

@available(iOS 18.0, *)
struct EffectsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.glowlit.ios.control.effects") {
            ControlWidgetButton(action: OpenURLIntent(GlowDeepLink.effects.url)) {
                Label("Effects", systemImage: "camera.filters")
            }
        }
        .displayName("Retro effects")
        .description("Give a photo an 80s or 90s look. Free.")
    }
}

@available(iOS 18.0, *)
struct VideoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.glowlit.ios.control.video") {
            ControlWidgetButton(action: OpenURLIntent(GlowDeepLink.video.url)) {
                Label("Video", systemImage: "video.fill")
            }
        }
        .displayName("Edit a video")
        .description("Cut the silences and add retro effects. Free.")
    }
}

@available(iOS 18.0, *)
struct RetroCamControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.glowlit.ios.control.retro-cam") {
            ControlWidgetButton(action: OpenURLIntent(GlowDeepLink.retroCam.url)) {
                Label("Retro Cam", systemImage: "camera.fill")
            }
        }
        .displayName("Retro Cam")
        .description("Shoot with live 80s, 90s and Y2K effects. Free.")
    }
}

@available(iOS 18.0, *)
struct PhotoBoothControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.glowlit.ios.control.photo-booth") {
            ControlWidgetButton(action: OpenURLIntent(GlowDeepLink.photoBooth.url)) {
                Label("Photo Booth", systemImage: "square.grid.2x2.fill")
            }
        }
        .displayName("Photo Booth")
        .description("Four shots with a 3-2-1 countdown. Free.")
    }
}
#endif
