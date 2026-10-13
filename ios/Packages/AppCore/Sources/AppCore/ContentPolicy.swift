import Foundation

/// Lightweight client-side pre-check that rejects clearly disallowed requests
/// before they cost a network round-trip. It is NOT the safety system: the
/// backend runs provider safety checkers and moderation on every request.
public enum ContentPolicy {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case blocked(reason: String)

        public var isAllowed: Bool { self == .allowed }
    }

    static let sexualTerms: Set<String> = [
        "nude", "nudes", "naked", "nsfw", "porn", "porno", "pornographic", "sex", "sexual", "sexy",
        "topless", "lingerie", "undress", "undressed", "undressing", "nudify", "nipple", "nipples",
        "genital", "genitals", "erotic", "hentai", "xxx", "onlyfans",
        // The app's other languages (whole words).
        // tr
        "çıplak", "çırılçıplak", "seks", "seksi", "erotik", "üstsüz", "müstehcen", "soyunuk", "soyunmuş",
        // es
        "desnuda", "desnudo", "desnudas", "desnudos", "desnudez", "sexo", "pornografía", "erótica", "erótico", "lencería", "tetas",
        // pt
        "nua", "nuas", "nudez", "pelada", "peladas", "pornô", "pornografia", "seios",
        // fr
        "nue", "nues", "nudité", "sexe", "sexuel", "sexuelle", "érotique", "déshabillée", "déshabiller", "seins",
        // de
        "nackt", "nackte", "nackten", "nacktbild", "nacktbilder", "nacktheit", "erotisch", "erotische", "unterwäsche", "ausziehen", "busen",
        // it
        "nuda", "nudo", "nudi", "sesso", "erotica", "erotico", "spogliata", "spogliare", "spogliarla",
        // ru
        "голая", "голый", "голые", "голую", "обнажённая", "обнаженная", "обнаженную", "секс", "порно", "эротика", "эротический", "раздеть", "раздетая", "раздень", "сиськи",
        "голой", "голым", "голыми", "голышом", "обнажённой", "обнаженной", "раздетой", "раздетую",
        // id
        "telanjang", "bugil", "seks", "erotis", "mesum", "payudara",
    ]

    static let minorTerms: Set<String> = [
        "child", "children", "kid", "kids", "minor", "minors", "teen", "teens", "teenager",
        "underage", "boy", "girl", "baby", "toddler", "schoolgirl", "schoolboy", "loli", "preteen",
    ]

    static let undressingPhrases: [String] = [
        "remove clothes", "remove her clothes", "remove his clothes", "remove their clothes",
        "take off clothes", "take off her clothes", "take off his clothes", "without clothes",
        "no clothes", "see through clothes", "x-ray clothes",
        // The app's other languages (matched inside the text; Japanese, Chinese
        // and Korean don't separate words with spaces).
        // tr
        "iç çamaşırı", "kıyafetsiz", "kıyafetlerini çıkar", "elbisesini çıkar", "soyundur",
        // es
        "sin ropa", "quitar la ropa", "quítale la ropa", "ropa interior",
        // pt
        "sem roupa", "tirar a roupa", "tire a roupa", "roupa íntima",
        // fr
        "sans vêtements", "enlever ses vêtements", "seins nus", "sous-vêtements",
        // de
        "ohne kleidung", "oben ohne", "kleidung ausziehen",
        // it
        "senza vestiti", "togliere i vestiti", "biancheria intima",
        // ru
        "без одежды", "нижнее белье", "нижнее бельё", "сними одежду",
        // id
        "tanpa baju", "lepas baju", "pakaian dalam", "buka baju",
        // ja
        "ヌード", "全裸", "裸体", "エロ", "ポルノ", "脱がせ", "下着姿", "セクシー",
        // zh
        "色情", "裸照", "裸体", "脱光", "黄图", "性感", "内衣照",
        // ko
        "누드", "나체", "알몸", "벗겨", "야동", "포르노", "섹시",
    ]

    public static func evaluate(_ prompt: String) -> Verdict {
        let lower = prompt.lowercased()
        let words = Set(lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let isSexual = !words.isDisjoint(with: sexualTerms) || undressingPhrases.contains { lower.contains($0) }
        guard isSexual else { return .allowed }
        if !words.isDisjoint(with: minorTerms) {
            return .blocked(reason: "This request violates our content policy and can't be created.")
        }
        return .blocked(reason: "Nudity and sexual content aren't allowed. Try a different idea.")
    }
}
