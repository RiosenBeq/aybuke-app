import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen widgets, the generation Live Activity
/// (Dynamic Island) and Control Center controls (iOS 18). Data comes from the
/// App Group the app writes to (`GlowSharedStore` in AppCore).
@main
struct GlowlitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TrendWidget()
        GlowWidget()
        GlowLiveActivity()
        if #available(iOS 18.0, *) {
            MagicEditControl()
            EffectsControl()
            VideoControl()
        }
    }
}
