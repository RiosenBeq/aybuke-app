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
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
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

    static func hasAlpha(_ image: UIImage) -> Bool {
        guard let alphaInfo = image.cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        default:
            return false
        }
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
