import Foundation
import AppCore

enum EditorTool: String, CaseIterable, Identifiable {
    case magicEdit
    case styles
    case enhance
    case removeBackground
    case erase
    case adjust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .magicEdit: return "Magic Edit"
        case .styles: return "Styles"
        case .enhance: return "Enhance"
        case .removeBackground: return "Remove BG"
        case .erase: return "Erase"
        case .adjust: return "Adjust"
        }
    }

    var caption: String {
        switch self {
        case .magicEdit: return "Describe a change"
        case .styles: return "One-tap looks"
        case .enhance: return "Sharpen & restore"
        case .removeBackground: return "Free · on-device"
        case .erase: return "Brush to remove"
        case .adjust: return "Light & color"
        }
    }

    var symbolName: String {
        switch self {
        case .adjust: return "slider.horizontal.3"
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
        case .adjust: return nil
        }
    }

    /// Tools surfaced on the home screen (Magic Edit has its own hero card).
    static let quickTools: [EditorTool] = [.enhance, .removeBackground, .erase, .styles, .adjust]
}
