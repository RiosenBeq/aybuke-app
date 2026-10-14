import UIKit
import Darwin
import ImageIO
import AppCore

/// A launch step for `PerfProbe`; does nothing in shipping builds.
@inline(__always) func perfMark(_ name: String) {
    #if DEBUG || GL_PERF
    PerfProbe.mark(name)
    #endif
}

#if DEBUG || GL_PERF

/// Measurements behind the Performance section of docs/04-architecture.md,
/// in DEBUG builds and in Release builds made with the GL_PERF condition
/// (never shipped). Every launch prints the time from process start to
/// Explore's first frame; `-GLPerfBench <photo file>` also times the photo
/// pipeline once, and `-GLPerfOpen <photo file>` opens that photo in the
/// editor and prints how long it took to show. Lines start with "[perf]".
enum PerfProbe {
    /// When the kernel started this process: before dyld, static
    /// initializers and `main`.
    static let processStart: Double? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
    }()

    private static let lock = NSLock()
    nonisolated(unsafe) private static var marks: [(name: String, ms: Double)] = []
    @MainActor private static var launchLogged = false
    @MainActor private static var openStarted: Double?

    static var now: Double { Date().timeIntervalSince1970 }

    /// A launch step, in milliseconds since the process started.
    static func mark(_ name: String) {
        guard let start = processStart else { return }
        let ms = (now - start) * 1000
        lock.withLock { marks.append((name, ms)) }
    }

    /// Explore appeared for the first time. The next turn of the main queue
    /// runs after that frame was committed.
    @MainActor static func homeAppeared() {
        guard !launchLogged else { return }
        launchLogged = true
        mark("home.appear")
        DispatchQueue.main.async {
            mark("home.frame")
            let steps = lock.withLock { marks.map { "\($0.name)=\(Int($0.ms.rounded()))" }.joined(separator: " ") }
            log("launch \(steps) footprint=\(Int(footprint().current))MB")
            let defaults = UserDefaults.standard
            if let path = defaults.string(forKey: "GLPerfBench") {
                Task.detached(priority: .userInitiated) { await PerfBench.run(photoAt: path) }
            } else if let path = defaults.string(forKey: "GLPerfOpen") {
                Task { await openForTiming(path) }
            }
        }
    }

    /// The editor appeared: prints the time since `-GLPerfOpen` read the file.
    @MainActor static func editorAppeared() {
        guard let started = openStarted else { return }
        openStarted = nil
        let appear = (now - started) * 1000
        DispatchQueue.main.async {
            let frame = (now - started) * 1000
            log(String(format: "open-editor appear=%.0fms frame=%.0fms footprint=%.0fMB peak=%.0fMB",
                       appear, frame, footprint().current, footprint().peak))
        }
    }

    /// The same path as a photo dropped on the window or picked in Photos:
    /// decode and downsample off the main actor, then the editor cover.
    @MainActor private static func openForTiming(_ path: String) async {
        try? await Task.sleep(for: .seconds(2))
        guard let data = FileManager.default.contents(atPath: path), let app = GlowIntents.app else {
            log("open-editor: no photo at \(path)")
            return
        }
        openStarted = now
        guard let decoded = await PhotoDecoder.decode(data) else {
            log("open-editor: decode failed")
            return
        }
        app.openEditor(with: decoded.image)
    }

    /// Physical footprint (what iOS counts against the app), now and the
    /// highest so far, in MB.
    static func footprint() -> (current: Double, peak: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (Double(info.phys_footprint) / 1_048_576, Double(info.ledger_phys_footprint_peak) / 1_048_576)
    }

    static func log(_ line: String) {
        print("[perf] \(line)")
        // Scripts read stdout from a file, which is block-buffered.
        fflush(stdout)
    }
}

/// `-GLPerfBench`: the photo pipeline, timed on this device.
enum PerfBench {
    static func run(photoAt path: String) async {
        // Let launch work settle first.
        try? await Task.sleep(for: .seconds(2))
        guard let data = FileManager.default.contents(atPath: path) else {
            PerfProbe.log("bench: no photo at \(path)")
            return
        }
        PerfProbe.log("bench start file=\((path as NSString).lastPathComponent) kb=\(data.count / 1024) \(memory())")

        // Open: decode and downsample, as the picker and drag and drop do.
        var photo: UIImage?
        var openTimes: [Double] = []
        for _ in 0..<5 {
            let start = PerfProbe.now
            photo = await PhotoDecoder.decode(data)?.image
            openTimes.append(ms(since: start))
        }
        guard let photo else {
            PerfProbe.log("bench: decode failed")
            return
        }
        PerfProbe.log("open \(series(openTimes)) image=\(describe(photo)) \(memory())")

        // The editor's preview proxy (made on the main actor).
        let proxy = await MainActor.run { () -> UIImage in
            let start = PerfProbe.now
            let proxy = ImageUtilities.normalized(photo, maxLongEdge: 1200)
            PerfProbe.log("proxy1200 ms=\(fmt(ms(since: start))) main=\(Thread.isMainThread) image=\(describe(proxy))")
            return proxy
        }

        // One edit as she'd make it: preview an effect, apply it at full
        // size, then save to Photos (encode) and to My Works.
        let options = RetroEffect.Options(extra: true)
        let flow = timed {
            materialize(RetroEffect.disposable.apply(to: proxy, options: options))
            let applied = RetroEffect.disposable.apply(to: photo, options: options)
            _ = ImageExporter.encode(applied, sourceType: nil)
            if let name = try? ImageStore.save(applied, tag: ImageStore.Tag(operation: nil)) { ImageStore.delete(name) }
        }
        PerfProbe.log("edit-flow ms=\(fmt(flow)) \(memory())")

        // Effects: preview size (first and later renders) and full size.
        for effect in RetroEffect.allCases {
            let options = RetroEffect.Options(extra: effect.option?.isOnByDefault ?? true)
            let cold = timed { materialize(effect.apply(to: proxy, options: options)) }
            let preview = (0..<3).map { _ in timed { materialize(effect.apply(to: proxy, options: options)) } }
            let full = (0..<3).map { _ in timed { materialize(effect.apply(to: photo, options: options)) } }
            PerfProbe.log("effect \(effect.rawValue) previewFirst=\(fmt(cold)) preview=\(fmt(median(preview))) full=\(fmt(median(full)))")
        }

        // The Effects strip: every effect on a 240 px copy.
        let strip = timed {
            let source = ImageUtilities.normalized(photo, maxLongEdge: 240)
            for effect in RetroEffect.allCases {
                materialize(effect.apply(to: source, options: RetroEffect.Options(extra: effect.option?.isOnByDefault ?? true)))
            }
        }
        PerfProbe.log("strip ms=\(fmt(strip))")
        // The strip as the editor makes it now (side by side).
        let stripApp = timed { _ = RetroEffect.thumbnails(of: photo) }
        PerfProbe.log("strip-app ms=\(fmt(stripApp))")

        // What each producer hands to the encoders and the files they make,
        // one at a time. `-GLPerfReference save` keeps the pixels and
        // `compare` checks a later build against them.
        let reference = UserDefaults.standard.string(forKey: "GLPerfReference")
        var producers: [(String, () -> UIImage)] = [("photo", { photo })]
        for effect in RetroEffect.allCases {
            producers.append(("effect.\(effect.rawValue)", {
                effect.apply(to: photo, options: RetroEffect.Options(extra: effect.option?.isOnByDefault ?? true))
            }))
        }
        producers.append(("effect.throwback16+border", { RetroEffect.throwback16.apply(to: photo, options: RetroEffect.Options(extra: true)) }))
        producers.append(("effect.filmStill+subtitle", {
            RetroEffect.filmStill.apply(to: photo, options: RetroEffect.Options(extra: true, subtitle: "Golden hour"))
        }))
        producers.append(("adjust", {
            OnDeviceImageService.adjust(photo, with: AdjustmentSettings(brightness: 0.04, contrast: 1.1, saturation: 1.15, warmth: 0.3, vignette: 0.3))
        }))
        producers.append(("crop", {
            var straighten = CropGeometry()
            straighten.angle = 4
            return CropRenderer.render(photo, geometry: straighten, aspect: .original)
        }))
        producers.append(("hideFaces", { FaceHiding.render(photo, faces: [CGRect(x: 0.4, y: 0.3, width: 0.15, height: 0.2)], cover: .blur) }))
        producers.append(("overlays", { OverlayRenderer.flatten(photo, layers: [], doodle: nil) }))
        producers.append(("watermark", { Watermark.apply(to: photo) }))
        producers.append(("demoStamp", { DemoArt.stamp(photo) }))
        let payload = SharePayload(image: photo, original: proxy, operation: .magicEdit)
        for format in [ShareFormat.photo, .beforeAfter, .story, .cover, .strip] {
            producers.append(("share.\(format.rawValue)", { ShareRenderer.render(payload, format: format, branded: true, showPrompt: false) }))
        }
        producers.append(("share.photo+aiLabel", { ShareRenderer.render(payload, format: .photo, branded: false, showPrompt: false, aiLabel: true) }))
        producers.append(("booth", { BoothPrint.render([proxy, proxy, proxy, proxy], faces: [nil, nil, nil, nil], layout: .strip, caption: "", date: nil) }))
        producers.append(("cutout.opaque", { ImageFilters.ciImage(photo).flatMap { CutoutRenderer.render($0, opaque: true) } ?? photo }))
        producers.append(("proxy1200", { ImageUtilities.normalized(photo, maxLongEdge: 1200) }))
        producers.append(("thumb240", { ImageUtilities.normalized(photo, maxLongEdge: 240) }))
        // Real transparency (a cut-out) has to survive every step.
        let cutoutLike = transparentFixture(photo)
        producers.append(("cutoutLike", { cutoutLike }))
        producers.append(("effect.vhs.transparent", { RetroEffect.vhs.apply(to: cutoutLike, options: RetroEffect.Options(extra: true)) }))
        producers.append(("effect.instant.transparent", { RetroEffect.instant.apply(to: cutoutLike, options: RetroEffect.Options(extra: true)) }))
        producers.append(("effect.glamour.transparent", { RetroEffect.glamour.apply(to: cutoutLike, options: RetroEffect.Options(extra: true)) }))
        producers.append(("crop.transparent", {
            var straighten = CropGeometry()
            straighten.angle = 4
            return CropRenderer.render(cutoutLike, geometry: straighten, aspect: .original)
        }))
        producers.append(("thumb240.transparent", { ImageUtilities.normalized(cutoutLike, maxLongEdge: 240) }))
        for (name, produce) in producers {
            autoreleasepool {
                let made = timedValue(produce)
                let image = made.value
                let start = PerfProbe.now
                let encoded = ImageExporter.encode(image, sourceType: nil)
                let encodeMs = ms(since: start)
                let stored = timedValue { try? ImageStore.save(image, tag: ImageStore.Tag(operation: nil)) }
                let storedKB = stored.value.flatMap { file -> Int? in
                    defer { ImageStore.delete(file) }
                    return (try? FileManager.default.attributesOfItem(atPath: ImageStore.url(for: file).path)[.size] as? Int).map { $0 / 1024 }
                }
                let export = "\(encoded?.fileExtension ?? "-")/\(encoded.map { $0.data.count / 1024 } ?? 0)KB/\(fmt(encodeMs))ms"
                let library = "\(stored.value.map { ($0 as NSString).pathExtension } ?? "-")/\(storedKB ?? 0)KB/\(fmt(stored.ms))ms"
                var line = "output \(name) make=\(fmt(made.ms))ms \(describe(image)) export=\(export) library=\(library)"
                if let reference { line += " " + Reference.check(image, name: name, mode: reference) }
                PerfProbe.log(line)
            }
        }
        PerfProbe.log("outputs done \(memory())")

        // Vision at editor open: ideas (labels, faces, animals) and the
        // kindness check (faces).
        let insight = await timedAsync { await PhotoInsightsService.insight(for: photo) }
        let faces = await timedAsync { await FaceAnalysis.faceCount(in: photo) }
        PerfProbe.log("vision insight=\(fmt(insight.ms)) faceCount=\(fmt(faces.ms))")

        // What a save does on the main actor for the widgets.
        await MainActor.run {
            guard let app = GlowIntents.app else { return }
            let sync = timed { app.syncWidgets() }
            let latest = timed { GlowWidgetBridge.updateLatestImage(photo) }
            PerfProbe.log("main syncWidgets=\(fmt(sync)) widgetImage=\(fmt(latest))")
        }

        PerfProbe.log("bench done \(memory())")
    }

    // MARK: Helpers

    /// The photo inside an ellipse on a transparent canvas, like a cut-out.
    private static func transparentFixture(_ photo: UIImage) -> UIImage {
        let size = photo.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.15, dy: size.height * 0.1)).addClip()
            photo.draw(at: .zero)
        }
    }

    /// Reads the pixels, so a lazily rendered image is counted where it's made.
    private static func materialize(_ image: UIImage) {
        _ = image.cgImage?.dataProvider?.data
    }

    private static func memory() -> String {
        let memory = PerfProbe.footprint()
        return "footprint=\(Int(memory.current))MB peak=\(Int(memory.peak))MB"
    }

    private static func ms(since start: Double) -> Double { (PerfProbe.now - start) * 1000 }

    private static func timed(_ work: () -> Void) -> Double {
        let start = PerfProbe.now
        work()
        return ms(since: start)
    }

    private static func timedValue<T>(_ work: () -> T) -> (value: T, ms: Double) {
        let start = PerfProbe.now
        let value = work()
        return (value, ms(since: start))
    }

    private static func timedAsync<T>(_ work: () async -> T) async -> (value: T, ms: Double) {
        let start = PerfProbe.now
        let value = await work()
        return (value, ms(since: start))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    private static func series(_ values: [Double]) -> String {
        "first=\(fmt(values.first ?? 0)) median=\(fmt(median(Array(values.dropFirst()))))"
    }

    private static func fmt(_ value: Double) -> String { String(format: "%.1f", value) }

    static func describe(_ image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "no-cgimage" }
        let alpha: String
        switch cgImage.alphaInfo {
        case .none: alpha = "none"
        case .noneSkipFirst: alpha = "skipFirst"
        case .noneSkipLast: alpha = "skipLast"
        case .premultipliedFirst: alpha = "premulFirst"
        case .premultipliedLast: alpha = "premulLast"
        case .first: alpha = "first"
        case .last: alpha = "last"
        case .alphaOnly: alpha = "alphaOnly"
        @unknown default: alpha = "?"
        }
        let float = cgImage.bitmapInfo.contains(.floatComponents) ? "f" : ""
        let space = (cgImage.colorSpace?.name as String?)?.replacingOccurrences(of: "kCGColorSpace", with: "") ?? "?"
        return "\(cgImage.width)x\(cgImage.height) \(cgImage.bitsPerComponent)\(float)bpc alpha=\(alpha) space=\(space) mb=\(cgImage.bytesPerRow * cgImage.height / 1_048_576)"
    }

    /// Pixels of a bench output, kept between builds to show that a change
    /// didn't alter what she gets. Compared in 8-bit Display P3.
    private enum Reference {
        static func check(_ image: UIImage, name: String, mode: String) -> String {
            guard let pixels = canonical(image) else { return "ref=unreadable" }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perf-ref", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(name)-\(pixels.width)x\(pixels.height).rgba")
            if mode == "save" {
                return (try? pixels.data.write(to: file)) != nil ? "ref=saved" : "ref=save-failed"
            }
            guard let saved = try? Data(contentsOf: file) else { return "ref=missing(\(pixels.width)x\(pixels.height))" }
            guard saved.count == pixels.data.count else { return "ref=size-differs" }
            var maxDiff = 0
            var differing = 0
            var total = 0
            saved.withUnsafeBytes { old in
                pixels.data.withUnsafeBytes { new in
                    let a = old.bindMemory(to: UInt8.self)
                    let b = new.bindMemory(to: UInt8.self)
                    for index in 0..<a.count {
                        let diff = abs(Int(a[index]) - Int(b[index]))
                        total += diff
                        if diff > maxDiff { maxDiff = diff }
                        if diff > 2 { differing += 1 }
                    }
                }
            }
            return String(format: "ref=maxDiff:%d mean:%.3f over2:%.3f%%", maxDiff, Double(total) / Double(saved.count),
                          Double(differing) * 100 / Double(saved.count))
        }

        private static func canonical(_ image: UIImage) -> (data: Data, width: Int, height: Int)? {
            guard let cgImage = image.cgImage, let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
            let width = cgImage.width, height = cgImage.height
            var data = Data(count: width * height * 4)
            let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            return drawn ? (data, width, height) : nil
        }
    }
}
#endif
