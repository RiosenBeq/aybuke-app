import UIKit
import Vision
import CoreImage
import AppCore

/// Adjust's Soft skin mask for one photo (adults only, `SoftSkin`): where the
/// skin is, as a soft grey matte. Vision's person matte, narrowed to each
/// face's own skin colour (sampled on the cheeks and forehead), minus the
/// eyes, brows, lips and nostrils (`FaceFeatureMask`) and minus fine texture
/// such as hair strands and freckles, which stay as they are. Made once per
/// step on a copy of at most 640 px (the mask is feathered anyway) and scaled
/// to the preview or the full-size photo, so both match. Nothing leaves the
/// device.
enum SkinMask {
    static let longEdge = 640

    /// Off the main actor. Nil when no face with landmarks is found.
    static func make(for image: UIImage) -> CIImage? {
        let small = ImageUtilities.normalized(image, maxLongEdge: longEdge)
        guard let cgImage = small.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        let extent = CGRect(x: 0, y: 0, width: width, height: height)

        var faces: [FaceLandmarks] = []
        var person: CIImage?
        #if DEBUG
        // The Simulator can't run these models: landmarks and masks found on a Mac.
        if let saved = ScreenshotFixtures.visionLandmarks(for: image) {
            faces = saved
            person = ScreenshotFixtures.visionMasks(for: image, size: extent.size)?.person
        }
        #endif
        if faces.isEmpty {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let landmarks = VNDetectFaceLandmarksRequest()
            try? handler.perform([landmarks])
            faces = (landmarks.results ?? [])
                .filter { $0.boundingBox.width * $0.boundingBox.height > 0.002 }
                .compactMap(Self.landmarks(of:))
            guard !faces.isEmpty else { return nil }
            let segmentation = VNGeneratePersonSegmentationRequest()
            segmentation.qualityLevel = .accurate
            segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
            if (try? handler.perform([segmentation])) != nil, let buffer = segmentation.results?.first?.pixelBuffer {
                person = Matte.scaled(Matte.image(buffer), to: extent)
            }
        }
        guard !faces.isEmpty else { return nil }

        let rgba = pixels(of: cgImage)
        let personBytes = person.map { Matte.pixels($0, width: width, height: height) }
        // Pixels, y up like the landmarks.
        let pixelFaces = faces.map { $0.mapped { FacePoint(x: $0.x * Double(width), y: $0.y * Double(height)) } }
        func color(at point: FacePoint) -> (r: Double, g: Double, b: Double)? {
            let x = Int(point.x), row = height - 1 - Int(point.y)
            guard x >= 0, x < width, row >= 0, row < height else { return nil }
            let i = 4 * (row * width + x)
            return (Double(rgba[i]) / 255, Double(rgba[i + 1]) / 255, Double(rgba[i + 2]) / 255)
        }
        let tones = pixelFaces.compactMap { face in
            SkinTone.reference(samples: FaceFeatureMask.skinSamplePoints(for: face).compactMap(color(at:)))
        }
        guard !tones.isEmpty else { return nil }
        let features = pixelFaces.flatMap(FaceFeatureMask.ellipses(for:))
        // Without Vision's person matte (it can fail), stay near the faces.
        let regions = pixelFaces.compactMap(faceRegion(of:))
        let texture = textureEnergy(rgba: rgba, width: width, height: height)

        var mask = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let y = Double(height - row) - 0.5
            for x in 0..<width {
                let i = row * width + x
                var weight: Double
                if let personBytes {
                    weight = Double(personBytes[i]) / 255
                } else {
                    let point = FacePoint(x: Double(x) + 0.5, y: y)
                    weight = 0
                    for region in regions where region.normalizedDistance(to: point) <= 1 {
                        weight = 1
                        break
                    }
                }
                guard weight > 0.03 else { continue }
                let r = Double(rgba[4 * i]) / 255, g = Double(rgba[4 * i + 1]) / 255, b = Double(rgba[4 * i + 2]) / 255
                var skin = 0.0
                for tone in tones { skin = max(skin, tone.likelihood(r: r, g: g, b: b)) }
                weight *= skin
                guard weight > 0.03 else { continue }
                // Hair strands, lashes and freckles keep their crisp detail.
                weight *= 1 - smoothstep(texture[i], from: 8, to: 18)
                guard weight > 0.03 else { continue }
                let point = FacePoint(x: Double(x) + 0.5, y: y)
                var nearest = 10.0
                for feature in features { nearest = min(nearest, feature.normalizedDistance(to: point)) }
                weight *= smoothstep(nearest, from: 1, to: 1.35)
                mask[i] = UInt8(max(0, min(255, (weight * 255).rounded())))
            }
        }
        guard let provider = CGDataProvider(data: Data(mask) as CFData),
              let maskImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return CIImage(cgImage: maskImage, options: [.colorSpace: NSNull()])
    }

    /// 0 at `from` and below, 1 at `to` and above, smooth between.
    private static func smoothstep(_ value: Double, from: Double, to: Double) -> Double {
        let t = min(1, max(0, (value - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }

    /// Around a face, down to the neck, for when there's no person matte.
    private static func faceRegion(of face: FaceLandmarks) -> FaceFeatureEllipse? {
        guard let center = face.center else { return nil }
        let size = face.eyeDistance
        guard size > 0 else { return nil }
        return FaceFeatureEllipse(center: FacePoint(x: center.x, y: center.y - 0.6 * size), radiusX: 1.6 * size, radiusY: 2.6 * size, angle: 0)
    }

    /// Local detail: the Laplacian's size averaged over 5×5 pixels (0–255 grey).
    private static func textureEnergy(rgba: [UInt8], width: Int, height: Int) -> [Double] {
        let count = width * height
        var gray = [Double](repeating: 0, count: count)
        for i in 0..<count {
            gray[i] = 0.299 * Double(rgba[4 * i]) + 0.587 * Double(rgba[4 * i + 1]) + 0.114 * Double(rgba[4 * i + 2])
        }
        // Summed-area table of |Laplacian|, for 5×5 means in constant time.
        var table = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var rowSum = 0.0
            for x in 0..<width {
                var lap = 0.0
                if x > 0, x < width - 1, y > 0, y < height - 1 {
                    let i = y * width + x
                    lap = abs(gray[i - 1] + gray[i + 1] + gray[i - width] + gray[i + width] - 4 * gray[i])
                }
                rowSum += lap
                table[(y + 1) * (width + 1) + x + 1] = table[y * (width + 1) + x + 1] + rowSum
            }
        }
        var energy = [Double](repeating: 0, count: count)
        for y in 0..<height {
            let y0 = max(0, y - 2), y1 = min(height, y + 3)
            for x in 0..<width {
                let x0 = max(0, x - 2), x1 = min(width, x + 3)
                let sum = table[y1 * (width + 1) + x1] - table[y0 * (width + 1) + x1] - table[y1 * (width + 1) + x0] + table[y0 * (width + 1) + x0]
                energy[y * width + x] = sum / Double((x1 - x0) * (y1 - y0))
            }
        }
        return energy
    }

    /// RGBA8, row 0 at the top.
    private static func pixels(of cgImage: CGImage) -> [UInt8] {
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    private static func landmarks(of face: VNFaceObservation) -> FaceLandmarks? {
        guard let marks = face.landmarks, let left = marks.leftEye, let right = marks.rightEye, let lips = marks.outerLips else { return nil }
        let box = face.boundingBox
        func points(_ region: VNFaceLandmarkRegion2D?) -> [FacePoint] {
            (region?.normalizedPoints ?? []).map {
                FacePoint(x: Double(box.minX + $0.x * box.width), y: Double(box.minY + $0.y * box.height))
            }
        }
        return FaceLandmarks(outerLips: points(lips), innerLips: points(marks.innerLips), leftEye: points(left), rightEye: points(right),
                             nose: points(marks.nose), faceContour: points(marks.faceContour),
                             leftEyebrow: points(marks.leftEyebrow), rightEyebrow: points(marks.rightEyebrow))
    }
}

extension PhotoQuality {
    /// Measured on a copy of at most 1024 px (off the main actor).
    static func measure(_ image: UIImage) -> PhotoQuality? {
        let small = ImageUtilities.normalized(image, maxLongEdge: PhotoQuality.measuredLongEdge)
        return small.cgImage.flatMap(measure(_:))
    }

    /// A copy already small enough (the Vision copy of `PhotoInsightsService`).
    static func measure(_ cgImage: CGImage) -> PhotoQuality? {
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return PhotoQuality.measure(rgba: bytes, width: width, height: height)
    }
}
