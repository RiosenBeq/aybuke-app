import SwiftUI
import UIKit
import CoreText

/// Display typeface: Bricolage Grotesque (SIL Open Font License 1.1), bundled
/// as static cuts generated from the variable font — display optical size
/// (opsz 96) for headlines, text optical size (opsz 24) for small titles.
/// Body text uses SF Pro so it inherits Dynamic Type and Apple's legibility tuning.
enum BrandFont {
    static let familyName = "Bricolage Grotesque"

    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy: return "BricolageGrotesque-DisplayExtraBold"
        case .bold: return "BricolageGrotesque-DisplayBold"
        default: return "BricolageGrotesque-TextSemiBold"
        }
    }
}

enum FontRegistrar {
    /// Registers every font file shipped in the bundle. Call once at launch,
    /// before any view renders.
    static func registerBundledFonts(bundle: Bundle = .main) {
        let urls = ["ttf", "otf"].flatMap { bundle.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Evaluated lazily on first use, i.e. after `registerBundledFonts()`.
    static let isDisplayFontAvailable: Bool = UIFont(name: BrandFont.postScriptName(for: .bold), size: 12) != nil
}

extension Font {
    /// Brand display font that scales with Dynamic Type; falls back to SF Pro
    /// Rounded if the bundled font is missing.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title) -> Font {
        if FontRegistrar.isDisplayFontAvailable {
            return .custom(BrandFont.postScriptName(for: weight), size: size, relativeTo: style)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    static var heroTitle: Font { .display(34, weight: .bold, relativeTo: .largeTitle) }
    static var screenTitle: Font { .display(28, weight: .bold, relativeTo: .largeTitle) }
    static var sectionTitle: Font { .display(20, weight: .semibold, relativeTo: .title3) }
    static var cardTitle: Font { .display(17, weight: .semibold, relativeTo: .headline) }
    static var buttonLabel: Font { .display(17, weight: .semibold, relativeTo: .headline) }
}
