#if DEBUG
import UIKit
import ImageIO
import AppCore

/// Deterministic app states for App Store / QA screenshots (DEBUG builds only).
/// Launch with `-GLScreenshotScene <scene>`; see .github/workflows/screenshots.yml.
///
/// With any scene, `-GLAssistStub YES` answers the server's writing help
/// (Create's "Inspire me" and "Make it magic", caption ideas, "Describe your
/// vibe") with canned text and no server or session (`fail`: an outage,
/// `blocked`: the server's policy); `-GLWriterAction inspire|magic` runs a
/// Create writer chip once; `-GLPro YES` makes her Pro.
enum ScreenshotScene: String, CaseIterable {
    case onboarding
    case home
    case create
    case results
    case edit
    /// Magic Edit with a prompt; `-GLEditorTool <tool>` opens another panel.
    /// Makeup Studio (`-GLEditorTool makeup`) takes `-GLMakeupPreset <id>`
    /// (a `MakeupStudio.presets` id) and `-GLMakeupCustomize lips|eyes|cheeks|extras|hair`;
    /// with `-GLAssistStub YES` it has "Describe your vibe", and
    /// `-GLMakeupVibe "<words>"` asks it once. Adjust (`-GLEditorTool adjust`)
    /// takes `-GLAdjustVibe dreamy|analog|moody|golden` and
    /// `-GLAdjustParameter <slider>` (an `AdjustmentParameter`, e.g. `tint`),
    /// and with `-GLAgeBand adult` `-GLSoftSkin <0…1>` (Soft skin's slider).
    /// Enhance (`-GLEditorTool enhance`) takes `-GLEnhanceMode <EnhanceOption>`
    /// (`quickFix` previews it) and `-GLEnhanceColor YES`; `-GLEnhanceHint YES`
    /// shows the one-time hint again. `-GLEditorPhoto <sample>` picks the photo.
    case editor
    case effects
    /// The editor's "Ideas for this photo" row on the demo landscape.
    case ideas
    case crop
    case result
    /// My Works; `-GLLibraryMissing YES` adds a tile whose file is gone, and
    /// `-GLKeepLibrary YES` shows the library on disk instead (migration QA).
    case library
    /// My Works in select mode with three creations picked;
    /// `-GLLibraryAction favorite|delete|duplicate` acts on them, `collage`
    /// opens the collage maker with them, `drag` drag-selects the first six
    /// tiles as a finger would, and `selectAll|clear` pick every tile or none.
    case librarySelect
    /// Recently deleted with days-left badges (and one past 30 days, which
    /// the launch purge removes); `-GLLibraryAction restore|purge`.
    case libraryTrash
    /// Create with an empty prompt and recent prompts to pick from;
    /// `-GLKeepPrompts YES` shows the stored prompts and draft instead.
    case recentPrompts
    /// The paywall; `-GLPaywallSource out_of_credits` says why it opened.
    /// `-GLAdRewardState available|loading|pending|capped` (also `offline`,
    /// `nofill`, `closed`, `delayed`) adds the rewarded-ad card in that state,
    /// here and in the credits sheet (`home -GLCreditsSheet YES`). With a Pro
    /// look or style (`-GLPaywallSource template_doll-box`, `style_fantasy`),
    /// `-GLUnlockState available|loading|pending|granted|capped|nocredits|nofill`
    /// (also `ready`, `closed`, `delayed`, `offline`, `unavailable`) adds the
    /// Pro try card. With any scene, `-GLAdPacing off` lets an interstitial
    /// follow every save (QA).
    case paywall
    /// The AI consent sheet; `-GLConsentScroll bottom` scrolls to the providers footnote.
    case consent
    /// Settings for a free member who never bought anything; `-GLPro YES`
    /// for a Pro member, `-GLPurchased YES` for one who bought credits.
    case settings
    /// The share composer; `-GLShareFormat <format>`, `-GLShareOnDevice YES`,
    /// and `-GLShareHideFaces YES` for a group from My Works with "Hide
    /// other faces" switched on.
    case share
    case invite
    case tour
    case legal
    /// A collection page; `-GLCategory <id>` picks it (default: the seasonal row).
    case collection
    /// The Pro out-of-credits sheet: empty, and 2 credits for 4 images.
    case outOfCredits
    case outOfCreditsMulti
    /// Best shot with sample pictures already sorted.
    case bestShot
    /// Settings › Feel good.
    case feelGood
    /// The age step shown once to people who finished onboarding before it.
    case age
    /// Hide faces on a group of cartoon figures, with every friend covered.
    case hideFaces
    /// Cut out with a fixture subject mask and a backdrop; `-GLCutoutRefine
    /// more|less` picks a refine brush (with two fixture strokes) and
    /// `-GLCutoutShadow YES` switches the shadow on. `-GLCutoutPhoto <sample>`
    /// cuts out a sample photo instead (Vision's masks from
    /// `-GLVisionFixtures`), and `-GLCutoutEdge <0…1>` sets the Edge slider.
    case cutout
    /// Erase with two brush strokes; `-GLBrushZoom <scale>` zooms the canvas.
    /// `-GLErasePhoto <sample>` erases a sample photo, and `-GLErasePick x,y`
    /// (normalized) turns on "Pick a person" and picks what's there instead.
    case erase
    /// Text & Stickers with text, stickers and a doodle on the demo photo;
    /// `-GLOverlayMode text|stickers|doodle` picks the panel (default stickers),
    /// `-GLOverlayEdit YES` (text) opens typing, `-GLOverlayApply YES` applies.
    case textStickers
    /// The video editor on a generated clip; `-GLVideoSeconds <n>` sets its
    /// length (default 8), `-GLVideoBroken YES` shows the can't-open state, and
    /// `-GLEffect`, `-GLCutSilences YES`, `-GLVideoAction save|share|close` act on it.
    /// Captions: `-GLCaptions fixture|auto|listening|nospeech|denied|…`,
    /// `-GLCaptionStyle`, `-GLCaptionPosition`, `-GLCaptionSize`,
    /// `-GLCaptionsEditor YES`, `-GLVideoSeek <s>` (paused there), and
    /// `-GLVideoSpeech YES` for a clip that talks, `-GLVideoLandscape YES` for a
    /// 16:9 one, and `-GLAutoEdit tiktok|reels|shorts` for Auto edit (more in
    /// `VideoEditorView.applyScreenshotOptions`).
    /// `-GLVideoClean YES` (marketing) drops the clip's dot and time stamp and
    /// makes `-GLCaptions fixture` speak the app's language.
    case video
    /// Retro Cam on the demo-art fixture (the simulator has no camera):
    /// `-GLEffect <effect>`, `-GLCameraMode booth`, `-GLCameraTimer 3|10`,
    /// `-GLCameraAction shoot|booth` to take a photo or run the booth,
    /// `-GLBoothLayout grid`, `-GLBoothCaption "…"` for the print,
    /// `-GLCameraReviewAction edit|share` to go on from the review, and
    /// `-GLCameraPermission ask|denied` for the permission screens.
    case camera
    /// The collage maker on synthetic photos: `-GLCollageStyle grid|mosaic|filmStrip|
    /// polaroid|scrapbook|moodboard`, `-GLCollageVariant <n>`, `-GLCollagePhotos <2…9>`,
    /// `-GLCollageFormat portrait|square|story|classic|carousel` (`-GLCollageSlides <2…5>`),
    /// `-GLCollageBackground <name>`, `-GLCollageCaption <text>`, `-GLCollagePanel
    /// layout|size|style|text`, `-GLCollageSelect <slot>`, `-GLCollageEmpty YES` (before
    /// photos), `-GLCollageAI YES` (the first photo is marked as AI-made) and
    /// `-GLCollageExport YES` (writes the export to tmp/glowlit-collage-qa).
    case collage
    /// "Your polls" over My Works with fixture polls (`-GLPollsFixture
    /// live|results|ended|takendown|empty`, default `results`; with any scene
    /// too, e.g. `library` for My Works' row). `-GLPollsCreate
    /// explainer|form|send|ready` shows Ask friends instead (`send` and
    /// `ready` send it to the fixtures), as do the `limit` and `blocked`
    /// fixtures, which show their message; `-GLPollsQuestion "<words>"` fills
    /// the question. `librarySelect -GLLibraryAction two|poll` picks two
    /// creations (and opens Ask friends), `share -GLShareFormat pick` shows
    /// the composer's Ask friends card.
    case polls
    /// Explore with the Retro Cam tip. Other scenes show no tips unless
    /// `-GLTip retroCam|collage|textStickers|ideas|captions` asks for one
    /// (`edit` for collage and textStickers, `ideas`, `video` for captions).
    /// With any scene, `-GLIntent <name>` performs a Siri/Shortcuts intent
    /// after launch (see `GlowIntents`).
    case tips

    static var current: ScreenshotScene? {
        UserDefaults.standard.string(forKey: "GLScreenshotScene").flatMap(ScreenshotScene.init(rawValue:))
    }

    /// `-GLForceLandscape YES` turns the window to landscape, since the
    /// simulator can't be rotated from the command line (iPad layout QA).
    @MainActor
    static func applyOrientation() {
        #if !targetEnvironment(macCatalyst)
        guard UserDefaults.standard.bool(forKey: "GLForceLandscape"),
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        #endif
    }
}

/// Synthetic images so screenshots never contain real people's photos.
enum ScreenshotFixtures {
    /// `-GLSamplePhotos <folder>`: marketing captures show the photos in that
    /// folder (made with AI: fictional adults, landscapes, pets; see
    /// docs/marketing/samples) instead of the drawings below. A missing file
    /// falls back to its drawing.
    static func sample(_ name: String) -> UIImage? {
        guard let folder = UserDefaults.standard.string(forKey: "GLSamplePhotos") else { return nil }
        for ext in ["jpg", "png"] {
            if let image = UIImage(contentsOfFile: (folder as NSString).appendingPathComponent("\(name).\(ext)")) {
                sampleLock.withLock { sampleNames[ObjectIdentifier(image)] = (name, image) }
                return image
            }
        }
        return nil
    }

    private static let sampleLock = NSLock()
    nonisolated(unsafe) private static var sampleNames: [ObjectIdentifier: (name: String, image: UIImage)] = [:]

    /// `-GLVisionFixtures <folder>`: Vision's masks for the sample photos,
    /// saved on a Mac (`<folder>/<sample>/person.png`, `people-1.png`…,
    /// `things-1.png`…, `humans.json`), because the Simulator can't run the
    /// segmentation models. `SubjectMasks` builds from them as it would from
    /// Vision's own.
    static func visionMasks(for image: UIImage, size: CGSize) -> VisionMasks? {
        guard let folder = UserDefaults.standard.string(forKey: "GLVisionFixtures"),
              let name = sampleLock.withLock({ sampleNames[ObjectIdentifier(image)]?.name }) else { return nil }
        let directory = URL(fileURLWithPath: folder).appendingPathComponent(name, isDirectory: true)
        let extent = CGRect(origin: .zero, size: size)
        func mask(_ file: String) -> CIImage? {
            guard let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(file) as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return Matte.scaled(CIImage(cgImage: cgImage, options: [.colorSpace: NSNull()]), to: extent)
        }
        var masks = VisionMasks()
        masks.person = mask("person.png")
        masks.people = (1...4).compactMap { mask("people-\($0).png") }
        masks.things = (1...8).compactMap { mask("things-\($0).png") }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("humans.json")),
           let boxes = try? JSONDecoder().decode([[Double]].self, from: data) {
            masks.humans = boxes.filter { $0.count == 4 }.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
        }
        return masks.person == nil && masks.things.isEmpty ? nil : masks
    }

    /// `-GLVisionFixtures <folder>`: a sample photo's face landmarks found on
    /// a Mac (`<folder>/<sample>/landmarks.json`, the format Retro Cam's
    /// fixture reads, plus optional `leftEyebrow`/`rightEyebrow`), for Soft skin.
    static func visionLandmarks(for image: UIImage) -> [FaceLandmarks]? {
        guard let folder = UserDefaults.standard.string(forKey: "GLVisionFixtures"),
              let name = sampleLock.withLock({ sampleNames[ObjectIdentifier(image)]?.name }) else { return nil }
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name, isDirectory: true).appendingPathComponent("landmarks.json")
        guard let data = try? Data(contentsOf: url),
              let faces = try? JSONDecoder().decode([[String: [[Double]]]].self, from: data), !faces.isEmpty else { return nil }
        return faces.map { face in
            func points(_ region: String) -> [FacePoint] {
                (face[region] ?? []).filter { $0.count == 2 }.map { FacePoint(x: $0[0], y: $0[1]) }
            }
            return FaceLandmarks(outerLips: points("outerLips"), innerLips: points("innerLips"), leftEye: points("leftEye"),
                                 rightEye: points("rightEye"), nose: points("nose"), faceContour: points("faceContour"),
                                 leftEyebrow: points("leftEyebrow"), rightEyebrow: points("rightEyebrow"))
        }
    }

    /// A flat, overcast lake landscape — the "before" photo.
    static let overcastLandscape = sample("lake-overcast") ?? landscape(golden: false)

    /// The same scene at golden hour — what "Golden hour light" produces.
    static let goldenLandscape = sample("lake-golden") ?? landscape(golden: true)

    /// Her photo and what Magic Edit ("Give me pink hair") and Makeup Studio
    /// (Soft Glam) made of it; the drawn lake without sample photos.
    static let portraitBefore = sample("portrait-a") ?? overcastLandscape
    static let portraitPinkHair = sample("portrait-a-pink-hair") ?? goldenLandscape
    static let portraitSoftGlam = sample("portrait-a-soft-glam") ?? goldenLandscape
    /// The Magic Edit editor ("Golden hour light") and the Effects strip.
    static let editorPhoto = sample("portrait-b") ?? overcastLandscape
    static let effectsPhoto = sample("portrait-c") ?? goldenLandscape
    static let beachPhoto = sample("beach-sunset") ?? goldenLandscape

    /// What My Works, the collage maker and Best shot show with sample photos.
    static var samplePool: [UIImage]? {
        let names = ["portrait-a-pink-hair", "create-1", "puppy", "friends", "latte-flowers", "portrait-b-golden",
                     "beach-sunset", "create-2", "city-night", "portrait-c", "lake-golden", "create-3", "portrait-a-soft-glam"]
        let images = names.compactMap(sample)
        return images.count >= 6 ? images : nil
    }

    /// Create's results for `createPrompt`, or drawn art.
    static var createResults: [UIImage] {
        let images = ["create-1", "create-2", "create-3"].compactMap(sample)
        return images.count == 3 ? images : generatedArt(count: 3)
    }

    static let createPrompt = "A dreamy pastel bedroom with fairy lights and a canopy bed at sunset"

    static let recentPrompts = [
        "A kawaii strawberry cat in a teacup",
        createPrompt,
        "My dog as a tiny astronaut, watercolor",
        "Retro mall photo booth with pink neon",
        "A cozy reading nook on a rainy day",
    ]

    static func generatedArt(count: Int) -> [UIImage] {
        let styles = ["pastel", "kawaii", "anime", "watercolor", "fantasy", "neon"].map { StyleCatalog.style(id: $0) }
        return (0..<count).map { index in
            let style = styles[index % styles.count]
            return DemoArt.render(prompt: "\(createPrompt) \(index)", style: style, size: AspectRatio.portrait.pixelSize(longEdge: 1024), variant: index, stamped: false)
        }
    }

    private static func landscape(golden: Bool) -> UIImage {
        let size = CGSize(width: 1200, height: 1500)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let horizon = size.height * 0.58

            // Sky
            let skyColors: [UIColor] = golden
                ? [UIColor(red: 0.16, green: 0.20, blue: 0.40, alpha: 1), UIColor(red: 0.98, green: 0.55, blue: 0.30, alpha: 1), UIColor(red: 1.0, green: 0.80, blue: 0.45, alpha: 1)]
                : [UIColor(red: 0.55, green: 0.60, blue: 0.66, alpha: 1), UIColor(red: 0.70, green: 0.73, blue: 0.76, alpha: 1), UIColor(red: 0.78, green: 0.80, blue: 0.82, alpha: 1)]
            if let sky = CGGradient(colorsSpace: space, colors: skyColors.map(\.cgColor) as CFArray, locations: [0, 0.7, 1]) {
                cg.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: horizon), options: [])
            }

            // Sun glow
            if golden {
                let sun = CGPoint(x: size.width * 0.62, y: horizon - 70)
                let glowColors = [UIColor(red: 1, green: 0.93, blue: 0.70, alpha: 1).cgColor, UIColor(red: 1, green: 0.62, blue: 0.30, alpha: 0).cgColor] as CFArray
                if let glow = CGGradient(colorsSpace: space, colors: glowColors, locations: [0, 1]) {
                    cg.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 520, options: [])
                }
                UIColor(red: 1, green: 0.96, blue: 0.84, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: sun.x - 60, y: sun.y - 60, width: 120, height: 120))
            }

            // Mountains (far → near)
            let ranges: [(CGFloat, [CGFloat], UIColor, UIColor)] = [
                (0.40, [0.0, 0.42, 0.20, 0.30, 0.38, 0.18, 0.62, 0.33, 0.85, 0.22, 1.0, 0.36],
                 UIColor(red: 0.45, green: 0.36, blue: 0.48, alpha: 1), UIColor(red: 0.62, green: 0.66, blue: 0.70, alpha: 1)),
                (0.50, [0.0, 0.52, 0.15, 0.40, 0.33, 0.48, 0.55, 0.34, 0.78, 0.46, 1.0, 0.41],
                 UIColor(red: 0.28, green: 0.20, blue: 0.30, alpha: 1), UIColor(red: 0.46, green: 0.50, blue: 0.54, alpha: 1)),
            ]
            for (_, points, goldenColor, flatColor) in ranges {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: horizon))
                for index in stride(from: 0, to: points.count, by: 2) {
                    path.addLine(to: CGPoint(x: points[index] * size.width, y: points[index + 1] * size.height))
                }
                path.addLine(to: CGPoint(x: size.width, y: horizon))
                path.close()
                (golden ? goldenColor : flatColor).setFill()
                path.fill()
            }

            // Lake with reflection
            let lakeColors: [UIColor] = golden
                ? [UIColor(red: 0.95, green: 0.58, blue: 0.34, alpha: 1), UIColor(red: 0.20, green: 0.17, blue: 0.30, alpha: 1)]
                : [UIColor(red: 0.62, green: 0.66, blue: 0.70, alpha: 1), UIColor(red: 0.32, green: 0.36, blue: 0.40, alpha: 1)]
            if let lake = CGGradient(colorsSpace: space, colors: lakeColors.map(\.cgColor) as CFArray, locations: [0, 1]) {
                cg.saveGState()
                cg.clip(to: CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon))
                cg.drawLinearGradient(lake, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: size.height), options: [])
                cg.restoreGState()
            }
            // Ripples
            (golden ? UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.35) : UIColor(white: 0.85, alpha: 0.2)).setFill()
            for row in 0..<14 {
                let y = horizon + 30 + CGFloat(row) * 42
                let width = CGFloat(220 - row * 9)
                cg.fill(CGRect(x: size.width * 0.62 - width / 2, y: y, width: width, height: 4))
            }

            // Foreground shore
            let shore = UIBezierPath()
            shore.move(to: CGPoint(x: 0, y: size.height * 0.86))
            shore.addCurve(to: CGPoint(x: size.width, y: size.height * 0.93),
                           controlPoint1: CGPoint(x: size.width * 0.3, y: size.height * 0.80),
                           controlPoint2: CGPoint(x: size.width * 0.7, y: size.height * 0.98))
            shore.addLine(to: CGPoint(x: size.width, y: size.height))
            shore.addLine(to: CGPoint(x: 0, y: size.height))
            shore.close()
            (golden ? UIColor(red: 0.12, green: 0.09, blue: 0.12, alpha: 1) : UIColor(red: 0.20, green: 0.22, blue: 0.24, alpha: 1)).setFill()
            shore.fill()
        }
    }

    // MARK: Hide faces and Cut out

    /// Head circles (centre x, centre y, radius as a share of the width) for
    /// a group of cartoon figures; the second one is the largest ("me").
    private static let groupHeads: [(CGFloat, CGFloat, CGFloat)] = [(0.17, 0.55, 0.065), (0.40, 0.47, 0.095), (0.63, 0.53, 0.07), (0.85, 0.57, 0.055)]

    /// Cartoon figures by the lake: Vision finds no real faces in them, so
    /// the scene uses `groupFaces` instead.
    static let groupPhoto = sample("friends") ?? figures(heads: groupHeads, pet: false)

    /// Face boxes for `groupPhoto`, normalized with a top-left origin.
    static var groupFaces: [CGRect] {
        groupHeads.map { x, y, r in
            let height = r * 1200 / 1500
            return CGRect(x: x - r, y: y - height, width: r * 2, height: height * 2)
        }
    }

    /// Erase: a wide stroke over the far shore and a fine one, as if made
    /// zoomed in, along a ripple.
    static let eraseStrokes = [
        MaskStroke(points: [CGPoint(x: 0.12, y: 0.5), CGPoint(x: 0.22, y: 0.47), CGPoint(x: 0.3, y: 0.5)], width: 0.07),
        MaskStroke(points: [CGPoint(x: 0.53, y: 0.66), CGPoint(x: 0.6, y: 0.655), CGPoint(x: 0.68, y: 0.66)], width: 0.02),
    ]

    /// Cut out's refine brush on `cutoutPhoto`: the shore brushed back in
    /// under her, and the pet's ears brushed away.
    static let refineStrokes = [
        CutoutRefineStroke(stroke: MaskStroke(points: [CGPoint(x: 0.12, y: 0.9), CGPoint(x: 0.34, y: 0.92), CGPoint(x: 0.55, y: 0.9)], width: 0.06),
                           keeps: true),
        CutoutRefineStroke(stroke: MaskStroke(points: [CGPoint(x: 0.76, y: 0.6), CGPoint(x: 0.84, y: 0.6)], width: 0.06), keeps: false),
    ]

    private static let cutoutHeads: [(CGFloat, CGFloat, CGFloat)] = [(0.34, 0.42, 0.11)]

    /// A cartoon person and a pet for the Cut out scene.
    static let cutoutPhoto = figures(heads: cutoutHeads, pet: true)

    /// A stand-in for Vision's subject lifting on `cutoutPhoto`: the same
    /// shapes as label map and masks.
    static func cutoutAnalysis(for image: UIImage) -> SubjectMasks? {
        guard let source = image.cgImage else { return nil }
        let size = CGSize(width: source.width, height: source.height)
        let labelWidth = 240, labelHeight = Int((240 * size.height / size.width).rounded())
        guard let labelContext = CGContext(
            data: nil, width: labelWidth, height: labelHeight, bitsPerComponent: 8, bytesPerRow: labelWidth,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        labelContext.setShouldAntialias(false)
        // Top-left origin, like Vision's label map.
        labelContext.translateBy(x: 0, y: CGFloat(labelHeight))
        labelContext.scaleBy(x: 1, y: -1)
        let labelScale = CGFloat(labelWidth) / size.width
        for (index, path) in figurePaths(heads: cutoutHeads, pet: true, size: size).enumerated() {
            labelContext.saveGState()
            labelContext.scaleBy(x: labelScale, y: labelScale)
            labelContext.addPath(path.cgPath)
            labelContext.setFillColor(gray: CGFloat(index + 1) / 255, alpha: 1)
            labelContext.fillPath()
            labelContext.restoreGState()
        }
        guard let data = labelContext.data else { return nil }
        let labels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: labelWidth * labelHeight))
        return SubjectMasks(source: source, labels: labels, labelWidth: labelWidth, labelHeight: labelHeight) { ids in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let mask = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIColor.black.setFill()
                UIRectFill(CGRect(origin: .zero, size: size))
                UIColor.white.setFill()
                for (index, path) in figurePaths(heads: cutoutHeads, pet: true, size: size).enumerated() where ids.contains(index + 1) {
                    path.fill()
                }
            }
            return mask.cgImage.map { CIImage(cgImage: $0) } ?? CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }
    }

    private static func figures(heads: [(CGFloat, CGFloat, CGFloat)], pet: Bool) -> UIImage {
        let base = goldenLandscape
        let size = base.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let colors: [UIColor] = [.auraLilac, .auraPink, .auraMint, .auraPeach, .auraButter]
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            base.draw(at: .zero)
            for (index, path) in figurePaths(heads: heads, pet: pet, size: size).enumerated() {
                colors[index % colors.count].setFill()
                path.fill()
                UIColor.white.withAlphaComponent(0.8).setStroke()
                path.lineWidth = 3
                path.stroke()
            }
        }
    }

    /// One path per subject: a head on a rounded body, and optionally a pet.
    private static func figurePaths(heads: [(CGFloat, CGFloat, CGFloat)], pet: Bool, size: CGSize) -> [UIBezierPath] {
        var paths = heads.map { x, y, r -> UIBezierPath in
            let radius = r * size.width
            let center = CGPoint(x: x * size.width, y: y * size.height)
            let path = UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            path.append(UIBezierPath(
                roundedRect: CGRect(x: center.x - radius * 1.5, y: center.y + radius * 1.05, width: radius * 3, height: size.height - center.y),
                cornerRadius: radius
            ))
            return path
        }
        if pet {
            let body = CGRect(x: size.width * 0.6, y: size.height * 0.7, width: size.width * 0.3, height: size.height * 0.16)
            let path = UIBezierPath(ovalIn: body)
            let head = CGRect(x: body.maxX - body.width * 0.35, y: body.minY - body.height * 0.55, width: body.width * 0.4, height: body.width * 0.4)
            path.append(UIBezierPath(ovalIn: head))
            for dx in [0.08, 0.62] as [CGFloat] {
                path.append(UIBezierPath(ovalIn: CGRect(x: head.minX + head.width * dx, y: head.minY - head.height * 0.18, width: head.width * 0.3, height: head.height * 0.45)))
            }
            paths.append(path)
        }
        return paths
    }
}
#endif
