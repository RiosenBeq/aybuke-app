import SwiftUI
import UIKit
import CoreText

/// Display typeface: Poppins (SIL Open Font License 1.1), a geometric sans
/// with round, friendly forms, the same face as the website. Medium,
/// SemiBold, Bold and ExtraBold are bundled. Body text uses SF Pro so it
/// inherits Dynamic Type and Apple's legibility tuning.
enum BrandFont {
    static let familyName = "Poppins"

    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy: return "Poppins-ExtraBold"
        case .bold: return "Poppins-Bold"
        case .medium, .regular, .light, .thin, .ultraLight: return "Poppins-Medium"
        default: return "Poppins-SemiBold"
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

    /// Editorial accent: Apple's New York serif in italic — the one soft,
    /// elegant word in a headline ("Make it *glow*"). Scales with Dynamic Type.
    static func accent(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        let scaled = UIFontMetrics(forTextStyle: style.uiTextStyle).scaledValue(for: size)
        return .system(size: scaled, weight: .medium, design: .serif).italic()
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

extension Text {
    /// Display headline where words wrapped in `*asterisks*` are set in the
    /// italic serif accent: `Text(styled: "Your photos, in their *best light*", size: 34)`.
    init(styled source: LocalizedStringResource, size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .largeTitle) {
        self.init(styled: String(localized: source), size: size, weight: weight, relativeTo: style)
    }

    /// For text that's already localized.
    @_disfavoredOverload
    init(styled source: String, size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .largeTitle) {
        let parts = source.components(separatedBy: "*")
        var text = Text(verbatim: "")
        for (index, part) in parts.enumerated() where !part.isEmpty {
            let isAccent = !index.isMultiple(of: 2)
            let piece = Text(verbatim: part).font(isAccent
                ? .accent(size * 1.06, relativeTo: style)
                : .display(size, weight: weight, relativeTo: style))
            text = Text("\(text)\(piece)")
        }
        self = text
    }
}
