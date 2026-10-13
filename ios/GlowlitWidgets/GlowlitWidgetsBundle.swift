import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen widgets plus the generation Live Activity
/// (Dynamic Island). Data comes from the App Group the app writes to
/// (`GlowSharedStore` in AppCore).
@main
struct GlowlitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TrendWidget()
        GlowWidget()
        GlowLiveActivity()
    }
}
