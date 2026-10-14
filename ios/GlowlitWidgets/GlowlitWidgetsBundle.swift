import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen widgets, the generation Live Activity
/// (Dynamic Island, not on the Mac) and Control Center controls (iOS 18).
/// Data comes from the App Group the app writes to (`GlowSharedStore` in AppCore).
@main
struct GlowlitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TrendWidget()
        GlowWidget()
        #if !targetEnvironment(macCatalyst)
        GlowLiveActivity()
        #endif
        #if !targetEnvironment(macCatalyst) || compiler(>=6.2)
        if #available(iOS 18.0, *) {
            MagicEditControl()
            EffectsControl()
            VideoControl()
            RetroCamControl()
            PhotoBoothControl()
        }
        #endif
    }
}
