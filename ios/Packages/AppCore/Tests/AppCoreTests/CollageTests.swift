import XCTest
@testable import AppCore

final class CollageLayoutTests: XCTestCase {
    private let formats: [CollageFormat] = CollageFormat.presets + CollageFormat.slideRange.map { .carousel(slides: $0) }

    private func layouts(_ style: CollageStyle, counts: ClosedRange<Int> = 2...9, caption: Bool = false) -> [(CollageFormat, Int, Int, CollageLayout)] {
        var result: [(CollageFormat, Int, Int, CollageLayout)] = []
        for format in formats {
            for count in counts {
                for variant in 0..<style.variantCount(for: count) {
                    let aspects = (0..<count).map { [0.75, 1.333, 1, 0.5625][$0 % 4] }
                    result.append((format, count, variant, CollageLayout.make(style: style, count: count, format: format, variant: variant,
                                                                              photoAspects: aspects, caption: caption)))
                }
            }
        }
        return result
    }

    /// The corners of a slot's frame after its tilt, in canvas units.
    private func corners(of rect: CollageRect, rotation: Double, aspect: Double) -> [(x: Double, y: Double)] {
        let cx = rect.midX * aspect, cy = rect.midY
        let radians = rotation * .pi / 180
        return [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { sx, sy in
            let dx = sx * rect.width * aspect / 2, dy = sy * rect.height / 2
            return (cx + dx * cos(radians) - dy * sin(radians), cy + dx * sin(radians) + dy * cos(radians))
        }
    }

    private func overlapArea(_ a: CollageRect, _ b: CollageRect) -> Double {
        max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)) * max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }

    func testEveryStyleGivesOneSlotPerPhotoWithTheWindowInsideItsFrame() {
        for style in CollageStyle.allCases {
            for (format, count, variant, layout) in layouts(style) {
                let label = "\(style) \(format) \(count) v\(variant)"
                XCTAssertEqual(layout.slots.count, count, label)
                for slot in layout.slots {
                    XCTAssertGreaterThan(slot.window.width, 0.01, label)
                    XCTAssertGreaterThan(slot.window.height, 0.01, label)
                    XCTAssertGreaterThanOrEqual(slot.window.minX, slot.frame.minX - 1e-9, label)
                    XCTAssertGreaterThanOrEqual(slot.window.minY, slot.frame.minY - 1e-9, label)
                    XCTAssertLessThanOrEqual(slot.window.maxX, slot.frame.maxX + 1e-9, label)
                    XCTAssertLessThanOrEqual(slot.window.maxY, slot.frame.maxY + 1e-9, label)
                }
            }
        }
    }

    func testEverythingStaysOnTheCanvasAfterTilting() {
        for style in CollageStyle.allCases {
            for (format, count, variant, layout) in layouts(style) {
                let aspect = format.widthOverHeight
                for slot in layout.slots {
                    for corner in corners(of: slot.frame, rotation: slot.rotation, aspect: aspect) {
                        XCTAssert((-1e-9...(aspect + 1e-9)).contains(corner.x), "\(style) \(format) \(count) v\(variant): x \(corner.x)")
                        XCTAssert((-1e-9...(1 + 1e-9)).contains(corner.y), "\(style) \(format) \(count) v\(variant): y \(corner.y)")
                    }
                }
            }
        }
    }

    func testFlatLayoutsNeverOverlap() {
        for style in [CollageStyle.grid, .mosaic, .moodboard] {
            for (format, count, variant, layout) in layouts(style) {
                for (index, slot) in layout.slots.enumerated() {
                    XCTAssertEqual(slot.rotation, 0)
                    for other in layout.slots[(index + 1)...] {
                        XCTAssertLessThan(overlapArea(slot.frame, other.frame), 1e-9, "\(style) \(format) \(count) v\(variant)")
                    }
                }
                for decoration in layout.decorations where decoration.kind == .palette {
                    for slot in layout.slots {
                        XCTAssertLessThan(overlapArea(slot.frame, decoration.frame), 1e-9, "palette over a photo")
                    }
                }
            }
        }
    }

    func testNineAndFourMakeEvenGrids() {
        let nine = CollageLayout.make(style: .grid, count: 9, format: .square, spacing: 0.4)
        let rows = Set(nine.slots.map { ($0.frame.minY * 1000).rounded() })
        let columns = Set(nine.slots.map { ($0.frame.minX * 1000).rounded() })
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(columns.count, 3)
        for slot in nine.slots {
            XCTAssertEqual(slot.frame.width, nine.slots[0].frame.width, accuracy: 1e-9)
            XCTAssertEqual(slot.frame.height, nine.slots[0].frame.height, accuracy: 1e-9)
        }
        // Photo order reads left to right, top to bottom.
        XCTAssertLessThan(nine.slots[0].frame.minX, nine.slots[1].frame.minX)
        XCTAssertLessThan(nine.slots[2].frame.minY, nine.slots[3].frame.minY)

        let four = CollageLayout.make(style: .grid, count: 4, format: .portrait)
        XCTAssertEqual(Set(four.slots.map { ($0.frame.minY * 1000).rounded() }).count, 2)
        XCTAssertEqual(Set(four.slots.map { ($0.frame.minX * 1000).rounded() }).count, 2)
    }

    func testSpacingSetsGapsAndMargins() {
        let spaced = CollageLayout.make(style: .grid, count: 4, format: .square, spacing: 1)
        // 5% of the short edge between cells and around them.
        XCTAssertEqual(spaced.slots[0].frame.minX, 0.05, accuracy: 1e-9)
        XCTAssertEqual(spaced.slots[1].frame.minX - spaced.slots[0].frame.maxX, 0.05, accuracy: 1e-9)
        XCTAssertEqual(spaced.slots[2].frame.minY - spaced.slots[0].frame.maxY, 0.05, accuracy: 1e-9)

        let seamless = CollageLayout.make(style: .grid, count: 4, format: .square, spacing: 0)
        XCTAssertEqual(seamless.slots[0].frame.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(seamless.slots[3].frame.maxX, 1, accuracy: 1e-9)
        XCTAssertEqual(seamless.slots[3].frame.maxY, 1, accuracy: 1e-9)
    }

    func testGridPicksCellsThatCropLeast() {
        // Two landscape photos on a story canvas stack; two tall ones sit side by side on a square.
        let stacked = CollageLayout.make(style: .grid, count: 2, format: .story, photoAspects: [1.5, 1.5])
        XCTAssertEqual(stacked.slots[0].frame.minX, stacked.slots[1].frame.minX, accuracy: 1e-9)
        let sideBySide = CollageLayout.make(style: .grid, count: 2, format: .square, photoAspects: [0.5, 0.5])
        XCTAssertEqual(sideBySide.slots[0].frame.minY, sideBySide.slots[1].frame.minY, accuracy: 1e-9)
        // Variants are different arrangements.
        let first = CollageLayout.make(style: .grid, count: 5, format: .portrait, variant: 0)
        let second = CollageLayout.make(style: .grid, count: 5, format: .portrait, variant: 1)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(CollageLayout.make(style: .grid, count: 5, format: .portrait, variant: 3), first, "variants wrap")
    }

    func testMosaicHeroIsTheBiggestAndCanSwapSides() {
        for count in 2...9 {
            for format in formats {
                let layout = CollageLayout.make(style: .mosaic, count: count, format: format)
                let areas = layout.slots.map { $0.frame.width * $0.frame.height }
                XCTAssertEqual(areas.firstIndex(of: areas.max()!), 0, "\(format) \(count)")
            }
        }
        let first = CollageLayout.make(style: .mosaic, count: 5, format: .portrait, variant: 0)
        let last = CollageLayout.make(style: .mosaic, count: 5, format: .portrait, variant: 1)
        XCTAssertLessThan(first.slots[0].frame.minY, last.slots[0].frame.minY)
    }

    func testMosaicLShapeForSixAndEight() {
        // Hero first, hero last, the L (6 and 8 only), then center stage (3 or more).
        XCTAssertEqual(CollageStyle.mosaic.variantCount(for: 6), 4)
        XCTAssertEqual(CollageStyle.mosaic.variantCount(for: 5), 3)
        XCTAssertEqual(CollageStyle.mosaic.variantCount(for: 2), 2)
        let six = CollageLayout.make(style: .mosaic, count: 6, format: .square, spacing: 0)
        XCTAssertEqual(six.slots[0].frame.width, 0.56, accuracy: 1e-9, "the hero beside the rest")
        XCTAssertEqual(six.slots[0].frame.height, 1, accuracy: 1e-9)
        let six2 = CollageLayout.make(style: .mosaic, count: 6, format: .square, spacing: 0, variant: 2)
        XCTAssertEqual(six2.slots[0].frame.height, 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(six2.slots[0].frame.width, 2.0 / 3, accuracy: 1e-9)
        for slot in six2.slots.dropFirst() {
            XCTAssertEqual(slot.frame.width, 1.0 / 3, accuracy: 1e-9)
            XCTAssertEqual(slot.frame.height, 1.0 / 3, accuracy: 1e-9)
        }
    }

    func testMosaicCenterStageKeepsTheHeroInTheMiddle() {
        for format in formats {
            for count in 3...9 {
                let variant = CollageStyle.mosaic.variantCount(for: count) - 1
                let layout = CollageLayout.make(style: .mosaic, count: count, format: format, variant: variant)
                let label = "\(format) \(count)"
                let hero = layout.slots[0].frame
                let areas = layout.slots.map { $0.frame.width * $0.frame.height }
                XCTAssertEqual(areas.firstIndex(of: areas.max()!), 0, "the hero is the biggest: \(label)")
                XCTAssertTrue(abs(hero.midX - 0.5) < 1e-9 || abs(hero.midY - 0.5) < 1e-9, "centred: \(label)")
                // The others split between both sides of it, along one axis.
                let others = layout.slots.dropFirst().map(\.frame)
                let sideBySide = (others.filter { $0.maxX <= hero.minX + 1e-9 }.count, others.filter { $0.minX >= hero.maxX - 1e-9 }.count)
                let stacked = (others.filter { $0.maxY <= hero.minY + 1e-9 }.count, others.filter { $0.minY >= hero.maxY - 1e-9 }.count)
                let split = sideBySide.0 + sideBySide.1 == count - 1 ? sideBySide : stacked
                XCTAssertEqual(split.0 + split.1, count - 1, label)
                XCTAssertEqual(split.0, (count - 1) / 2, label)
            }
        }
        XCTAssertNotEqual(CollageLayout.make(style: .mosaic, count: 5, format: .portrait, variant: 2),
                          CollageLayout.make(style: .mosaic, count: 5, format: .portrait, variant: 0))
    }

    func testFeaturedMoodboardLeadsWithTheFirstPhoto() {
        XCTAssertEqual(CollageStyle.moodboard.variantCount(for: 2), 2)
        XCTAssertEqual(CollageStyle.moodboard.variantCount(for: 3), 3)
        for format in formats {
            for count in 3...9 {
                let layout = CollageLayout.make(style: .moodboard, count: count, format: format, variant: 2)
                let label = "\(format) \(count)"
                let hero = layout.slots[0].frame
                let others = layout.slots.dropFirst()
                if format.isCarousel {
                    // Down the left, the board beside it.
                    XCTAssertTrue(others.allSatisfy { $0.frame.minX >= hero.maxX - 1e-9 }, label)
                    XCTAssertEqual(hero.height, others.map(\.frame.maxY).max()! - others.map(\.frame.minY).min()!, accuracy: 1e-9, label)
                } else {
                    // Across the top, as wide as the board under it.
                    XCTAssertTrue(others.allSatisfy { $0.frame.minY >= hero.maxY - 1e-9 }, label)
                    XCTAssertEqual(hero.minX, others.map(\.frame.minX).min()!, accuracy: 1e-9, label)
                    XCTAssertEqual(hero.maxX, others.map(\.frame.maxX).max()!, accuracy: 1e-9, label)
                }
                XCTAssertEqual(layout.decorations.filter { $0.kind == .palette }.count, 1, label)
            }
        }
    }

    func testGarlandHangsEveryPrintFromARibbon() {
        for format in formats {
            for count in 2...9 {
                let variant = CollageStyle.polaroid.variantCount(for: count) - 1
                let layout = CollageLayout.make(style: .polaroid, count: count, format: format, variant: variant)
                let label = "\(format) \(count)"
                // Ribbons run across the whole canvas; every print has a pin.
                let ribbons = layout.decorations.filter { abs($0.frame.width - 1) < 1e-9 }
                XCTAssertFalse(ribbons.isEmpty, label)
                XCTAssertEqual(layout.decorations.count - ribbons.count, count, "one pin per print: \(label)")
                XCTAssert(layout.slots.contains { $0.rotation < 0 } && layout.slots.contains { $0.rotation > 0 }, "they swing both ways: \(label)")
                for slot in layout.slots {
                    XCTAssertLessThanOrEqual(abs(slot.rotation), 5.5 + 1e-9, label)
                    let top = slot.window.minY - slot.frame.minY
                    XCTAssertGreaterThan(slot.frame.maxY - slot.window.maxY, top * 2, "the instant print's thick bottom border")
                    // The print hangs from a ribbon: its top edge is close under one.
                    let hangs = ribbons.contains { ribbon in
                        abs(ribbon.frame.midY - slot.frame.minY) < slot.frame.height * 0.12
                    }
                    XCTAssertTrue(hangs, label)
                }
            }
        }
    }

    func testTidyScrapbookLinesThePrintsUp() {
        let variant = CollageStyle.scrapbook.variantCount(for: 6) - 1
        let layout = CollageLayout.make(style: .scrapbook, count: 6, format: .portrait, variant: variant)
        XCTAssertTrue(layout.slots.allSatisfy { abs($0.rotation) <= 2.5 + 1e-9 })
        let rows = Set(layout.slots.map { ($0.frame.midY * 1e6).rounded() })
        XCTAssertLessThan(rows.count, 6, "prints in a row share their centre line")
        let tapes = layout.decorations.filter { if case .tape = $0.kind { return true } else { return false } }
        XCTAssertEqual(tapes.count, 4 + 2 * 2, "every print is still taped down")
        XCTAssertNotEqual(layout, CollageLayout.make(style: .scrapbook, count: 6, format: .portrait, variant: 0))
    }

    func testFilmStripsRunDownTallCanvasesAndAcrossCarousels() {
        let tall = CollageLayout.make(style: .filmStrip, count: 9, format: .portrait)
        XCTAssertEqual(tall.strips.count, 3)
        for strip in tall.strips {
            XCTAssertGreaterThan(strip.frame.height, strip.frame.width)
            XCTAssertFalse(strip.holes.isEmpty)
            for hole in strip.holes {
                XCTAssert(hole.minX >= 0 && hole.maxX <= 1 && hole.minY >= 0 && hole.maxY <= 1)
            }
        }
        // Frames follow each other down the first strip.
        XCTAssertLessThan(tall.slots[0].frame.midY, tall.slots[1].frame.midY)
        XCTAssertLessThan(tall.slots[1].frame.midY, tall.slots[2].frame.midY)

        let wide = CollageLayout.make(style: .filmStrip, count: 6, format: .carousel(slides: 3))
        XCTAssertEqual(wide.strips.count, 1)
        XCTAssertGreaterThan(wide.strips[0].frame.width * 2.4, wide.strips[0].frame.height)
        XCTAssertGreaterThan(wide.strips[0].frame.width, 2.0 / 3, "the strip crosses the seams")
        XCTAssertLessThan(wide.slots[0].frame.midX, wide.slots[5].frame.midX)

        let turned = CollageLayout.make(style: .filmStrip, count: 6, format: .carousel(slides: 3), variant: 1)
        XCTAssertGreaterThan(turned.strips[0].frame.height, turned.strips[0].frame.width * 2.4)
    }

    func testScatterIsRepeatableAndShuffles() {
        for style in [CollageStyle.polaroid, .scrapbook] {
            let a = CollageLayout.make(style: style, count: 6, format: .portrait, variant: 2)
            let b = CollageLayout.make(style: style, count: 6, format: .portrait, variant: 2)
            let c = CollageLayout.make(style: style, count: 6, format: .portrait, variant: 3)
            XCTAssertEqual(a, b, "the preview and the export must match")
            XCTAssertNotEqual(a, c)
            XCTAssert(a.slots.contains { $0.rotation < 0 } && a.slots.contains { $0.rotation > 0 }, "tilts alternate")
            for slot in a.slots {
                XCTAssertLessThanOrEqual(abs(slot.rotation), 9)
            }
        }
    }

    func testPolaroidsHaveTheThickBottomBorder() {
        let layout = CollageLayout.make(style: .polaroid, count: 3, format: .square)
        for slot in layout.slots {
            let top = slot.window.minY - slot.frame.minY
            let bottom = slot.frame.maxY - slot.window.maxY
            XCTAssertGreaterThan(bottom, top * 2)
        }
    }

    func testScrapbookTapesEveryPrintAndMoodboardSamplesColours() {
        let scrapbook = CollageLayout.make(style: .scrapbook, count: 6, format: .portrait)
        let tapes = scrapbook.decorations.filter { if case .tape = $0.kind { return true } else { return false } }
        let stickers = scrapbook.decorations.filter { if case .sticker = $0.kind { return true } else { return false } }
        XCTAssertEqual(tapes.count, 4 + 2 * 2, "one tape, or two on every third print")
        XCTAssertEqual(stickers.count, 3)

        let moodboard = CollageLayout.make(style: .moodboard, count: 7, format: .portrait)
        XCTAssertEqual(moodboard.decorations.filter { $0.kind == .palette }.count, 1)
        let swatches = moodboard.decorations.compactMap { decoration -> Int? in
            if case .swatch(let photo) = decoration.kind { return photo }
            return nil
        }
        XCTAssertEqual(swatches, [0, 1, 2, 3, 4])
    }

    func testCaptionKeepsTheBottomBandFree() {
        for style in [CollageStyle.grid, .mosaic, .moodboard, .filmStrip] {
            for (format, count, variant, layout) in layouts(style, counts: 2...9, caption: true) {
                guard let caption = layout.captionFrame else { return XCTFail("no caption band") }
                for slot in layout.slots where slot.rotation == 0 {
                    XCTAssertLessThanOrEqual(slot.frame.maxY, caption.minY + 1e-9, "\(style) \(format) \(count) v\(variant)")
                }
            }
        }
        let carousel = CollageLayout.make(style: .grid, count: 6, format: .carousel(slides: 3), caption: true)
        XCTAssertLessThanOrEqual(carousel.captionFrame!.maxX, 1.0 / 3, "the caption sits on the first slide")
        XCTAssertNil(CollageLayout.make(style: .grid, count: 6, format: .portrait).captionFrame)
    }

    func testHitTestingFollowsTiltAndStacking() {
        let grid = CollageLayout.make(style: .grid, count: 4, format: .square, spacing: 0)
        XCTAssertEqual(grid.slotIndex(atX: 0.25, y: 0.25, aspect: 1), 0)
        XCTAssertEqual(grid.slotIndex(atX: 0.75, y: 0.75, aspect: 1), 3)

        let tilted = CollageLayout(slots: [
            CollageSlot(frame: CollageRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), window: CollageRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
            CollageSlot(frame: CollageRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), window: CollageRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                        rotation: 45),
        ])
        XCTAssertEqual(tilted.slotIndex(atX: 0.5, y: 0.5, aspect: 1), 1, "the top card wins")
        // Just inside the unrotated corner, but outside the card once it's turned 45°.
        XCTAssertEqual(tilted.slotIndex(atX: 0.41, y: 0.41, aspect: 1), 0)
        XCTAssertNil(tilted.slotIndex(atX: 0.05, y: 0.05, aspect: 1))
    }
}

final class CollageCropTests: XCTestCase {
    private let photo = 1.5   // landscape
    private let window = 0.75 // portrait cell

    func testFillCoversTheWindow() {
        let rect = CollageCrop.fill.photoRect(photoAspect: photo, windowAspect: window)
        XCTAssertEqual(rect.height, 1, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 2, accuracy: 1e-9)
        XCTAssertEqual(rect.midX, 0.5, accuracy: 1e-9)
    }

    func testPanningNeverUncoversTheWindow() {
        let crop = CollageCrop.fill.moved(dx: 5, dy: 5, photoAspect: photo, windowAspect: window)
        let rect = crop.photoRect(photoAspect: photo, windowAspect: window)
        XCTAssertEqual(rect.minX, 0, accuracy: 1e-9, "stopped at the photo's edge")
        XCTAssertEqual(rect.midY, 0.5, accuracy: 1e-9, "no room to move vertically")
        let back = crop.moved(dx: -10, dy: 0, photoAspect: photo, windowAspect: window)
        XCTAssertEqual(back.photoRect(photoAspect: photo, windowAspect: window).maxX, 1, accuracy: 1e-9)
    }

    func testFitShowsTheWholePhotoAndDoubleTapToggles() {
        let fit = CollageCrop.fill.toggledFit(photoAspect: photo, windowAspect: window)
        XCTAssertEqual(fit.zoom, 0.5, accuracy: 1e-9)
        let rect = fit.photoRect(photoAspect: photo, windowAspect: window)
        XCTAssertEqual(rect.width, 1, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rect.midY, 0.5, accuracy: 1e-9)
        XCTAssertEqual(fit.toggledFit(photoAspect: photo, windowAspect: window), .fill)
        // Zoomed in and moved: a double-tap fits the whole photo again.
        let zoomed = CollageCrop(zoom: 2, offsetX: 0.3).toggledFit(photoAspect: photo, windowAspect: window)
        XCTAssertEqual(zoomed, CollageCrop(zoom: 0.5))
        // A photo the window's shape has nothing to fit.
        XCTAssertEqual(CollageCrop.fill.toggledFit(photoAspect: 1, windowAspect: 1), .fill)
    }

    func testZoomStaysInRangeAndKeepsTheCentre() {
        let out = CollageCrop.fill.zoomed(by: 0.1, photoAspect: photo, windowAspect: window)
        XCTAssertEqual(out.zoom, 0.5, accuracy: 1e-9, "no smaller than the whole photo")
        let deep = CollageCrop.fill.zoomed(by: 100, photoAspect: photo, windowAspect: window)
        XCTAssertEqual(deep.zoom, CollageCrop.maxZoom, accuracy: 1e-9)

        let moved = CollageCrop(zoom: 2, offsetX: 0.4, offsetY: 0.2)
        let before = moved.photoRect(photoAspect: photo, windowAspect: window)
        let after = moved.zoomed(by: 1.5, photoAspect: photo, windowAspect: window).photoRect(photoAspect: photo, windowAspect: window)
        // The photo point under the window's centre stays under it.
        let pointBefore = ((0.5 - before.minX) / before.width, (0.5 - before.minY) / before.height)
        let pointAfter = ((0.5 - after.minX) / after.width, (0.5 - after.minY) / after.height)
        XCTAssertEqual(pointBefore.0, pointAfter.0, accuracy: 1e-9)
        XCTAssertEqual(pointBefore.1, pointAfter.1, accuracy: 1e-9)
    }
}

final class CarouselSlicerTests: XCTestCase {
    func testCarouselExportsOrderedFourByFiveSlides() {
        for slides in CollageFormat.slideRange {
            let format = CollageFormat.carousel(slides: slides)
            let canvas = format.pixelSize()
            XCTAssertEqual(canvas, PixelSize(width: 2160 * slides, height: 2700))
            let slices = CarouselSlicer.slices(of: canvas, count: format.slides)
            XCTAssertEqual(slices.count, slides)
            XCTAssertEqual(slices.map(\.number), Array(1...slides))
            XCTAssertEqual(slices.first?.x, 0)
            for (index, slice) in slices.enumerated() {
                XCTAssertEqual(slice.width * 5, slice.height * 4, "each slide is 4:5")
                XCTAssertEqual(slice.height, canvas.height)
                if index > 0 { XCTAssertEqual(slice.x, slices[index - 1].x + slices[index - 1].width, "no gap or overlap") }
            }
            XCTAssertEqual(slices.last.map { $0.x + $0.width }, canvas.width)
        }
    }

    func testOddWidthsStillTileExactly() {
        let slices = CarouselSlicer.slices(of: PixelSize(width: 1001, height: 400), count: 3)
        XCTAssertEqual(slices.map(\.width).reduce(0, +), 1001)
        XCTAssertLessThanOrEqual(slices.map(\.width).max()! - slices.map(\.width).min()!, 1)
    }

    func testFormatsAndSeams() {
        XCTAssertEqual(CollageFormat.carousel(slides: 9).slides, 5)
        XCTAssertEqual(CollageFormat.carousel(slides: 1).slides, 2)
        XCTAssertEqual(CollageFormat.portrait.slides, 1)
        XCTAssertEqual(CollageFormat.carousel(slides: 3).widthOverHeight, 2.4, accuracy: 1e-9)
        XCTAssertEqual(CollageFormat.portrait.pixelSize(), PixelSize(width: 1728, height: 2160))
        XCTAssertEqual(CollageFormat.story.pixelSize(), PixelSize(width: 1215, height: 2160))
        XCTAssertEqual(CollageFormat.classic.pixelSize(), PixelSize(width: 1620, height: 2160))
        XCTAssertEqual(CollageFormat.square.pixelSize(), PixelSize(width: 2160, height: 2160))
        XCTAssertEqual(CarouselSlicer.seams(count: 4), [0.25, 0.5, 0.75])
        XCTAssertEqual(CarouselSlicer.seams(count: 1), [])
    }
}

final class CollageProvenanceTests: XCTestCase {
    func testHerOwnPhotosClaimNothing() {
        let provenance = Provenance.collage(of: [nil, nil, nil])
        XCTAssertNil(provenance.sourceType)
        XCTAssertFalse(provenance.carriesAIProvenance)
        XCTAssertFalse(provenance.showsMark(isPro: false))
    }

    func testAnAIPhotoMakesAnAIComposite() {
        let provenance = Provenance.collage(of: [nil, .trainedAlgorithmicMedia, nil])
        XCTAssertEqual(provenance.sourceType, .compositeWithTrainedAlgorithmicMedia)
        XCTAssertEqual(provenance.storedSourceType, .compositeWithTrainedAlgorithmicMedia)
        XCTAssertTrue(provenance.carriesAIProvenance)
        XCTAssertFalse(provenance.isFullyGenerated)
        // Marked by its sources, never by Aybuke's free-tier mark.
        XCTAssertFalse(provenance.showsMark(isPro: false))
        XCTAssertEqual(Provenance.collage(of: [.compositeWithTrainedAlgorithmicMedia, nil]).sourceType, .compositeWithTrainedAlgorithmicMedia)
    }

    func testAllAIPicturesStayAIMade() {
        let provenance = Provenance.collage(of: [.trainedAlgorithmicMedia, .trainedAlgorithmicMedia])
        XCTAssertEqual(provenance.sourceType, .trainedAlgorithmicMedia)
        XCTAssertTrue(provenance.isFullyGenerated)
    }

    func testOtherMarkingsMakeAPlainComposite() {
        XCTAssertEqual(Provenance.collage(of: [.algorithmicallyEnhanced, nil]).sourceType, .composite)
        XCTAssertEqual(Provenance.collage(of: [.composite, .algorithmicallyEnhanced]).sourceType, .composite)
        XCTAssertFalse(Provenance.collage(of: [.composite, nil]).carriesAIProvenance)
    }
}
