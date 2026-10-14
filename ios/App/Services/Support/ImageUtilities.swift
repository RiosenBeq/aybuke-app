import UIKit
import ImageIO
import AppCore

enum ImageUtilities {
    static func pixelSize(of image: UIImage) -> PixelSize {
        PixelSize(width: Int(image.size.width * image.scale), height: Int(image.size.height * image.scale))
    }

    /// Decodes straight to an upright image of at most `maxPixel` on the long
    /// edge. A 48 MP photo never becomes a full-size bitmap (about 190 MB),
    /// which `UIImage(data:)` plus `normalized` would make. Call it off the
    /// main actor.
    static func decodedImage(from data: Data, maxPixel: Int = 2048) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            // Without "always", ImageIO may hand back the small embedded preview.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // ImageIO's bitmap is converted again every time it's read (for a
        // HEIC photo that takes about as long as decoding it), and the
        // canvas, previews, Vision, effects and saving all read it. One copy
        // into a plain 8-bit bitmap makes each of those reads cheap.
        let decoded = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        return draw(size: size, opaque: !hasAlpha(decoded), colorSpace: cgImage.colorSpace) { _ in
            decoded.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Bakes in EXIF orientation and downsizes to `maxLongEdge` pixels at scale 1.
    /// Every image entering the editor goes through here so pixel math
    /// (masks, crops, uploads) can ignore orientation.
    static func normalized(_ image: UIImage, maxLongEdge: Int = 2048) -> UIImage {
        let target = ImageSizing.fit(pixelSize(of: image), maxLongEdge: maxLongEdge)
        if image.imageOrientation == .up, image.scale == 1, target == pixelSize(of: image) {
            return image
        }
        return redraw(image, to: target)
    }

    static func redraw(_ image: UIImage, to size: PixelSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !hasAlpha(image)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width, height: size.height), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
    }

    /// Whether the bitmap has an alpha channel. Core Image and
    /// UIGraphicsImageRenderer often add one to opaque pictures, so this
    /// alone doesn't mean anything is see-through (`hasTransparentPixels`).
    static func hasAlpha(_ image: UIImage) -> Bool {
        guard let alphaInfo = image.cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        default:
            return false
        }
    }

    // MARK: Opaque bitmaps

    /// Draws into an 8-bit bitmap with UIKit's top-left origin (`size` in
    /// points at `scale`). An opaque picture gets no alpha channel, so it
    /// saves as a JPEG instead of a PNG several times the size, and the
    /// bitmap keeps `colorSpace` (an 8-bit one, else Display P3), so photos
    /// keep their wide colour without the 16-bit floats UIGraphicsImageRenderer
    /// switches to for it. Shadow offsets here are in the bitmap's own y-up
    /// space, so only draw shadows with a zero offset.
    static func draw(size: CGSize, scale: CGFloat = 1, opaque: Bool, colorSpace: CGColorSpace?,
                     _ actions: (CGContext) -> Void) -> UIImage {
        // Whole pixels, rounded up as UIGraphicsImageRenderer does.
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        // BGRA, the layout the screen uses, so showing it needs no conversion.
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipFirst : .premultipliedFirst
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: bitmapColorSpace(for: colorSpace),
                                      bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else {
            // No bitmap for this size: UIKit's renderer, as before.
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = opaque
            return UIGraphicsImageRenderer(size: size, format: format).image { actions($0.cgContext) }
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        actions(context)
        UIGraphicsPopContext()
        guard let cgImage = context.makeImage() else { return UIImage() }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// `space` when an 8-bit bitmap can use it; Display P3 for extended-range
    /// (16-bit float) and non-RGB spaces, so no wide colour is lost.
    static func bitmapColorSpace(for space: CGColorSpace?) -> CGColorSpace {
        if let space, space.model == .rgb, !CGColorSpaceUsesExtendedRange(space) { return space }
        return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// The same picture without an alpha channel. Any see-through pixels
    /// turn black, so only use it for pictures that are opaque.
    static func opaque(_ image: UIImage) -> UIImage {
        guard hasAlpha(image), let cgImage = image.cgImage else { return image }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        return draw(size: size, opaque: true, colorSpace: cgImage.colorSpace) { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Whether any pixel is less than fully opaque. Reads every alpha value,
    /// so a cut-out is never mistaken for a photo; images without an alpha
    /// channel answer at once. Call it off the main actor.
    static func hasTransparentPixels(_ image: UIImage) -> Bool {
        guard hasAlpha(image), let cgImage = image.cgImage else { return false }
        if cgImage.alphaInfo == .alphaOnly { return true }
        let width = cgImage.width, height = cgImage.height
        // 8-bit RGBA is read where it is; other layouts are converted first.
        let readable = cgImage.bitsPerComponent == 8 && cgImage.bitsPerPixel == 32 && !cgImage.bitmapInfo.contains(.floatComponents)
        let source: CGImage
        if readable {
            source = cgImage
        } else {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let converted = context.makeImage() else { return true }
            source = converted
        }
        guard let data = source.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
        let alphaFirst = source.alphaInfo == .premultipliedFirst || source.alphaInfo == .first
        let byteOrder = source.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let littleEndian = byteOrder == CGBitmapInfo.byteOrder32Little.rawValue
        // Where alpha sits within each 4-byte pixel in memory.
        let offset = alphaFirst != littleEndian ? 0 : 3
        let rowBytes = source.bytesPerRow
        for row in 0..<height {
            let line = bytes + row * rowBytes + offset
            for column in 0..<width where line[column * 4] != 255 {
                return true
            }
        }
        return false
    }

    /// Drops an alpha channel that no pixel uses, so the encoders write a
    /// JPEG; real transparency (cut-outs, stickers) is kept for a PNG.
    static func droppingUnusedAlpha(_ image: UIImage) -> UIImage {
        guard hasAlpha(image), !hasTransparentPixels(image) else { return image }
        return opaque(image)
    }

    static func jpegData(_ image: UIImage, maxLongEdge: Int, quality: CGFloat = 0.9) -> Data? {
        let target = ImageSizing.fit(pixelSize(of: image), maxLongEdge: maxLongEdge)
        let resized = target == pixelSize(of: image) && image.imageOrientation == .up ? image : redraw(image, to: target)
        return resized.jpegData(compressionQuality: quality)
    }

    static func pngData(_ image: UIImage, maxLongEdge: Int) -> Data? {
        let target = ImageSizing.fit(pixelSize(of: image), maxLongEdge: maxLongEdge)
        let resized = target == pixelSize(of: image) && image.imageOrientation == .up ? image : redraw(image, to: target)
        return resized.pngData()
    }
}
