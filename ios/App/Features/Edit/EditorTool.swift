import Foundation
import AppCore

enum EditorTool: String, CaseIterable, Identifiable {
    case magicEdit
    case makeup
    case styles
    case effects
    case textStickers
    case enhance
    case removeBackground
    case erase
    case adjust
    case crop
    case hideFaces

    var id: String { rawValue }

    var title: String {
        switch self {
        case .magicEdit: return String(localized: "Magic Edit")
        case .makeup: return String(localized: "Makeup Studio")
        case .styles: return String(localized: "Styles")
        case .effects: return String(localized: "Effects")
        case .textStickers: return String(localized: "Text & Stickers")
        case .enhance: return String(localized: "Enhance")
        case .removeBackground: return String(localized: "Remove BG")
        case .erase: return String(localized: "Erase")
        case .adjust: return String(localized: "Adjust")
        case .crop: return String(localized: "Crop")
        case .hideFaces: return String(localized: "Hide faces")
        }
    }

    /// One word for the editor's bottom bar.
    var shortTitle: String {
        switch self {
        case .magicEdit: return String(localized: "Magic")
        case .makeup: return String(localized: "Makeup", comment: "Bottom bar name of the Makeup Studio tool")
        case .styles: return String(localized: "Styles")
        case .effects: return String(localized: "Effects")
        case .textStickers: return String(localized: "Stickers", comment: "Bottom bar name of the Text & Stickers tool")
        case .enhance: return String(localized: "Enhance")
        case .removeBackground: return String(localized: "Cut out")
        case .erase: return String(localized: "Erase")
        case .adjust: return String(localized: "Adjust")
        case .crop: return String(localized: "Crop")
        case .hideFaces: return String(localized: "Hide", comment: "Bottom bar name of the Hide faces tool")
        }
    }

    var caption: String {
        switch self {
        case .magicEdit: return String(localized: "Describe a change")
        case .makeup: return String(localized: "Lips, eyes & blush")
        case .styles: return Platform.isMac ? String(localized: "One-click looks") : String(localized: "One-tap looks")
        case .effects: return String(localized: "80s · Y2K · 2010s")
        case .textStickers: return String(localized: "Text, stickers, doodles")
        case .enhance: return String(localized: "Fix, sharpen & restore", comment: "Caption of the Enhance tool: a free quick fix plus AI unblur, old-photo restore, low light and HD")
        case .removeBackground: return String(localized: "Free · on-device")
        case .erase: return String(localized: "Brush to remove")
        case .adjust: return String(localized: "Light & color")
        case .crop: return String(localized: "Fit & straighten")
        case .hideFaces: return String(localized: "Protect friends")
        }
    }

    var symbolName: String {
        switch self {
        case .makeup: return "paintbrush.pointed"
        case .adjust: return "slider.horizontal.3"
        case .effects: return "camera.filters"
        case .textStickers: return "face.smiling"
        case .crop: return "crop.rotate"
        case .hideFaces: return "person.2.slash"
        default: return operation?.symbolName ?? "wand.and.stars"
        }
    }

    /// Makeup Studio runs as a Magic Edit: same gates, guard, credits and retry.
    var operation: AIOperation? {
        switch self {
        case .magicEdit, .makeup: return .magicEdit
        case .styles: return .restyle
        case .enhance: return .enhance
        case .removeBackground: return .removeBackground
        case .erase: return .eraseObject
        case .adjust, .effects, .textStickers, .crop, .hideFaces: return nil
        }
    }

    /// Only works with cloud AI (consent and credits), so it's hidden under
    /// 13. Enhance isn't: its Quick fix is free and on the device, and its
    /// AI fixes show only where cloud AI is allowed.
    var usesCloudAI: Bool {
        if self == .enhance { return false }
        return operation.map { !$0.runsOnDevice } ?? false
    }

    /// The tools offered: the free on-device ones only, when cloud AI isn't.
    static func available(cloudAI: Bool) -> [EditorTool] {
        allCases.filter { cloudAI || !$0.usesCloudAI }
    }

    /// Tools surfaced on the home screen (Magic Edit has its own hero card).
    static let quickTools: [EditorTool] = [.makeup, .effects, .enhance, .removeBackground, .erase, .styles, .adjust]
}
