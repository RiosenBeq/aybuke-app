import XCTest
@testable import AppCore

final class MakeupStudioTests: XCTestCase {
    /// Every non-empty set of extras, in a fixed order.
    private static let extraSets: [Set<MakeupExtra>] = {
        let all = MakeupExtra.allCases
        return (1..<(1 << all.count)).map { mask in
            Set(all.indices.filter { mask & (1 << $0) != 0 }.map { all[$0] })
        }
    }()

    private static let onlyMeSentence = "Only change the main person in front; keep everyone else exactly as they are."

    /// The text the server checks: the instruction, "Only edit me" when she
    /// picked it, and the edit guard.
    private func sent(_ recipe: MakeupRecipe, onlyMe: Bool) -> String {
        let instruction = MakeupStudio.instruction(for: recipe)
        return PromptBuilder.editInstruction(onlyMe ? PromptBuilder.onlyMainPerson(instruction) : instruction)
    }

    // MARK: Looks

    func testLooksAreWellFormed() {
        let presets = MakeupStudio.presets
        XCTAssertGreaterThanOrEqual(presets.count, 12)
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count, "ids are unique")
        XCTAssertEqual(Set(presets.map(\.name)).count, presets.count, "names are unique")
        XCTAssertEqual(Set(presets.map(\.recipe)).count, presets.count, "every look is different")
        for preset in presets {
            XCTAssertTrue(preset.recipe.hasMakeup, preset.id)
            XCTAssertEqual(preset.recipe.hair, .none, "\(preset.id): a look never picks her hair color")
            XCTAssertTrue((2...3).contains(preset.swatches.count), preset.id)
            for swatch in preset.swatches {
                XCTAssertTrue(Self.isHexColor(swatch), "\(preset.id): \(swatch)")
            }
            XCTAssertEqual(MakeupStudio.preset(id: preset.id), preset)
            XCTAssertEqual(MakeupStudio.preset(matching: preset.recipe), preset)
            XCTAssertEqual(MakeupStudio.preset(matching: preset.recipe.withHair(.lilac)), preset, "her hair color keeps the look")
        }
        XCTAssertEqual(MakeupStudio.defaultPreset.id, "softGlam")
        XCTAssertNil(MakeupStudio.preset(id: "nope"))
    }

    func testAChangedLookIsCustom() {
        var recipe = MakeupStudio.defaultPreset.recipe
        recipe.intensity = .bold
        XCTAssertNil(MakeupStudio.preset(matching: recipe))
        recipe = MakeupStudio.defaultPreset.recipe
        recipe.toggle(.glitter)
        XCTAssertNil(MakeupStudio.preset(matching: recipe))
        recipe.toggle(.glitter)
        XCTAssertEqual(MakeupStudio.preset(matching: recipe), MakeupStudio.defaultPreset)
    }

    func testEveryChoiceHasANameAndAColor() {
        func check<Choice: MakeupChoice>(_ choices: [Choice], hasNone: Bool) {
            XCTAssertEqual(Set(choices.map(\.name)).count, choices.count, "\(Choice.self) names are unique")
            for choice in choices {
                XCTAssertFalse(choice.name.isEmpty)
                if hasNone, choice == choices.first {
                    XCTAssertEqual(choice.name, "As is")
                    XCTAssertNil(choice.swatch)
                } else {
                    XCTAssertTrue(choice.swatch.map(Self.isHexColor) ?? false, "\(choice)")
                }
            }
        }
        check(MakeupLips.allCases, hasNone: true)
        check(MakeupEyes.allCases, hasNone: true)
        check(MakeupCheeks.allCases, hasNone: true)
        check(MakeupHair.allCases, hasNone: true)
        check(MakeupExtra.allCases, hasNone: false)
        XCTAssertEqual(MakeupIntensity.allCases.map(\.name), ["Soft", "Medium", "Vivid"])
    }

    func testRecipeStates() {
        XCTAssertTrue(MakeupRecipe().isEmpty)
        XCTAssertFalse(MakeupRecipe().hasMakeup)
        let hairOnly = MakeupRecipe(hair: .pastelPink)
        XCTAssertFalse(hairOnly.isEmpty)
        XCTAssertFalse(hairOnly.hasMakeup)
        XCTAssertTrue(MakeupRecipe(extras: [.glitter]).hasMakeup)
        XCTAssertEqual(MakeupStudio.defaultPreset.recipe.withHair(.blue).hair, .blue)
    }

    // MARK: Requests

    func testNothingChosenAsksForNothing() {
        XCTAssertEqual(MakeupStudio.instruction(for: MakeupRecipe()), "")
        XCTAssertEqual(MakeupStudio.instruction(for: MakeupRecipe(intensity: .bold)), "")
    }

    func testTheRequestAsksOnlyForWhatShePicked() {
        let instruction = MakeupStudio.instruction(for: MakeupRecipe(lips: .cherryRed, intensity: .soft))
        XCTAssertEqual(instruction, """
        Add makeup to the person in this photo as color, shine and sparkle on the real skin. \
        Lips: a cherry-red color, following the natural lip line. Keep the colors soft and subtle. \
        \(MakeupStudio.skinGuard)
        """)
        XCTAssertFalse(instruction.contains("Eyes:"))
        XCTAssertFalse(instruction.contains("Hair:"))
    }

    func testAHairColorAloneOnlyChangesTheHairColor() {
        let instruction = MakeupStudio.instruction(for: MakeupRecipe(hair: .pastelPink))
        XCTAssertTrue(instruction.hasPrefix("Change only the hair color of the person in this photo."), instruction)
        XCTAssertTrue(instruction.contains("Hair: soft pastel pink color with realistic highlights, same hairstyle and cut."), instruction)
        XCTAssertFalse(instruction.contains("makeup"), instruction)
        XCTAssertTrue(instruction.hasSuffix(MakeupStudio.skinGuard))
    }

    func testExtrasAreListedInAFixedOrder() {
        let recipe = MakeupRecipe(extras: [.glitter, .faceGems, .starStickers])
        XCTAssertTrue(MakeupStudio.instruction(for: recipe).contains(
            "Extras: a few face gems by the outer eye corners, star stickers on the cheekbones and glitter on the cheekbones."
        ))
    }

    func testEveryRequestKeepsTheSkinAndTheEditGuard() {
        for preset in MakeupStudio.presets {
            let instruction = MakeupStudio.instruction(for: preset.recipe)
            XCTAssertTrue(instruction.hasSuffix(MakeupStudio.skinGuard), preset.id)
            XCTAssertTrue(instruction.contains("following the natural lip line") || preset.recipe.lips == .none, preset.id)
            for onlyMe in [false, true] {
                let text = sent(preset.recipe, onlyMe: onlyMe)
                XCTAssertTrue(text.contains(MakeupStudio.skinGuard), preset.id)
                XCTAssertTrue(text.hasSuffix(PromptBuilder.editGuard), preset.id)
                XCTAssertEqual(text.contains(Self.onlyMeSentence), onlyMe, preset.id)
            }
        }
    }

    /// `PromptBuilder.sanitize` cuts after 800 characters, which would drop
    /// the skin guard, so every recipe (with "Only edit me") must fit.
    func testEveryRequestFitsWithoutBeingCut() {
        var longest = ""
        for lips in MakeupLips.allCases {
            for eyes in MakeupEyes.allCases {
                for cheeks in MakeupCheeks.allCases {
                    for extras in [[]] + Self.extraSets {
                        for hair in MakeupHair.allCases {
                            for intensity in MakeupIntensity.allCases {
                                let recipe = MakeupRecipe(lips: lips, eyes: eyes, cheeks: cheeks, extras: extras, hair: hair, intensity: intensity)
                                let text = PromptBuilder.onlyMainPerson(MakeupStudio.instruction(for: recipe))
                                if text.count > longest.count { longest = text }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(longest.count, PromptBuilder.maxPromptLength, longest)
        XCTAssertEqual(PromptBuilder.sanitize(longest), longest)
        XCTAssertLessThanOrEqual(PromptBuilder.editInstruction(longest).count, 1000) // MAX_PROMPT_LENGTH on the server
    }

    // MARK: Policy (the app and the server run the same lists)

    func testEveryLookPassesThePolicyAsSent() {
        for (index, preset) in MakeupStudio.presets.enumerated() {
            // A hair color now and then, and "Only edit me" every other time.
            let hair = MakeupHair.allCases[index % MakeupHair.allCases.count]
            let text = sent(preset.recipe.withHair(hair), onlyMe: index.isMultiple(of: 2))
            XCTAssertEqual(ContentPolicy.evaluate(text, operation: .magicEdit), .allowed, text)
        }
    }

    /// Every recipe, without checking 100,000 whole prompts. A blocked term is
    /// at most `longestTerm` words, and every sentence but the last has at
    /// least `longestTerm - 1`, so a match lies inside one sentence or across
    /// two neighbours, within `longestTerm - 1` words of their boundary.
    /// Recipes with up to two of eyes, lips, cheeks and extras (with every
    /// intensity and hair color) have every sentence and every pair of
    /// neighbours that any recipe can have, so checking each sentence and the
    /// words around each boundary covers every recipe as the server sees it.
    func testEveryCombinationPassesThePolicy() {
        let terms = [ContentPolicy.compiled.sexual, ContentPolicy.compiled.revealingClothing,
                     ContentPolicy.compiled.humiliation, ContentPolicy.compiled.appearanceChange].flatMap { $0 }
        let longestTerm = terms.compactMap { $0.tokens?.count }.max() ?? 0
        XCTAssertGreaterThan(longestTerm, 1)
        let edge = longestTerm - 1

        enum Area { case eyes(MakeupEyes), lips(MakeupLips), cheeks(MakeupCheeks), extras(Set<MakeupExtra>) }
        let areas: [[Area]] = [
            MakeupEyes.allCases.dropFirst().map(Area.eyes),
            MakeupLips.allCases.dropFirst().map(Area.lips),
            MakeupCheeks.allCases.dropFirst().map(Area.cheeks),
            Self.extraSets.map(Area.extras),
        ]
        func apply(_ area: Area, to recipe: inout MakeupRecipe) {
            switch area {
            case .eyes(let eyes): recipe.eyes = eyes
            case .lips(let lips): recipe.lips = lips
            case .cheeks(let cheeks): recipe.cheeks = cheeks
            case .extras(let extras): recipe.extras = extras
            }
        }
        var bases: [MakeupRecipe] = [MakeupRecipe()]
        for (index, first) in areas.enumerated() {
            for a in first {
                var single = MakeupRecipe()
                apply(a, to: &single)
                bases.append(single)
                for second in areas[(index + 1)...] {
                    for b in second {
                        var pair = single
                        apply(b, to: &pair)
                        bases.append(pair)
                    }
                }
            }
        }

        struct Neighbours: Hashable {
            let first: String
            let second: String
        }
        let onlyMe = Self.onlyMeSentence
        let editGuard = PromptBuilder.editGuard.trimmingCharacters(in: .whitespaces)
        // After the skin guard: "Only edit me" and then the edit guard, or the edit guard.
        var neighbours: Set<Neighbours> = [
            Neighbours(first: MakeupStudio.skinGuard, second: onlyMe),
            Neighbours(first: onlyMe, second: editGuard),
            Neighbours(first: MakeupStudio.skinGuard, second: editGuard),
        ]
        for base in bases {
            for hair in MakeupHair.allCases {
                for intensity in MakeupIntensity.allCases {
                    var recipe = base.withHair(hair)
                    recipe.intensity = intensity
                    let parts = MakeupStudio.sentences(for: recipe)
                    XCTAssertEqual(parts.isEmpty, recipe.isEmpty)
                    for (a, b) in zip(parts, parts.dropFirst()) { neighbours.insert(Neighbours(first: a, second: b)) }
                }
            }
        }

        let sentences = Set(neighbours.flatMap { [$0.first, $0.second] })
        var words: [String: [String]] = [:]
        for sentence in sentences {
            words[sentence] = ContentPolicy.words(in: sentence)
            XCTAssertGreaterThanOrEqual(words[sentence]?.count ?? 0, edge, sentence)
        }
        let boundaries = Set(neighbours.map { pair in
            (words[pair.first, default: []].suffix(edge) + words[pair.second, default: []].prefix(edge)).joined(separator: " ")
        })
        XCTAssertGreaterThan(sentences.count, 40)
        XCTAssertGreaterThan(boundaries.count, 100)
        for text in sentences.union(boundaries) {
            XCTAssertEqual(ContentPolicy.evaluate(text, operation: .magicEdit), .allowed, text)
        }
    }

    /// Belt and braces for the test above: a few whole prompts, picked at random.
    func testSampledCombinationsPassThePolicy() {
        var generator = SeededGenerator(seed: 2026_10_14)
        for _ in 0..<8 {
            var recipe = MakeupRecipe(
                lips: MakeupLips.allCases.randomElement(using: &generator)!,
                eyes: MakeupEyes.allCases.randomElement(using: &generator)!,
                cheeks: MakeupCheeks.allCases.randomElement(using: &generator)!,
                extras: Set(MakeupExtra.allCases.filter { _ in Bool.random(using: &generator) }),
                hair: MakeupHair.allCases.randomElement(using: &generator)!,
                intensity: MakeupIntensity.allCases.randomElement(using: &generator)!
            )
            if recipe.isEmpty { recipe.lips = .rosy }
            let text = sent(recipe, onlyMe: Bool.random(using: &generator))
            XCTAssertEqual(ContentPolicy.evaluate(text, operation: .magicEdit), .allowed, text)
        }
    }

    // MARK: Words

    /// Makeup is play: no ratings, no "better", nothing sexual, no reshaping
    /// or skin changes, and no brand, celebrity or platform names, in the
    /// names on screen or in what the model is asked (the skin guard names
    /// what it rules out, so it's left out here).
    func testTheWordsStayKind() {
        let unkind: Set<String> = [
            "sexy", "sexier", "sultry", "seductive", "hot", "hotter", "pretty", "prettier", "beautiful", "beauty",
            "gorgeous", "attractive", "flawless", "perfect", "flaw", "flaws", "fix", "better", "ugly", "rate", "score",
            "slim", "slimmer", "thin", "thinner", "skinny", "younger", "older", "whiter", "whiten", "whitening",
            "lighter", "lighten", "lightening", "brighter", "brightening", "fairer", "paler", "tan", "tanned", "tanner",
            "plump", "plumper", "plumping", "fuller", "bigger", "larger", "enlarge", "enlarged", "wider", "lift", "lifted",
            "sculpt", "sculpted", "contour", "contoured", "slimming", "airbrush", "airbrushed", "filler", "botox",
            "smooth", "smoother", "poreless", "porcelain", "nude", "naked",
            "tiktok", "instagram", "snapchat", "pinterest", "youtube", "barbie", "kardashian", "fenty", "sephora",
            "glossier", "maybelline", "nyx", "rhode",
        ]
        var names = MakeupStudio.presets.map(\.name)
        names += MakeupLips.allCases.map(\.name) + MakeupEyes.allCases.map(\.name) + MakeupCheeks.allCases.map(\.name)
        names += MakeupExtra.allCases.map(\.name) + MakeupHair.allCases.map(\.name) + MakeupIntensity.allCases.map(\.name)
        for name in Set(names) {
            XCTAssertTrue(Set(ContentPolicy.words(in: name)).isDisjoint(with: unkind), name)
            XCTAssertTrue(ContentPolicy.evaluate(name, operation: .magicEdit).isAllowed, name)
        }
        // Every choice appears in one of these.
        var recipes = MakeupStudio.presets.map(\.recipe)
        recipes.append(MakeupRecipe(lips: .rosy, eyes: .glitterLid, cheeks: .sunKissed, extras: Set(MakeupExtra.allCases), hair: .copper))
        recipes += MakeupLips.allCases.map { MakeupRecipe(lips: $0, hair: .lilac) } + MakeupEyes.allCases.map { MakeupRecipe(eyes: $0) }
        recipes += MakeupCheeks.allCases.map { MakeupRecipe(cheeks: $0) } + MakeupHair.allCases.map { MakeupRecipe(hair: $0) }
        recipes += MakeupIntensity.allCases.map { MakeupRecipe(lips: .berry, intensity: $0) }
        for recipe in recipes {
            let text = MakeupStudio.instruction(for: recipe).replacingOccurrences(of: MakeupStudio.skinGuard, with: "")
            let words = Set(ContentPolicy.words(in: text))
            XCTAssertTrue(words.isDisjoint(with: unkind), "\(text): \(words.intersection(unkind).sorted())")
        }
    }

    // MARK: Helpers

    private static func isHexColor(_ text: String) -> Bool {
        text.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil
    }
}
