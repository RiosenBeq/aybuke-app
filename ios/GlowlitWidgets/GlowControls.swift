import AppIntents
import SwiftUI
import WidgetKit
import AppCore

// Controls for Control Center, the Lock Screen and the Action button
// (iOS 18). Each opens the app right where it's needed.

@available(iOS 18.0, *)
struct MagicEditControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.glowlit.ios.control.magic-edit") {
            ControlWidgetButton(action: OpenURLIntent(GlowDeepLink.magicEdit.url)) {
                Label("Magic Edit", systemImage: "wand.and.stars")
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
