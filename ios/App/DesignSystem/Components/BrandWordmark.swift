import SwiftUI

/// The "aybuke" logotype: the `Wordmark` vector that
/// scripts/render-brand-assets.py draws from Poppins Bold (tightened, corners
/// rounded, the icon's sparkle after the "e"), tinted like text: ink, or light
/// in dark mode. VoiceOver reads the name.
struct BrandWordmark: View {
    var height: CGFloat
    var color: Color = Palette.textPrimary

    var body: some View {
        Image("Wordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(color)
            .accessibilityRemoveTraits(.isImage)
            .accessibilityLabel(Text(verbatim: Brand.name))
    }
}

/// One letter of the wordmark (or, last, its sparkle), from
/// `WordmarkGlyphs`: drawn in the whole wordmark's frame, so the letters of a
/// ZStack line up exactly as in `BrandWordmark` (the same outlines, scaled to
/// fit and centred). The launch splash writes the wordmark on with these.
struct WordmarkGlyph: Shape {
    let index: Int

    static var count: Int { WordmarkGlyphs.letters.count }
    static var sparkleIndex: Int { count - 1 }
    /// Width over height, for a frame that holds the wordmark at its own shape.
    static var aspectRatio: CGFloat { WordmarkGlyphs.size.width / WordmarkGlyphs.size.height }

    /// Parsed once, the first time the wordmark is drawn letter by letter.
    private static let paths: [Path] = WordmarkGlyphs.letters.map(SVGPathData.path)

    /// The centre of a letter in the wordmark's frame, for scaling or turning
    /// it in place.
    static func anchor(of index: Int) -> UnitPoint {
        let box = paths[index].boundingRect
        return UnitPoint(x: box.midX / WordmarkGlyphs.size.width, y: box.midY / WordmarkGlyphs.size.height)
    }

    func path(in rect: CGRect) -> Path {
        let size = WordmarkGlyphs.size
        let scale = min(rect.width / size.width, rect.height / size.height)
        let transform = CGAffineTransform(translationX: rect.midX - size.width * scale / 2,
                                          y: rect.midY - size.height * scale / 2)
            .scaledBy(x: scale, y: scale)
        return Self.paths[index].applying(transform)
    }
}

/// Just enough of an SVG path reader for the generated wordmark data:
/// absolute M, L, Q, C and Z with plain numbers.
private enum SVGPathData {
    static func path(_ data: String) -> Path {
        var path = Path()
        var command: Character = "M"
        var numbers: [CGFloat] = []
        var token = ""

        func flushToken() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }
        func point(_ i: Int) -> CGPoint { CGPoint(x: numbers[i], y: numbers[i + 1]) }
        func run() {
            switch command {
            case "M" where numbers.count >= 2: path.move(to: point(0))
            case "L" where numbers.count >= 2: path.addLine(to: point(0))
            case "Q" where numbers.count >= 4: path.addQuadCurve(to: point(2), control: point(0))
            case "C" where numbers.count >= 6: path.addCurve(to: point(4), control1: point(0), control2: point(2))
            case "Z": path.closeSubpath()
            default: break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        for character in data {
            if character.isLetter {
                flushToken()
                run()
                command = character
            } else if character == " " || character == "," {
                flushToken()
            } else if character == "-", !token.isEmpty {
                flushToken()
                token.append(character)
            } else {
                token.append(character)
            }
        }
        flushToken()
        run()
        return path
    }
}
