import XCTest
@testable import AppCore

/// Canvas zoom, the brush loupe, My filters and the share composer's sizes.
final class EditorPolishTests: XCTestCase {
    // MARK: Zoom

    func testDoubleTapGoesToTwiceAndBackToFit() {
        XCTAssertEqual(CanvasZoomMath.doubleTapTarget(from: 1), 2)
        XCTAssertEqual(CanvasZoomMath.doubleTapTarget(from: 1.005), 2, "a hair above fit is fit")
        XCTAssertEqual(CanvasZoomMath.doubleTapTarget(from: 2), 1)
        XCTAssertEqual(CanvasZoomMath.doubleTapTarget(from: 3.4), 1)
    }

    func testAPinchJustAboveFitSettlesAtFit() {
        XCTAssertEqual(CanvasZoomMath.settledScale(1.05), 1)
        XCTAssertEqual(CanvasZoomMath.settledScale(1.5), 1.5)
        XCTAssertEqual(CanvasZoomMath.settledScale(9), CanvasZoomMath.maximumScale)
    }

    func testTheBadgeShowsOneDecimalAndNothingAtFit() {
        XCTAssertNil(CanvasZoomMath.badgeValue(for: 1))
        XCTAssertNil(CanvasZoomMath.badgeValue(for: 1.004))
        XCTAssertEqual(CanvasZoomMath.badgeValue(for: 2), 2)
        XCTAssertEqual(CanvasZoomMath.badgeValue(for: 1.46), 1.5)
        XCTAssertEqual(CanvasZoomMath.badgeValue(for: 6), 4)
    }

    func testDoubleTapZoomsAroundTheTappedSpotAndStaysOnTheCanvas() {
        // In the middle: centred on the tap.
        let middle = CanvasZoomMath.zoomRect(around: 200, 300, width: 400, height: 600, scale: 2)
        XCTAssertEqual(middle, CanvasRect(x: 100, y: 150, width: 200, height: 300))
        // Near a corner: the same size, pushed back onto the canvas.
        let corner = CanvasZoomMath.zoomRect(around: 10, 590, width: 400, height: 600, scale: 2)
        XCTAssertEqual(corner, CanvasRect(x: 0, y: 300, width: 200, height: 300))
        XCTAssertTrue(CanvasRect(x: 0, y: 0, width: 400, height: 600).contains(corner))
    }

    func testResizingKeepsTheSameSpotInTheMiddle() {
        let offset = CanvasZoomMath.offset(keeping: (0.5, 0.5), contentWidth: 800, contentHeight: 1200, viewWidth: 400, viewHeight: 600)
        XCTAssertEqual(offset.x, 200)
        XCTAssertEqual(offset.y, 300)
        let edge = CanvasZoomMath.offset(keeping: (0.99, 0), contentWidth: 800, contentHeight: 1200, viewWidth: 400, viewHeight: 600)
        XCTAssertEqual(edge.x, 400, "never past the content")
        XCTAssertEqual(edge.y, 0)
    }

    // MARK: Loupe

    func testTheLoupeSitsAboveTheFingerAndInsideTheCanvas() {
        let above = LoupeLayout.frame(touchX: 200, touchY: 400, width: 400, height: 600, diameter: 120, gap: 30)
        XCTAssertEqual(above.midX, 200)
        XCTAssertEqual(above.maxY, 370, "a gap above the finger")
        // Near the top: beside the finger, away from the nearer edge.
        let nearTopRight = LoupeLayout.frame(touchX: 340, touchY: 60, width: 400, height: 600, diameter: 120, gap: 30)
        XCTAssertLessThan(nearTopRight.maxX, 340, "to the left of a finger on the right")
        let nearTopLeft = LoupeLayout.frame(touchX: 40, touchY: 60, width: 400, height: 600, diameter: 120, gap: 30)
        XCTAssertGreaterThan(nearTopLeft.minX, 40, "to the right of a finger on the left")
        let canvas = CanvasRect(x: 0, y: 0, width: 400, height: 600)
        for touch in [(0.0, 0.0), (400, 0), (0, 600), (400, 600), (200, 10)] {
            let frame = LoupeLayout.frame(touchX: touch.0, touchY: touch.1, width: 400, height: 600, diameter: 120, gap: 30)
            XCTAssertTrue(canvas.contains(frame), "\(touch)")
        }
        let source = LoupeLayout.source(touchX: 100, touchY: 100, diameter: 120)
        XCTAssertEqual(source, CanvasRect(x: 70, y: 70, width: 60, height: 60))
    }

    // MARK: My filters

    private var dreamyish: AdjustmentSettings {
        AdjustVibes.preset(id: "dreamy")!.applied(to: .neutral, replacing: nil)
    }

    func testSavingAFilterKeepsItsValuesAndVibeNewestFirst() {
        var shelf = MyFilterShelf()
        guard case .saved(let first) = shelf.save(name: "  Beach day \n", settings: dreamyish, vibeID: "dreamy") else {
            return XCTFail("saved")
        }
        XCTAssertEqual(first.name, "Beach day")
        XCTAssertEqual(first.vibe?.id, "dreamy")
        var warmer = dreamyish
        warmer.warmth = 0.5
        shelf.save(name: "Warm", settings: warmer, vibeID: nil)
        XCTAssertEqual(shelf.filters.map(\.name), ["Warm", "Beach day"])
        XCTAssertEqual(shelf.filter(matching: dreamyish)?.id, first.id)
    }

    func testSavingRefusesNothingDuplicatesEmptyNamesAndAFullShelf() {
        var shelf = MyFilterShelf()
        XCTAssertEqual(shelf.save(name: "Nothing", settings: .neutral, vibeID: nil), .neutral)
        XCTAssertEqual(shelf.save(name: "   ", settings: dreamyish, vibeID: nil), .emptyName)
        guard case .saved(let saved) = shelf.save(name: "Dreamy mine", settings: dreamyish, vibeID: nil) else { return XCTFail("saved") }
        XCTAssertEqual(shelf.save(name: "Again", settings: dreamyish, vibeID: nil), .duplicate(saved))
        for step in 1..<MyFilterShelf.limit {
            var settings = AdjustmentSettings.neutral
            settings.grain = Double(step) / 20
            shelf.save(name: "Grain \(step)", settings: settings, vibeID: nil)
        }
        XCTAssertTrue(shelf.isFull)
        var one = AdjustmentSettings.neutral
        one.vignette = 0.9
        XCTAssertEqual(shelf.save(name: "One more", settings: one, vibeID: nil), .full)
        XCTAssertEqual(shelf.filters.count, MyFilterShelf.limit)
    }

    func testRenamingAndDeleting() {
        var shelf = MyFilterShelf()
        guard case .saved(let saved) = shelf.save(name: "Old", settings: dreamyish, vibeID: nil) else { return XCTFail("saved") }
        XCTAssertFalse(shelf.rename(saved.id, to: "  "))
        XCTAssertTrue(shelf.rename(saved.id, to: String(repeating: "a", count: 40)))
        XCTAssertEqual(shelf.filters.first?.name.count, MyFilterShelf.maxNameLength)
        shelf.delete(saved.id)
        XCTAssertTrue(shelf.filters.isEmpty)
    }

    func testSuggestedNamesSkipTakenOnes() {
        var shelf = MyFilterShelf()
        XCTAssertEqual(shelf.suggestedName(base: "My filter"), "My filter 1")
        shelf.save(name: "My filter 2", settings: dreamyish, vibeID: nil)
        XCTAssertEqual(shelf.suggestedName(base: "My filter"), "My filter 3")
    }

    func testStorageRoundTripsAndCleansUp() throws {
        var shelf = MyFilterShelf()
        shelf.save(name: "Keep", settings: dreamyish, vibeID: "dreamy")
        XCTAssertEqual(MyFilterShelf.decode(shelf.encoded()), shelf)
        XCTAssertEqual(MyFilterShelf.decode(nil), MyFilterShelf())
        XCTAssertEqual(MyFilterShelf.decode(Data("not json".utf8)), MyFilterShelf())
        // A slider added later reads as at rest; values out of range come back on their slider.
        let stored = """
        {"filters":[{"id":"\(UUID().uuidString)","name":"Old one","settings":{"glow":3,"futureSlider":1}},
                    {"id":"\(UUID().uuidString)","name":" ","settings":{"glow":0.5}},
                    {"id":"\(UUID().uuidString)","name":"Flat","settings":{}}]}
        """
        let decoded = MyFilterShelf.decode(Data(stored.utf8))
        XCTAssertEqual(decoded.filters.map(\.name), ["Old one"])
        XCTAssertEqual(decoded.filters.first?.settings.glow, 1)
        XCTAssertEqual(decoded.filters.first?.settings.contrast, 1)
    }

    // MARK: Share sizes

    func testEverySizeHasItsShapeAndRatio() {
        XCTAssertNil(ShareSize.original.pixelSize)
        XCTAssertFalse(ShareSize.cardSizes.contains(.original))
        for size in ShareSize.cardSizes {
            let pixels = try! XCTUnwrap(size.pixelSize)
            let parts = size.ratio.split(separator: ":").compactMap { Double($0) }
            XCTAssertEqual(parts.count, 2, size.id)
            XCTAssertEqual(pixels.width / pixels.height, parts[0] / parts[1], accuracy: 0.001, size.id)
            XCTAssertGreaterThanOrEqual(min(pixels.width, pixels.height), 900, "sharp enough for a feed: \(size.id)")
        }
        XCTAssertTrue(ShareLayout.isStoryShaped(width: 1080, height: 1920))
        XCTAssertFalse(ShareLayout.isStoryShaped(width: 1080, height: 1350))
    }

    func testTheStoriesCardKeepsItsLayout() {
        let card = StoryCardLayout(size: .story, branded: true, hasCaption: false)
        XCTAssertEqual(card.header, CanvasRect(x: 0, y: 150, width: 1080, height: 90))
        XCTAssertEqual(card.footer, CanvasRect(x: 0, y: 1620, width: 1080, height: 60))
        XCTAssertEqual(card.photoArea, CanvasRect(x: 110, y: 300, width: 860, height: 1300))
        XCTAssertEqual(ShareLayout.labelReserve(size: .story, isCard: true), 300)
    }

    func testCardsInEverySizeKeepClearOfTheAppsButtons() {
        for size in ShareSize.cardSizes {
            for branded in [false, true] {
                for hasCaption in [false, true] {
                    let card = StoryCardLayout(size: size, branded: branded, hasCaption: hasCaption)
                    let insets = size.safeInsets
                    let safe = CanvasRect(x: insets.left, y: insets.top, width: card.canvas.width - insets.left - insets.right,
                                          height: card.canvas.height - insets.top - insets.bottom)
                    let label = "\(size.id) branded \(branded) caption \(hasCaption)"
                    XCTAssertTrue(safe.contains(card.photoArea), label)
                    XCTAssertGreaterThan(card.photoArea.height, card.canvas.height * 0.4, label)
                    for portrait in [true, false] {
                        let photo = card.photoFrame(imageWidth: portrait ? 800 : 1200, imageHeight: portrait ? 1200 : 800)
                        XCTAssertTrue(card.photoArea.contains(photo), label)
                        XCTAssertEqual(photo.width / photo.height, portrait ? 2.0 / 3 : 1.5, accuracy: 0.01, label)
                        if let caption = card.caption(under: photo) {
                            XCTAssertGreaterThanOrEqual(caption.minY, photo.maxY, label)
                            XCTAssertLessThanOrEqual(caption.maxY, card.footer?.minY ?? card.canvas.height, label)
                        }
                    }
                    if let header = card.header { XCTAssertLessThanOrEqual(header.maxY, card.photoArea.minY, label) }
                    if let footer = card.footer { XCTAssertGreaterThanOrEqual(footer.minY, card.photoArea.maxY, label) }
                }
            }
        }
    }

    func testABackdropShowsOnlyWhenThePhotoLeavesRoom() {
        XCTAssertTrue(ShareLayout.showsBackdrop(imageWidth: 800, imageHeight: 1200, size: .story))
        XCTAssertFalse(ShareLayout.showsBackdrop(imageWidth: 1080, imageHeight: 1350, size: .post))
        XCTAssertFalse(ShareLayout.showsBackdrop(imageWidth: 800, imageHeight: 1200, size: .original))
        let fitted = ShareLayout.fit(width: 800, height: 1200, in: CanvasRect(x: 0, y: 0, width: 1080, height: 1920))
        XCTAssertEqual(fitted.width, 1080)
        XCTAssertEqual(fitted.midY, 960, accuracy: 1)
        XCTAssertEqual(ShareBackdrop(id: "blur"), .blur)
        XCTAssertEqual(ShareBackdrop(id: "ink"), .color(.ink))
        XCTAssertNil(ShareBackdrop(id: "neon"))
        XCTAssertTrue(ShareBackdrop.color(.ink).isDark)
        XCTAssertEqual(ShareBackdrop.all.count, 2 + ShareSwatch.allCases.count)
    }

    func testShareTextIsTrimmedAndCut() {
        XCTAssertEqual(ShareTextSlot.coverMasthead.clean("  sunny days forever "), "sunny days")
        XCTAssertEqual(ShareTextSlot.stripCaption.clean("best\nnight\never"), "best night ever")
        XCTAssertEqual(ShareTextSlot.coverHeadline.clean("Soft girl\nsummer\nera"), "Soft girl\nsummer era")
        XCTAssertEqual(ShareTextSlot.storyLine.clean("   "), "")
        for slot in ShareTextSlot.allCases {
            XCTAssertLessThanOrEqual(slot.clean(String(repeating: "x", count: 200)).count, slot.maxLength)
        }
    }

    /// Sample texts shown in the composer pass the same rules as overlay text.
    func testShareTextGoesThroughThePromptPolicy() {
        XCTAssertTrue(ContentPolicy.evaluate("Soft girl summer", operation: .textToImage).isAllowed)
    }
}
