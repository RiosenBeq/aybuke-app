import Foundation
import AppCore

enum EditorTool: String, CaseIterable, Identifiable {
    case magicEdit
    case styles
    case effects
    case enhance
    case removeBackground
    case erase
    case adjust
    case crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .magicEdit: return String(localized: "Magic Edit")
        case .styles: return String(localized: "Styles")
        case .effects: return String(localized: "Effects")
        case .enhance: return String(localized: "Enhance")
        case .removeBackground: return String(localized: "Remove BG")
        case .erase: return String(localized: "Erase")
        case .adjust: return String(localized: "Adjust")
        case .crop: return String(localized: "Crop")
        }
    }

    /// One word for the editor's bottom bar.
    var shortTitle: String {
        switch self {
        case .magicEdit: return String(localized: "Magic")
        case .styles: return String(localized: "Styles")
        case .effects: return String(localized: "Effects")
        case .enhance: return String(localized: "Enhance")
        case .removeBackground: return String(localized: "Cut out")
        case .erase: return String(localized: "Erase")
        case .adjust: return String(localized: "Adjust")
        case .crop: return String(localized: "Crop")
        }
    }

    var caption: String {
        switch self {
        case .magicEdit: return String(localized: "Describe a change")
        case .styles: return String(localized: "One-tap looks")
        case .effects: return String(localized: "80s · Y2K · 2010s")
        case .enhance: return String(localized: "Sharpen & restore")
        case .removeBackground: return String(localized: "Free · on-device")
        case .erase: return String(localized: "Brush to remove")
        case .adjust: return String(localized: "Light & color")
        case .crop: return String(localized: "Fit & straighten")
        }
    }

    var symbolName: String {
        switch self {
        case .adjust: return "slider.horizontal.3"
        case .effects: return "camera.filters"
        case .crop: return "crop.rotate"
        default: return operation?.symbolName ?? "wand.and.stars"
        }
    }

    var operation: AIOperation? {
        switch self {
        case .magicEdit: return .magicEdit
        case .styles: return .restyle
        case .enhance: return .enhance
        case .removeBackground: return .removeBackground
        case .erase: return .eraseObject
        case .adjust, .effects, .crop: return nil
        }
    }

    /// Tools surfaced on the home screen (Magic Edit has its own hero card).
    static let quickTools: [EditorTool] = [.effects, .enhance, .removeBackground, .erase, .styles, .adjust]
}
