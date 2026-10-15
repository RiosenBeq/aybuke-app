import UIKit
import Vision
import CoreImage
import AppCore

/// What Vision found in one photo, as soft masks with the photo's extent
/// (white = there). The Vision calls stay this thin so the rest can be
/// tested with saved masks (the Simulator can't run these models).
struct VisionMasks {
    /// Person segmentation at `.accurate`: every person, with hair detail.
    var person: CIImage?
    /// Person instances: up to four people, one coarse mask each.
    var people: [CIImage] = []
    /// Foreground instances: subjects of any kind (pets, things, people).
    var things: [CIImage] = []
    /// Face and upper-body boxes, normalized, Vision's bottom-left origin.
    var humans: [CGRect] = []
}

/// One photo's subjects on the device, shared by DSLR '12, Cut out and
/// Erase's "Pick a person": who and what is in it, where (a label map for
/// taps), and a soft matte for any set of them. People get Vision's
/// accurate person matte, split between them by their instances and snapped
/// to strands of hair; pets and things get their foreground instance. Whole
/// subjects only, never body parts. Mattes are made at the analysed size
/// (at most 2048 px) and scaled to a preview or a full-size render, so both
/// look the same.
final class SubjectMasks: @unchecked Sendable {
    struct Subject: Identifiable, Sendable {
        /// Label in the label map (0 is the background).
        let id: Int
        /// Normalized, top-left origin.
        let bounds: CGRect
        let isPerson: Bool
    }

    /// The photo that was analysed (at most 2048 px, orientation baked in).
    let source: CGImage
    /// Left to right, so labels and VoiceOver read in order.
    let subjects: [Subject]
    let allIDs: IndexSet
    /// The photo was already a cut-out: there's nothing behind it to blur.
    let hasTransparency: Bool

    private let labels: [UInt8]
    private let labelWidth: Int
    private let labelHeight: Int
    /// Soft matte (white = keep) with the source's extent for a set of labels.
    private let makeMatte: (IndexSet) -> CIImage
    private let lock = NSLock()
    /// Rendered mattes (8-bit, 4 MB at 2048 px): keep a few.
    private var mattes: [(ids: IndexSet, matte: CIImage)] = []

    var extent: CGRect { CGRect(x: 0, y: 0, width: source.width, height: source.height) }
    var hasPeople: Bool { subjects.contains(where: \.isPerson) }

    init(source: CGImage, labels: [UInt8], labelWidth: Int, labelHeight: Int, personIDs: Set<Int> = [],
         makeMatte: @escaping (IndexSet) -> CIImage) {
        self.source = source
        self.labels = labels
        self.labelWidth = labelWidth
        self.labelHeight = labelHeight
        self.makeMatte = makeMatte
        subjects = Self.subjects(in: labels, width: labelWidth, height: labelHeight, personIDs: personIDs)
        allIDs = IndexSet(subjects.map(\.id))
        hasTransparency = Self.hasTransparentPixels(source)
    }

    // MARK: Analysis

    /// Runs Vision. Throws `noSubjectFound` when nothing stands out.
    static func analyze(_ image: UIImage) throws -> SubjectMasks {
        let normalized = ImageUtilities.normalized(image, maxLongEdge: 2048)
        guard let cgImage = normalized.cgImage else {
            throw AIServiceError.invalidRequest(String(localized: "This photo couldn't be read."))
        }
        #if DEBUG
        if let fixture = ScreenshotFixtures.visionMasks(for: image, size: CGSize(width: cgImage.width, height: cgImage.height)) {
            return try build(source: cgImage, vision: fixture)
        }
        #endif
        return try build(source: cgImage, vision: runVision(on: cgImage))
    }

    private static func runVision(on cgImage: CGImage) throws -> VisionMasks {
        let extent = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        var masks = VisionMasks()
        let faces = VNDetectFaceRectanglesRequest()
        let bodies = VNDetectHumanRectanglesRequest()
        try? handler.perform([faces, bodies])
        masks.humans = (faces.results ?? []).map(\.boundingBox) + (bodies.results ?? []).map(\.boundingBox)
        var failures = 0
        // The person models also "find" people in pets and lattes, so they
        // only run when there's a face or a body.
        if !masks.humans.isEmpty {
            let person = VNGeneratePersonSegmentationRequest()
            person.qualityLevel = .accurate
            person.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let people = VNGeneratePersonInstanceMaskRequest()
            do {
                try handler.perform([person, people])
                if let buffer = person.results?.first?.pixelBuffer {
                    masks.person = Matte.scaled(Matte.image(buffer), to: extent)
                }
                if let observation = people.results?.first {
                    masks.people = observation.allInstances.compactMap { instance in
                        (try? observation.generateScaledMaskForImage(forInstances: [instance], from: handler)).map(Matte.image)
                    }
                }
            } catch {
                failures += 1
            }
        }
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([foreground])
            if let observation = foreground.results?.first {
                masks.things = observation.allInstances.compactMap { instance in
                    (try? observation.generateScaledMaskForImage(forInstances: [instance], from: handler)).map(Matte.image)
                }
            }
        } catch {
            failures += 1
        }
        if failures > 0, masks.person == nil, masks.things.isEmpty {
            throw AIServiceError.server(code: "vision_failed", message: String(localized: "Background removal isn't available on this device."))
        }
        return masks
    }

    /// Joins Vision's masks into subjects: the people it can tell apart
    /// (only those with a face or body in them), then pets and things that
    /// aren't part of anyone.
    static func build(source: CGImage, vision: VisionMasks) throws -> SubjectMasks {
        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let unit = max(extent.width, extent.height) / 1000
        let labelWidth = source.width >= source.height ? 512 : max(1, Int((512 * extent.width / extent.height).rounded()))
        let labelHeight = source.height >= source.width ? 512 : max(1, Int((512 * extent.height / extent.width).rounded()))
        let small = { (mask: CIImage) in Matte.pixels(mask, width: labelWidth, height: labelHeight) }

        var people: [(mask: CIImage, pixels: [UInt8])] = []
        if vision.person != nil {
            for mask in vision.people {
                let pixels = small(mask)
                let hasSomeone = vision.humans.contains { box in
                    let x = min(max(Int(box.midX * CGFloat(labelWidth - 1)), 0), labelWidth - 1)
                    let y = min(max(Int((1 - box.midY) * CGFloat(labelHeight - 1)), 0), labelHeight - 1)
                    return pixels[y * labelWidth + x] > 127
                }
                if hasSomeone { people.append((mask, pixels)) }
            }
        }

        // Each person's zone: her instance grown to take in loose hair. Where
        // zones meet, the person matte is shared by how much each covers.
        var shares: [CIImage] = []
        var personAll: CIImage?
        if let person = vision.person, !people.isEmpty {
            let zones = people.map { Matte.blur(Matte.dilate($0.mask, 22 * unit), 8 * unit) }
            let sum = zones.dropFirst().reduce(zones[0]) { Matte.add($0, $1) }
            let denominator = sum.applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0.02, y: 0.02, z: 0.02, w: 1),
                "inputMaxComponents": CIVector(x: 16, y: 16, z: 16, w: 1),
            ])
            shares = zones.map { denominator.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: $0]).applyingFilter("CIColorClamp") }
            personAll = Matte.multiply(person, Matte.ramp(sum, 0, 1))
        }

        // Things: foreground instances, minus anything that's part of a person
        // (her hair, a sliver of background between curls). What's left has to
        // be solid to count, like a pet beside her or the cup she holds out.
        var things: [(mask: CIImage, pixels: [UInt8])] = []
        for thing in vision.things {
            var mask = thing
            if let personAll {
                let rest = Matte.multiply(thing, Matte.invert(Matte.dilate(Matte.ramp(personAll, 0.1, 0.4), 6 * unit)))
                let solid = Matte.dilate(Matte.erode(rest, 12 * unit), 12 * unit)
                mask = Matte.multiply(thing, Matte.ramp(Matte.blur(solid, 3 * unit), 0.05, 0.6))
            }
            let pixels = small(mask)
            let covered = pixels.reduce(0) { $0 + ($1 > 127 ? 1 : 0) }
            guard Double(covered) / Double(pixels.count) > 0.004 else { continue }
            things.append((mask, pixels))
        }
        guard !people.isEmpty || !things.isEmpty else { throw AIServiceError.noSubjectFound }

        // The label map: people first (1…4), then things (100…).
        var labels = [UInt8](repeating: 0, count: labelWidth * labelHeight)
        for (index, person) in people.enumerated() {
            for i in labels.indices where labels[i] == 0 && person.pixels[i] > 127 { labels[i] = UInt8(index + 1) }
        }
        for (index, thing) in things.enumerated() {
            for i in labels.indices where labels[i] == 0 && thing.pixels[i] > 127 { labels[i] = UInt8(100 + index) }
        }
        let guide = CIImage(cgImage: source)
        let person = vision.person
        let thingMasks = things.map(\.mask)
        let personIDs = Set(people.indices.map { $0 + 1 })
        return SubjectMasks(source: source, labels: labels, labelWidth: labelWidth, labelHeight: labelHeight, personIDs: personIDs) { ids in
            var result: CIImage?
            let chosen = ids.filter { personIDs.contains($0) }.map { shares[$0 - 1] }
            if let person, let first = chosen.first {
                let share = chosen.dropFirst().reduce(first) { Matte.add($0, $1) }
                result = Matte.multiply(person, Matte.ramp(share, 0, 1))
            }
            for id in ids where id >= 100 && id - 100 < thingMasks.count {
                result = result.map { Matte.maximum($0, thingMasks[id - 100]) } ?? thingMasks[id - 100]
            }
            guard let result else { return Matte.gray(0, extent) }
            return Matte.refined(result, guide: guide)
        }
    }

    // MARK: Mattes

    /// Soft matte (white = keep) of `ids` at the analysed size, rendered once.
    func matte(for ids: IndexSet) -> CIImage {
        lock.lock()
        defer { lock.unlock() }
        if let cached = mattes.first(where: { $0.ids == ids }) { return cached.matte }
        let recipe = makeMatte(ids)
        let matte = Matte.rendered(recipe) ?? recipe
        mattes.append((ids, matte))
        if mattes.count > 3 { mattes.removeFirst() }
        return matte
    }

    /// The same matte scaled to `extent` (a preview or a full-size render).
    func matte(for ids: IndexSet, fitting extent: CGRect) -> CIImage {
        Matte.scaled(matte(for: ids), to: extent)
    }

    // MARK: Taps and outlines

    /// The subject under a normalized point (top-left origin), or nil on the
    /// background. Looks at a 5×5 patch so taps on hair and edges still count.
    func subject(atNormalized point: CGPoint) -> Int? {
        let x = Int((min(max(point.x, 0), 1) * CGFloat(labelWidth - 1)).rounded())
        let y = Int((min(max(point.y, 0), 1) * CGFloat(labelHeight - 1)).rounded())
        var counts: [UInt8: Int] = [:]
        for dy in -2...2 {
            for dx in -2...2 {
                let px = x + dx, py = y + dy
                guard px >= 0, py >= 0, px < labelWidth, py < labelHeight else { continue }
                let label = labels[py * labelWidth + px]
                if label != 0 { counts[label, default: 0] += 1 }
            }
        }
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        return Int(best.key)
    }

    /// Normalized bounds of the chosen subjects together.
    func bounds(of ids: IndexSet) -> CGRect {
        subjects.filter { ids.contains($0.id) }.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
    }

    /// Thin outlines around each subject at the label map's size: white for
    /// the kept ones, blush for the others.
    func outlines(kept ids: IndexSet) -> CGImage? {
        let width = labelWidth, height = labelHeight
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let label = labels[y * width + x]
                guard label != 0 else { continue }
                var isEdge = false
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-2, 0), (2, 0), (0, -2), (0, 2)] {
                    let nx = x + dx, ny = y + dy
                    if nx < 0 || ny < 0 || nx >= width || ny >= height || labels[ny * width + nx] != label {
                        isEdge = true
                        break
                    }
                }
                guard isEdge else { continue }
                let offset = (y * width + x) * 4
                // Premultiplied RGBA: white, or blush (#F7C1D9).
                let color: (UInt8, UInt8, UInt8) = ids.contains(Int(label)) ? (255, 255, 255) : (247, 193, 217)
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private static func subjects(in labels: [UInt8], width: Int, height: Int, personIDs: Set<Int>) -> [Subject] {
        var boxes: [UInt8: (minX: Int, minY: Int, maxX: Int, maxY: Int, sumX: Int, count: Int)] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let label = labels[y * width + x]
                guard label != 0 else { continue }
                var box = boxes[label] ?? (x, y, x, y, 0, 0)
                box.minX = min(box.minX, x); box.maxX = max(box.maxX, x)
                box.minY = min(box.minY, y); box.maxY = max(box.maxY, y)
                box.sumX += x; box.count += 1
                boxes[label] = box
            }
        }
        let w = CGFloat(max(width, 1)), h = CGFloat(max(height, 1))
        return boxes
            // Specks of a few pixels aren't something she could tap.
            .filter { $0.value.count > 12 }
            .sorted { Double($0.value.sumX) / Double($0.value.count) < Double($1.value.sumX) / Double($1.value.count) }
            .map { label, box in
                Subject(id: Int(label), bounds: CGRect(
                    x: CGFloat(box.minX) / w, y: CGFloat(box.minY) / h,
                    width: CGFloat(box.maxX - box.minX + 1) / w, height: CGFloat(box.maxY - box.minY + 1) / h
                ), isPerson: personIDs.contains(Int(label)))
            }
    }

    /// Core Image output always has an alpha channel, so look at the pixels.
    private static func hasTransparentPixels(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }
}

/// Core Image building blocks for soft mattes (grey images, white = subject)
/// and the colours along their edges. Pure and safe off the main thread.
enum Matte {
    private static let measuring = ImageFilters.measuringContext

    /// A Vision buffer or saved mask as a matte, its values as they are.
    static func image(_ buffer: CVPixelBuffer) -> CIImage {
        CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }

    static func gray(_ value: CGFloat, _ extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value)).cropped(to: extent)
    }

    static func scaled(_ image: CIImage, to extent: CGRect) -> CIImage {
        let from = image.extent
        guard from != extent, from.width > 0, from.height > 0 else { return image.cropped(to: extent) }
        return image
            .transformed(by: CGAffineTransform(translationX: -from.minX, y: -from.minY)
                .concatenating(CGAffineTransform(scaleX: extent.width / from.width, y: extent.height / from.height))
                .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY)))
            .cropped(to: extent)
    }

    static func multiply(_ a: CIImage, _ b: CIImage) -> CIImage {
        a.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: b])
    }

    static func maximum(_ a: CIImage, _ b: CIImage) -> CIImage {
        a.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: b])
    }

    /// Adding two opaque layers sums their alpha too; reset it to 1.
    static func add(_ a: CIImage, _ b: CIImage) -> CIImage {
        a.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: b]).settingAlphaOne(in: a.extent)
    }

    static func invert(_ a: CIImage) -> CIImage { a.applyingFilter("CIColorInvert") }

    /// 0 at `low` and below, 1 at `high` and above, linear between.
    static func ramp(_ a: CIImage, _ low: CGFloat, _ high: CGFloat) -> CIImage {
        let scale = 1 / max(high - low, 0.0001)
        return a.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputBiasVector": CIVector(x: -low * scale, y: -low * scale, z: -low * scale, w: 0),
        ]).applyingFilter("CIColorClamp")
    }

    static func blur(_ a: CIImage, _ sigma: CGFloat) -> CIImage {
        guard sigma > 0.3 else { return a }
        return a.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: a.extent)
    }

    static func dilate(_ a: CIImage, _ radius: CGFloat) -> CIImage {
        guard radius >= 1 else { return a }
        return a.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius]).cropped(to: a.extent)
    }

    static func erode(_ a: CIImage, _ radius: CGFloat) -> CIImage {
        guard radius >= 1 else { return a }
        return a.clampedToExtent().applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius]).cropped(to: a.extent)
    }

    /// Rec. 709 luma of gamma-encoded values in every channel.
    static func lightness(_ image: CIImage) -> CIImage {
        image.applyingFilter("CILinearToSRGBToneCurve").applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
        ]).settingAlphaOne(in: image.extent)
    }

    /// Snaps the matte to the photo's own edges in a band around the
    /// subject's outline (a guided filter on the photo's lightness), which
    /// brings back strands of hair the coarse matte only half caught and
    /// drops the background caught between curls.
    static func refined(_ matte: CIImage, guide image: CIImage) -> CIImage {
        let extent = image.extent
        let unit = max(extent.width, extent.height) / 1000
        let guided = matte.applyingFilter("CIGuidedFilter", parameters: [
            "inputGuideImage": lightness(image), kCIInputRadiusKey: 8 * unit, "inputEpsilon": 0.001,
        ]).cropped(to: extent).applyingFilter("CIColorClamp")
        let solid = ramp(matte, 0.3, 0.7)
        let band = blur(multiply(dilate(solid, 14 * unit), invert(erode(solid, 6 * unit))), 3 * unit)
        return guided.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: matte, kCIInputMaskImageKey: band])
            .cropped(to: extent)
    }

    /// Cut out's Edge control on a matte (`CutoutEdge`).
    static func edged(_ matte: CIImage, plan: CutoutEdge.Plan) -> CIImage {
        guard !plan.isIdentity else { return matte }
        let long = max(matte.extent.width, matte.extent.height)
        var result = matte
        if plan.low > 0 || plan.high < 1 { result = ramp(result, plan.low, plan.high) }
        guard plan.choke > 0 || plan.feather > 0 else { return result }
        // A feather fades her edge inward and never reaches past it, so
        // nothing from around her (old background or smudged colour) shows.
        let feathered = blur(erode(result, plan.choke * long), plan.feather * long)
        return feathered.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: result])
    }

    /// Push-pull fill: `image` where `known` is white, and smooth colours
    /// from around it everywhere else, however big the hole.
    static func fill(_ image: CIImage, known: CIImage) -> CIImage {
        let extent = image.extent
        let start = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent), kCIInputMaskImageKey: known,
        ]).cropped(to: extent)
        var levels = [start]
        var level = start
        while max(level.extent.width, level.extent.height) > 2 {
            let from = level.extent
            let rect = CGRect(x: from.minX / 2, y: from.minY / 2, width: (from.width / 2).rounded(.up), height: (from.height / 2).rounded(.up))
            level = level.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5)).cropped(to: rect)
            levels.append(level)
        }
        guard let coarsest = levels.last else { return image }
        var result = coarsest.unpremultiplyingAlpha().settingAlphaOne(in: coarsest.extent)
        for level in levels.dropLast().reversed() {
            let up = result.clampedToExtent().transformed(by: CGAffineTransform(scaleX: 2, y: 2)).cropped(to: level.extent)
            result = level.composited(over: up).cropped(to: level.extent)
        }
        return result.cropped(to: extent)
    }

    /// The subject's own colours carried out over its soft edge, so the
    /// edge never brings the old background along (no halo on a new
    /// backdrop, no sharp fringe on a blurred one).
    static func foreground(of image: CIImage, matte: CIImage) -> CIImage {
        let extended = fill(image, known: ramp(matte, 0.88, 0.98))
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: extended, kCIInputMaskImageKey: ramp(matte, 0.75, 0.97),
        ]).cropped(to: image.extent)
    }

    /// Renders a matte once into an 8-bit grey bitmap, so later uses read
    /// pixels instead of running its filters again. The shared context sees
    /// the photo as light (the guided filter reads its lightness); the matte
    /// itself comes out as it is, with no colour matching.
    static func rendered(_ matte: CIImage) -> CIImage? {
        let extent = matte.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        ImageFilters.context.render(matte, toBitmap: &bytes, rowBytes: width, bounds: extent, format: .L8, colorSpace: nil)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return CIImage(cgImage: cgImage, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// A matte as a grey bitmap for drawing (top-left origin, white = there).
    static func grayImage(_ matte: CIImage, longEdge: CGFloat) -> CGImage? {
        let extent = matte.extent
        let scale = min(1, longEdge / max(extent.width, extent.height))
        let target = CGRect(x: 0, y: 0, width: (extent.width * scale).rounded(), height: (extent.height * scale).rounded())
        return measuring.createCGImage(scaled(matte, to: target), from: target, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    }

    /// A matte at `width` × `height` as bytes, row 0 at the top.
    static func pixels(_ matte: CIImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        measuring.render(scaled(matte, to: target), toBitmap: &pixels, rowBytes: width, bounds: target, format: .L8, colorSpace: nil)
        return pixels
    }
}
