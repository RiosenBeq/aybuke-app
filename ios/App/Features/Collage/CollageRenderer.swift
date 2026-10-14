import SwiftUI
import UIKit
import Photos
import CoreImage
import AppCore

/// Everything about a collage apart from its photos.
struct CollageDesign: Equatable {
    var style: CollageStyle = .grid
    var variant = 0
    var format: CollageFormat = .portrait
    /// 0…1: gaps between photos and the margin around them.
    var spacing = 0.35
    /// 0…1: how round the corners are.
    var corners = 0.2
    var background: CollageBackground = .blush
    var showsCaption = false
    var caption = ""

    static let captionLimit = 40
}

/// Brand swatches, aura gradients, or a soft blur of the first photo.
enum CollageBackground: String, CaseIterable, Identifiable {
    case blush, petal, paper, ink, bubblegum, lilac, sunset, mint, butter, nightGlam, photo

    var id: String { rawValue }

    /// One colour, or an aura gradient from the top-left corner to the
    /// bottom-right one. The blurred photo shows petal until it's ready.
    var colors: [Color] {
        switch self {
        case .blush: return [Palette.blush]
        case .petal, .photo: return [Palette.petal]
        case .paper: return [Palette.paper]
        case .ink: return [Palette.ink]
        case .bubblegum: return AuraPalette.bubblegum.colors
        case .lilac: return AuraPalette.lilac.colors
        case .sunset: return AuraPalette.sunset.colors
        case .mint: return AuraPalette.mint.colors
        case .butter: return AuraPalette.butter.colors
        case .nightGlam: return AuraPalette.nightGlam.colors
        }
    }

    /// The date and caption turn white on these.
    var isDark: Bool { self == .ink || self == .nightGlam }

    var title: String {
        switch self {
        case .blush: return String(localized: "Blush")
        case .petal: return String(localized: "Petal")
        case .paper: return String(localized: "Paper")
        case .ink: return String(localized: "Ink")
        case .bubblegum: return String(localized: "Bubblegum")
        case .lilac: return String(localized: "Lilac")
        case .sunset: return String(localized: "Sunset")
        case .mint: return String(localized: "Mint")
        case .butter: return String(localized: "Butter")
        case .nightGlam: return String(localized: "Night")
        case .photo: return String(localized: "Blurred photo")
        }
    }
}

// MARK: - Shared art

/// Pieces both the live canvas and the export draw, so they match.
enum CollageArt {
    /// The white veil over the blurred photo background.
    static let backdropVeil: CGFloat = 0.22
    static let captionFontName = "Courier-Bold"

    static func pixels(_ rect: CollageRect, in canvas: CGSize) -> CGRect {
        CGRect(x: rect.x * canvas.width, y: rect.y * canvas.height, width: rect.width * canvas.width, height: rect.height * canvas.height)
    }

    /// Where the photo goes inside `window` for its pan and zoom.
    static func photoFrame(_ crop: CollageCrop, imageSize: CGSize, window: CGRect) -> CGRect {
        guard imageSize.height > 0, window.height > 0 else { return window }
        let rect = crop.photoRect(photoAspect: imageSize.width / imageSize.height, windowAspect: window.width / window.height)
        return CGRect(x: window.minX + rect.x * window.width, y: window.minY + rect.y * window.height,
                      width: rect.width * window.width, height: rect.height * window.height)
    }

    /// A film strip with its sprocket holes cut out (fill with even-odd).
    static func stripPath(_ strip: CollageStrip, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addRect(rect)
        for hole in strip.holes {
            let box = CGRect(x: rect.minX + hole.x * rect.width, y: rect.minY + hole.y * rect.height,
                             width: hole.width * rect.width, height: hole.height * rect.height)
            let radius = min(box.width, box.height) * 0.3
            path.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
        }
        return path
    }

    static func tapeColor(_ tone: Int) -> UIColor {
        let tones: [UIColor] = [.auraPink, .auraMint, .auraButter, .auraLilac]
        return tones[((tone % tones.count) + tones.count) % tones.count].withAlphaComponent(0.72)
    }

    static func sticker(_ index: Int) -> (symbol: String, color: UIColor) {
        let stickers: [(String, UIColor)] = [
            ("heart.fill", .auraPink), ("sparkle", .auraButter), ("star.fill", .auraLilac),
            ("camera.macro", .auraMint), ("sun.max.fill", .auraPeach), ("moon.stars.fill", .auraLilac),
        ]
        return stickers[((index % stickers.count) + stickers.count) % stickers.count]
    }

    /// "summer dump ✦ 14.10.26", or just the date between sparkles.
    static func captionText(_ caption: String, date: Date) -> String {
        let stamp = date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "✦ \(stamp) ✦" : "\(text) ✦ \(stamp)"
    }

    static func aspectFill(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }
}

// MARK: - Export

/// Everything an export draws, captured on the main actor so rendering can
/// run off it.
struct CollageSnapshot {
    struct Photo {
        let image: UIImage
        let crop: CollageCrop
        let swatch: UIColor
    }

    let layout: CollageLayout
    let design: CollageDesign
    /// In slot order.
    let photos: [Photo]
    /// The background's colours, resolved (the blurred photo uses `backdrop`).
    let backgroundColors: [UIColor]
    let backdrop: UIImage?
    let date: Date
}

/// Draws a collage with Core Graphics, off the main actor: the whole
/// picture, or one carousel slide at a time so a five-slide canvas never
/// becomes one giant bitmap.
enum CollageRenderer {
    static func image(_ snapshot: CollageSnapshot, size: PixelSize) -> UIImage {
        let canvas = CGSize(width: size.width, height: size.height)
        return ShareRenderer.renderer(canvas, opaque: true).image { context in
            draw(snapshot, canvas: canvas, in: context.cgContext)
        }
    }

    /// One slide: the whole canvas drawn shifted, so only its columns land.
    static func slide(_ snapshot: CollageSnapshot, _ slice: CarouselSlicer.Slice, canvas size: PixelSize) -> UIImage {
        let canvas = CGSize(width: size.width, height: size.height)
        return ShareRenderer.renderer(CGSize(width: slice.width, height: slice.height), opaque: true).image { context in
            context.cgContext.translateBy(x: -CGFloat(slice.x), y: 0)
            draw(snapshot, canvas: canvas, in: context.cgContext)
        }
    }

    private static func draw(_ snapshot: CollageSnapshot, canvas: CGSize, in cg: CGContext) {
        let design = snapshot.design
        let style = design.style
        let short = min(canvas.width, canvas.height)
        cg.interpolationQuality = .high
        drawBackground(snapshot, canvas: canvas, in: cg)

        for strip in snapshot.layout.strips {
            let rect = CollageArt.pixels(strip.frame, in: canvas)
            cg.saveGState()
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: strip.rotation * .pi / 180)
            cg.setShadow(offset: CGSize(width: 0, height: short * 0.008), blur: short * 0.025, color: UIColor.black.withAlphaComponent(0.28).cgColor)
            cg.addPath(CollageArt.stripPath(strip, in: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)))
            cg.setFillColor(UIColor.brandInk.cgColor)
            cg.fillPath(using: .evenOdd)
            cg.restoreGState()
        }

        let radii = style.cornerRadii(amount: design.corners, aspect: design.format.widthOverHeight)
        for (index, slot) in snapshot.layout.slots.enumerated() where index < snapshot.photos.count {
            let photo = snapshot.photos[index]
            let frame = CollageArt.pixels(slot.frame, in: canvas)
            let window = CollageArt.pixels(slot.window, in: canvas).offsetBy(dx: -frame.midX, dy: -frame.midY)
            cg.saveGState()
            cg.translateBy(x: frame.midX, y: frame.midY)
            cg.rotate(by: slot.rotation * .pi / 180)
            if style.hasCards {
                let card = CGRect(x: -frame.width / 2, y: -frame.height / 2, width: frame.width, height: frame.height)
                let radius = min(radii.card * canvas.height, min(card.width, card.height) / 2)
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: short * 0.01), blur: short * 0.035, color: UIColor.black.withAlphaComponent(0.22).cgColor)
                cg.addPath(CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil))
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillPath()
                cg.restoreGState()
            }
            let radius = min(radii.window * canvas.height, min(window.width, window.height) / 2)
            cg.addPath(CGPath(roundedRect: window, cornerWidth: radius, cornerHeight: radius, transform: nil))
            cg.clip()
            photo.image.draw(in: CollageArt.photoFrame(photo.crop, imageSize: photo.image.size, window: window))
            cg.restoreGState()
        }

        for decoration in snapshot.layout.decorations {
            let rect = CollageArt.pixels(decoration.frame, in: canvas)
            switch decoration.kind {
            case .tape(let tone):
                cg.saveGState()
                cg.translateBy(x: rect.midX, y: rect.midY)
                cg.rotate(by: decoration.rotation * .pi / 180)
                cg.setFillColor(CollageArt.tapeColor(tone).cgColor)
                cg.fill(CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
                cg.restoreGState()
            case .sticker(let index):
                let sticker = CollageArt.sticker(index)
                ShareRenderer.drawSymbol(sticker.symbol, in: rect, color: sticker.color, outline: .white, angle: decoration.rotation)
            case .palette:
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: short * 0.004), blur: short * 0.014, color: UIColor.black.withAlphaComponent(0.12).cgColor)
                let radius = min(rect.height * 0.16, rect.width / 2)
                cg.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillPath()
                cg.restoreGState()
            case .swatch(let photo):
                let color = photo < snapshot.photos.count ? snapshot.photos[photo].swatch : UIColor.brandBlush
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: rect)
                let line = max(1, rect.width * 0.03)
                cg.setStrokeColor(UIColor.black.withAlphaComponent(0.08).cgColor)
                cg.setLineWidth(line)
                cg.strokeEllipse(in: rect.insetBy(dx: line / 2, dy: line / 2))
            }
        }

        if let frame = snapshot.layout.captionFrame {
            let rect = CollageArt.pixels(frame, in: canvas)
            let text = CollageArt.captionText(design.caption, date: snapshot.date)
            var size = rect.height * 0.34
            var font = UIFont(name: CollageArt.captionFontName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
            // Shrink to fit, like the preview's minimum scale factor.
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            if width > rect.width, width > 0 {
                size *= max(rect.width / width, 0.3)
                font = font.withSize(size)
            }
            ShareRenderer.drawText(text, font: font, color: design.background.isDark ? .white : .brandInk, centeredIn: rect)
        }
    }

    private static func drawBackground(_ snapshot: CollageSnapshot, canvas: CGSize, in cg: CGContext) {
        let bounds = CGRect(origin: .zero, size: canvas)
        if snapshot.design.background == .photo, let backdrop = snapshot.backdrop {
            backdrop.draw(in: CollageArt.aspectFill(backdrop.size, in: bounds))
            cg.setFillColor(UIColor.white.withAlphaComponent(CollageArt.backdropVeil).cgColor)
            cg.fill(bounds)
            return
        }
        let colors = snapshot.backgroundColors
        if colors.count > 1,
           let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: canvas.width, y: canvas.height),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else {
            cg.setFillColor((colors.first ?? .brandPetal).cgColor)
            cg.fill(bounds)
        }
    }
}

// MARK: - Picked photos

enum CollageImaging {
    struct Decoded: Sendable {
        let image: UIImage
        /// The AI marking the file carried (see `Provenance.collage(of:)`).
        let sourceType: DigitalSourceType?
        let swatch: UIColor
    }

    /// Big enough for the export (2160 px) at that many photos, with room
    /// to zoom, and no bigger: nine full-size photos would take gigabytes.
    static func decodeSize(forCount count: Int) -> Int {
        count <= 3 ? 2048 : count <= 6 ? 1600 : 1280
    }

    /// Downsampled with ImageIO and upright. Call it off the main actor.
    static func decode(_ data: Data, maxPixel: Int) -> Decoded? {
        guard let image = ImageUtilities.decodedImage(from: data, maxPixel: maxPixel) else { return nil }
        return Decoded(image: image, sourceType: ImageExporter.digitalSourceType(in: data), swatch: swatch(of: image))
    }

    /// The liveliest colour of an 8 × 8 sample, for the moodboard's colour
    /// card; the average when the photo has none (black and white).
    static func swatch(of image: UIImage) -> UIColor {
        guard let source = image.cgImage else { return .brandBlush }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .brandBlush }
        var best: (score: CGFloat, color: UIColor)?
        var total = (red: CGFloat(0), green: CGFloat(0), blue: CGFloat(0))
        for index in 0..<(side * side) {
            let red = CGFloat(pixels[index * 4]) / 255, green = CGFloat(pixels[index * 4 + 1]) / 255, blue = CGFloat(pixels[index * 4 + 2]) / 255
            total = (total.red + red, total.green + green, total.blue + blue)
            let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let score = brightness < 0.25 ? 0 : saturation * (0.4 + brightness)
            if score > (best?.score ?? 0) { best = (score, color) }
        }
        if let best, best.score > 0.15 { return best.color }
        let count = CGFloat(side * side)
        return UIColor(red: total.red / count, green: total.green / count, blue: total.blue / count, alpha: 1)
    }

    /// A soft blur of `image` for the background: small, since it's blurred
    /// anyway, through the shared Core Image context.
    static func backdrop(from image: UIImage) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let small = ImageUtilities.normalized(image, maxLongEdge: 240)
            guard let input = ImageFilters.ciImage(small) else { return nil }
            let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 10).cropped(to: input.extent)
            return ImageFilters.render(blurred)
        }.value
    }
}

extension PhotoLibrarySaver {
    /// Carousel slides, in order: each is dated a second after the one
    /// before, so Photos and Instagram's picker list them in sequence.
    static func saveInOrder(_ files: [Data]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        let start = Date().addingTimeInterval(-Double(files.count))
        try await PHPhotoLibrary.shared().performChanges {
            for (index, data) in files.enumerated() {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = start.addingTimeInterval(Double(index))
                request.addResource(with: .photo, data: data, options: nil)
            }
        }
    }
}
