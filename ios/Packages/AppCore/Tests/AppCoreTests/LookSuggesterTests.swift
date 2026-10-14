import XCTest
@testable import AppCore

final class LookSuggesterTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(month: Int, day: Int = 15) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    /// The app's effect ids (RetroEffect raw values).
    private let effects = ["vhs", "disposable", "kira", "digicam", "instant", "glamour", "neon", "throwback16", "camcorder06", "filmStill", "tinyWorld"]

    private func suggest(_ insight: PhotoInsight, month: Int = 4, rotation: Int = 0) -> [LookSuggestion] {
        LookSuggester.suggest(for: insight, date: date(month: month), calendar: utc, freeEffects: effects, rotation: rotation)
    }

    private func templates(_ suggestions: [LookSuggestion]) -> [PhotoTemplate] {
        suggestions.compactMap { if case .template(let id) = $0 { TemplateCatalog.template(id: id) } else { nil } }
    }

    // MARK: Kinds

    func testKindDerivation() {
        XCTAssertEqual(PhotoInsight(faceCount: 1).kind, .selfie)
        XCTAssertEqual(PhotoInsight(faceCount: 3, labels: ["beach"]).kind, .group)
        XCTAssertEqual(PhotoInsight(hasAnimal: true, animalKind: "Cat").kind, .pet)
        XCTAssertEqual(PhotoInsight(labels: ["dog"]).kind, .pet)
        XCTAssertEqual(PhotoInsight(labels: ["sky", "water_body"]).kind, .landscape)
        XCTAssertEqual(PhotoInsight(labels: ["structure", "street"], isDark: true).kind, .cityNight)
        XCTAssertEqual(PhotoInsight(labels: ["structure", "street"], isDark: false).kind, .city)
        // Sky in view keeps it a landscape; a room keeps it indoors.
        XCTAssertEqual(PhotoInsight(labels: ["building", "sky"]).kind, .landscape)
        XCTAssertEqual(PhotoInsight(labels: ["structure", "room"]).kind, .indoor)
        XCTAssertEqual(PhotoInsight(labels: ["baked_goods", "table"]).kind, .food)
        XCTAssertEqual(PhotoInsight(labels: ["furniture", "room"]).kind, .indoor)
        XCTAssertEqual(PhotoInsight().kind, .other)
        // Labels are compared in lowercase.
        XCTAssertEqual(PhotoInsight(labels: ["Mountain"]).kind, .landscape)
    }

    // MARK: Rules

    func testAtMostFourAndFreeEffectFirst() {
        for kind in [PhotoInsight(faceCount: 1), PhotoInsight(faceCount: 2), PhotoInsight(labels: ["cat"]),
                     PhotoInsight(labels: ["sky"]), PhotoInsight(labels: ["street"]), PhotoInsight(labels: ["food"]), PhotoInsight()] {
            let ideas = suggest(kind)
            XCTAssertLessThanOrEqual(ideas.count, LookSuggester.maxSuggestions)
            guard case .effect(let id) = ideas.first else { return XCTFail("First idea should be a free effect") }
            XCTAssertTrue(effects.contains(id))
        }
    }

    func testOnlyOfferedEffectsAreReturned() {
        let ideas = LookSuggester.suggest(for: PhotoInsight(faceCount: 1), date: date(month: 4), calendar: utc, freeEffects: ["instant"])
        let ids = ideas.compactMap { if case .effect(let id) = $0 { id } else { nil } }
        XCTAssertEqual(ids, ["instant"])
    }

    func testNeverSuggestsSoftFocusEffect() {
        for kind in PhotoKind.allCases {
            for theme in [nil] + SeasonalTheme.allCases.map(Optional.some) {
                XCTAssertFalse(LookSuggester.effectIDs(for: kind, theme: theme).contains("glamour"))
            }
        }
    }

    func testPeopleNeverGetBeautyLooks() {
        let beauty: Set<String> = ["soft-glam", "glam", "curls", "clean-girl"]
        for month in 1...12 {
            for faces in [1, 2] {
                let ids = templates(suggest(PhotoInsight(faceCount: faces), month: month)).map(\.id)
                XCTAssertTrue(beauty.isDisjoint(with: ids), "month \(month): \(ids)")
                for kind in PhotoKind.allCases {
                    let candidates = LookSuggester.templateCandidates(
                        for: kind, theme: SeasonalTheme.current(on: date(month: month), calendar: utc),
                        date: date(month: month), calendar: utc, catalog: TemplateCatalog.all
                    )
                    XCTAssertTrue(beauty.isDisjoint(with: candidates.map(\.id)))
                    XCTAssertFalse(candidates.contains { $0.category == .glowUp && $0.id != "pink-hair" })
                }
            }
        }
    }

    func testTinyWorldForCitiesAndLandscapes() {
        XCTAssertEqual(suggest(PhotoInsight(labels: ["street", "building"])).first, .effect("tinyWorld"))
        XCTAssertTrue(suggest(PhotoInsight(labels: ["sky", "mountain"])).contains(.effect("tinyWorld")))
        XCTAssertTrue(LookSuggester.effectIDs(for: .cityNight, theme: nil).contains("tinyWorld"))
        // A tilt-shift blur is never suggested for photos of people.
        for kind in PhotoKind.allCases where kind.hasPeople {
            XCTAssertFalse(LookSuggester.effectIDs(for: kind, theme: nil).contains("tinyWorld"))
        }
    }

    func testPetsGetPetLooks() {
        let looks = templates(suggest(PhotoInsight(hasAnimal: true, animalKind: "dog")))
        XCTAssertEqual(looks.first?.category, .pets)
    }

    func testTemplateIdsAreRealAndFreeFirst() {
        for month in 1...12 {
            for kind in PhotoKind.allCases {
                let candidates = LookSuggester.templateCandidates(
                    for: kind, theme: SeasonalTheme.current(on: date(month: month), calendar: utc),
                    date: date(month: month), calendar: utc, catalog: TemplateCatalog.all
                )
                XCTAssertFalse(candidates.isEmpty, "\(kind)")
                XCTAssertFalse(candidates.first?.isPro ?? true, "\(kind) in month \(month) leads with a Pro look")
                if let firstPro = candidates.firstIndex(where: \.isPro) {
                    XCTAssertTrue(candidates[firstPro...].allSatisfy(\.isPro), "free looks come before Pro ones")
                }
            }
        }
    }

    // MARK: Seasons

    func testHalloweenBoost() {
        let october = suggest(PhotoInsight(faceCount: 1), month: 10)
        XCTAssertEqual(templates(october).first?.season, .halloween)
        XCTAssertFalse(templates(october).first?.isPro ?? true)
        guard case .magicEdit(let prompt) = october.first(where: { if case .magicEdit = $0 { true } else { false } }) else {
            return XCTFail("Expected a Magic Edit idea")
        }
        XCTAssertTrue(prompt.contains("witch hat"))

        let april = suggest(PhotoInsight(faceCount: 1), month: 4)
        XCTAssertNil(templates(april).first?.season)
    }

    func testWinterLooksOnlyInSeason() {
        let december = templates(suggest(PhotoInsight(faceCount: 2), month: 12, rotation: 0))
        XCTAssertEqual(december.first?.season, .winter)
        let july = templates(suggest(PhotoInsight(faceCount: 2), month: 7))
        XCTAssertNil(july.first?.season)
    }

    // MARK: Determinism and rotation

    func testDeterministic() {
        let insight = PhotoInsight(labels: ["sky", "mountain"])
        XCTAssertEqual(suggest(insight), suggest(insight))
        XCTAssertEqual(suggest(insight, rotation: 3), suggest(insight, rotation: 3))
    }

    func testDifferentPhotosCanLeadWithDifferentIdeasAndLooks() {
        let labelSets: [[String]] = [[], ["indoor"], ["outdoor", "sky"], ["beach"], ["room", "bed"], ["street"],
                                     ["flower", "garden"], ["snow"], ["food"], ["tree", "grass"], ["window"], ["concert"]]
        var ideas = Set<String>()
        var looks = Set<String>()
        for labels in labelSets {
            let insight = PhotoInsight(faceCount: 1, labels: labels)
            let suggestions = suggest(insight)
            XCTAssertEqual(suggestions, suggest(insight), "the same photo always gets the same ideas")
            for suggestion in suggestions {
                if case .magicEdit(let prompt) = suggestion { ideas.insert(prompt) }
                if case .template(let id) = suggestion { looks.insert(id) }
            }
        }
        XCTAssertGreaterThan(ideas.count, 2)
        XCTAssertGreaterThan(looks.count, 2)
    }

    func testNewPetLooksCanLead() {
        var looks = Set<String>()
        for labels in [["cat"], ["dog"], ["rabbit"], ["bird"], ["hamster"], ["puppy"], ["kitten"], ["dog", "grass"], ["cat", "sofa"], ["pet", "bed"]] {
            looks.formUnion(templates(suggest(PhotoInsight(labels: labels))).map(\.id))
        }
        XCTAssertFalse(looks.isDisjoint(with: ["pet-party", "pet-studio"]), "\(looks)")
        XCTAssertFalse(looks.contains("plushie-pet"), "a Pro look never leads")
    }

    func testRotationMovesThroughEffects() {
        let insight = PhotoInsight(labels: ["sky"])
        var seen: [LookSuggestion] = []
        for rotation in 0..<4 {
            if let first = suggest(insight, rotation: rotation).first { seen.append(first) }
        }
        XCTAssertEqual(Set(seen).count, 4)
        XCTAssertEqual(suggest(insight, rotation: 4).first, suggest(insight, rotation: 0).first)
        XCTAssertEqual(suggest(insight, rotation: -1).first, suggest(insight, rotation: 3).first)
    }

    // MARK: Safety

    func testEveryIdeaPassesThePolicy() {
        XCTAssertFalse(LookSuggester.allMagicEditIdeas.isEmpty)
        for idea in LookSuggester.allMagicEditIdeas {
            XCTAssertEqual(ContentPolicy.evaluate(idea, operation: .magicEdit), .allowed, idea)
            // What the server checks: the idea with the edit guard appended.
            XCTAssertEqual(ContentPolicy.evaluate(PromptBuilder.editInstruction(idea), operation: .magicEdit), .allowed, idea)
        }
    }

    func testEveryKindHasSeveralIdeas() {
        for kind in PhotoKind.allCases {
            let ideas = LookSuggester.magicEditIdeas(for: kind, theme: nil)
            XCTAssertGreaterThanOrEqual(ideas.count, 5, "\(kind)")
            XCTAssertEqual(ideas.count, Set(ideas).count, "\(kind) repeats an idea")
            // The season's idea always leads, whatever the photo.
            for theme in SeasonalTheme.allCases {
                let seasonal = LookSuggester.magicEditIdeas(for: kind, theme: theme, offset: 3)
                XCTAssertEqual(seasonal.first, LookSuggester.magicEditIdeas(for: kind, theme: theme).first)
            }
        }
    }

    func testIdeasNeverTalkAboutLooks() {
        let banned = ["face", "skin", "body", "slim", "thin", "weight", "makeup", "lips", "eyes", "nose",
                      "prettier", "beautiful", "younger", "older", "tan", "whiten", "waist", "smooth"]
        for idea in LookSuggester.allMagicEditIdeas {
            let words = Set(idea.lowercased().split { !$0.isLetter }.map(String.init))
            XCTAssertTrue(words.isDisjoint(with: banned), idea)
        }
    }
}
