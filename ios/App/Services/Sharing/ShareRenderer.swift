import UIKit
import AppCore

/// What the user is sharing. `original` enables the Before / After collage.
struct SharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    var original: UIImage?
    let operation: AIOperation?
    var prompt: String?

    /// Prompts are only offered on the card for text-to-image creations;
    /// edit instructions can be personal.
    var shareablePrompt: String? {
        guard operation == .textToImage, let prompt = prompt.map(PromptBuilder.sanitize), !prompt.isEmpty else { return nil }
        return prompt
    }
}

enum ShareFormat: String, CaseIterable, Identifiable {
    case photo
    case beforeAfter
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "Photo"
        case .beforeAfter: return "Before / After"
        case .story: return "Story card"
        }
    }

    var symbolName: String {
        switch self {
        case .photo: return "photo"
        case .beforeAfter: return "square.split.2x1"
        case .story: return "rectangle.portrait"
        }
    }
}

/// Renders share formats. Free exports carry Glowlit branding (the corner
/// watermark, or a "Made with Glowlit" line on collages and cards); Pro
/// removes it everywhere. Pure functions, safe off the main thread.
enum ShareRenderer {
    static func render(_ payload: SharePayload, format: ShareFormat, branded: Bool, showPrompt: Bool) -> UIImage {
        let image = ImageUtilities.normalized(payload.image, maxLongEdge: 2048)
        switch format {
        case .photo:
            return branded ? Watermark.apply(to: image) : image
        case .beforeAfter:
            guard let original = payload.original else { return branded ? Watermark.apply(to: image) : image }
            return beforeAfter(before: ImageUtilities.normalized(original, maxLongEdge: 2048), after: image, branded: branded)
        case .story:
            return storyCard(image, prompt: showPrompt ? payload.shareablePrompt : nil, branded: branded)
        }
    }

    // MARK: Before / After

    static func beforeAfter(before: UIImage, after: UIImage, branded: Bool) -> UIImage {
        let landscape = after.size.width > after.size.height
        let unit: CGFloat = 1400
        let afterSize = scaled(after.size, toFit: landscape ? CGSize(width: unit, height: .greatestFiniteMagnitude) : CGSize(width: .greatestFiniteMagnitude, height: unit))
        let beforeSize = landscape
            ? scaled(before.size, toFit: CGSize(width: afterSize.width, height: .greatestFiniteMagnitude))
            : scaled(before.size, toFit: CGSize(width: .greatestFiniteMagnitude, height: afterSize.height))
        let padding = unit * 0.05
        let gap = unit * 0.025
        let footer = branded ? unit * 0.1 : 0
        let canvas = landscape
            ? CGSize(width: padding * 2 + afterSize.width, height: padding * 2 + beforeSize.height + gap + afterSize.height + footer)
            : CGSize(width: padding * 2 + beforeSize.width + gap + afterSize.width, height: padding * 2 + afterSize.height + footer)

        return renderer(canvas, opaque: true).image { context in
            UIColor.brandPetal.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            let beforeRect = CGRect(origin: CGPoint(x: padding, y: padding), size: beforeSize)
            let afterRect = landscape
                ? CGRect(origin: CGPoint(x: padding, y: beforeRect.maxY + gap), size: afterSize)
                : CGRect(origin: CGPoint(x: beforeRect.maxX + gap, y: padding), size: afterSize)
            let radius = unit * 0.035
            for (image, rect, label) in [(before, beforeRect, "BEFORE"), (after, afterRect, "AFTER")] {
                drawRounded(image, in: rect, radius: radius, context: context.cgContext)
                drawTag(label, at: CGPoint(x: rect.minX + unit * 0.02, y: rect.minY + unit * 0.02), size: unit * 0.026, highlighted: label == "AFTER")
            }
            if branded {
                drawText("Made with \(Brand.name) ✦", font: brandFont(unit * 0.034), color: .brandInk,
                         centeredIn: CGRect(x: 0, y: canvas.height - padding - footer * 0.85, width: canvas.width, height: footer))
            }
        }
    }

    // MARK: Story card (9:16)

    static let storySize = CGSize(width: 1080, height: 1920)

    static func storyCard(_ image: UIImage, prompt: String?, branded: Bool) -> UIImage {
        let canvas = storySize
        return renderer(canvas, opaque: true).image { context in
            let cg = context.cgContext
            UIColor.brandBlush.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            radialGlow(cg, center: CGPoint(x: 160, y: 260), radius: 760, color: .white, alpha: 0.75)
            radialGlow(cg, center: CGPoint(x: 980, y: 1700), radius: 700, color: .brandPetal, alpha: 0.9)

            // Instagram keeps ~250 px at the top and bottom for its own UI.
            let promptHeight: CGFloat = prompt == nil ? 0 : 190
            let maxImage = CGSize(width: canvas.width - 220, height: canvas.height - 620 - promptHeight)
            let imageSize = scaled(image.size, toFit: maxImage)
            let frame = CGRect(
                x: (canvas.width - imageSize.width) / 2,
                y: 300 + (maxImage.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )

            cg.saveGState()
            cg.translateBy(x: frame.midX, y: frame.midY)
            cg.rotate(by: -2 * .pi / 180)
            cg.translateBy(x: -frame.midX, y: -frame.midY)
            let border = frame.insetBy(dx: -18, dy: -18)
            cg.setShadow(offset: CGSize(width: 0, height: 24), blur: 48, color: UIColor.brandInk.withAlphaComponent(0.22).cgColor)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: border, cornerRadius: 52).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            drawRounded(image, in: frame, radius: 36, context: cg)
            cg.restoreGState()

            if let prompt {
                let text = "“\(String(prompt.prefix(110)))\(prompt.count > 110 ? "…" : "")”"
                drawText(text, font: brandFont(40, weight: .semibold), color: .brandInk,
                         centeredIn: CGRect(x: 120, y: frame.maxY + 70, width: canvas.width - 240, height: promptHeight - 20), lines: 3)
            }
            if branded {
                drawText(Brand.name, font: brandFont(64, weight: .heavy), color: .brandInk,
                         centeredIn: CGRect(x: 0, y: 150, width: canvas.width, height: 90))
                drawText("Made with \(Brand.name) ✦  ·  \(Brand.tagline)", font: brandFont(34, weight: .semibold), color: .brandInk,
                         centeredIn: CGRect(x: 0, y: canvas.height - 300, width: canvas.width, height: 60))
            }
        }
    }

    // MARK: Drawing helpers

    private static func renderer(_ size: CGSize, opaque: Bool) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    static func scaled(_ size: CGSize, toFit bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private static func drawRounded(_ image: UIImage, in rect: CGRect, radius: CGFloat, context: CGContext) {
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
        image.draw(in: rect)
        context.restoreGState()
    }

    private static func drawTag(_ text: String, at origin: CGPoint, size: CGFloat, highlighted: Bool) {
        let font = UIFont.systemFont(ofSize: size, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: highlighted ? UIColor.brandInk : UIColor.white,
            .kern: size * 0.08,
        ]
        let label = text as NSString
        let textSize = label.size(withAttributes: attributes)
        let rect = CGRect(x: origin.x, y: origin.y, width: textSize.width + size * 1.2, height: textSize.height + size * 0.6)
        (highlighted ? UIColor.brandBlush : UIColor.brandInk.withAlphaComponent(0.75)).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
        label.draw(at: CGPoint(x: rect.minX + size * 0.6, y: rect.minY + size * 0.3), withAttributes: attributes)
    }

    private static func drawText(_ text: String, font: UIFont, color: UIColor, centeredIn rect: CGRect, lines: Int = 1) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let height = min(rect.height, ceil(bounds.height))
        string.draw(with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], context: nil)
    }

    private static func radialGlow(_ context: CGContext, center: CGPoint, radius: CGFloat, color: UIColor, alpha: CGFloat) {
        let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    static func brandFont(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        let name: String
        switch weight {
        case .heavy, .black: name = BrandFont.postScriptName(for: .heavy)
        case .bold: name = BrandFont.postScriptName(for: .bold)
        default: name = BrandFont.postScriptName(for: .semibold)
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

/// Default caption with hashtags and a link people can tap.
enum ShareCaption {
    static func make(for payload: SharePayload, hashtags: [String], link: URL?) -> String {
        var lines: [String] = []
        if let prompt = payload.shareablePrompt {
            lines.append("“\(prompt)”")
        }
        lines.append("Made with \(Brand.name) ✦ \(Brand.tagline)")
        if let link {
            lines.append(link.absoluteString)
        }
        let tags = hashtags
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .filter { !$0.isEmpty }
            .map { "#\($0)" }
        if !tags.isEmpty {
            lines.append(tags.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}
