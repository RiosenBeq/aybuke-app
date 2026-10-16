import Foundation

/// What a blocked request was blocked for. The raw value is shared with the
/// backend (`_shared/policy-terms.json`, `_shared/policy-vectors.json`).
public enum PolicyCategory: String, CaseIterable, Codable, Sendable {
    case sexual
    case sexualMinor
    case revealingClothing
    case humiliation
    case appearanceChange
}

/// Lightweight client-side pre-check that rejects clearly disallowed requests
/// before they cost a credit or a network round-trip. It is NOT the safety
/// system: the backend runs the same lists (`_shared/policy.ts`, generated
/// terms in `_shared/policy-terms.json`), appends the edit guard and the
/// provider runs its own safety checker.
///
/// Term syntax: words separated by spaces must appear next to each other as
/// whole words; `a|b` matches either word, a trailing `*` matches the start of
/// a word (Turkish and Indonesian suffixes), and a trailing `?` makes that word
/// optional. A term with Chinese, Japanese
/// or Korean characters matches anywhere in the text. Both the terms and the
/// prompt go through `words(in:)` first, so diacritics, case, leetspeak,
/// stretched letters, lookalike letters from another script, invisible
/// characters, control characters inside a word and "b i k i n i" spacing
/// don't matter (a line break between words, or next to Chinese, Japanese or
/// Korean, still splits them); the prompt is also
/// matched squeezed (`squeezedWords(in:)`: "na.ked", "n@ked", "5exy").
public enum ContentPolicy {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case blocked(reason: String, category: PolicyCategory)

        public var isAllowed: Bool { self == .allowed }

        public var category: PolicyCategory? {
            if case .blocked(_, let category) = self { return category }
            return nil
        }
    }

    /// Messages stay `reason:` literals in this file: scripts/export-core-strings.py
    /// picks them up for translation, and the server sends them back verbatim.
    public static func verdict(for category: PolicyCategory) -> Verdict {
        switch category {
        case .sexualMinor:
            return .blocked(reason: "This request violates our content policy and can't be created.", category: .sexualMinor)
        case .sexual:
            return .blocked(reason: "Nudity and sexual content aren't allowed. Try a different idea.", category: .sexual)
        case .revealingClothing:
            return .blocked(reason: "Let's keep outfits cozy and everyday. Try a cozy knit, a party dress or a costume.", category: .revealingClothing)
        case .humiliation:
            return .blocked(reason: "Edits that make fun of someone aren't something we do. Try a fun scene instead.", category: .humiliation)
        case .appearanceChange:
            return .blocked(reason: "Aybuke keeps you, you. Try hair color, makeup colors, outfits, light or backgrounds.", category: .appearanceChange)
        }
    }

    public static func evaluate(_ prompt: String, operation: AIOperation) -> Verdict {
        let text = MatchText(prompt)
        let involvesMinor = compiled.minor.contains { text.matches($0) }
        if compiled.sexual.contains(where: { text.matches($0) }) {
            return verdict(for: involvesMinor ? .sexualMinor : .sexual)
        }
        // Every operation: a text prompt with no person noun still draws one.
        if compiled.revealingClothing.contains(where: { text.matches($0) }) {
            return verdict(for: involvesMinor ? .sexualMinor : .revealingClothing)
        }
        // A brand-new image has nobody to reshape or mock, and describing an
        // invented character ("a tall elf") is fine.
        guard operation != .textToImage else { return .allowed }
        if compiled.humiliation.contains(where: { text.matches($0) }) {
            return verdict(for: .humiliation)
        }
        if compiled.appearanceChange.contains(where: { text.matches($0) }) {
            return verdict(for: .appearanceChange)
        }
        return .allowed
    }

    // MARK: Terms

    static let sexualTerms: [String] = [
        "nude", "nudes", "naked", "nsfw", "porn", "porno", "pornographic", "sex", "sexual", "sexy", "sexier",
        "topless", "lingerie", "undress", "undressed", "undressing", "nudify", "nipple", "nipples",
        "genital", "genitals", "erotic", "hentai", "xxx", "onlyfans",
        "remove clothes", "remove her|his|their|my clothes", "take off clothes", "take off her|his|their|my clothes",
        "without clothes", "no clothes", "see through clothes", "x ray clothes",
        "shirtless", "unclothed", "bare chested", "strip her|him|them|me down", "boobs", "her|his|my|their|your|me|big|bare tits",
        "remove her|his|their|my top|shirt|tshirt|blouse|dress|skirt|pants|jeans|bra|clothing", "remove her|his|their|my t shirt",
        "unbutton|lift her|his|their|my shirt|tshirt|blouse|dress|skirt|bra",
        "take|pull off|down her|his|their|my top|shirt|tshirt|blouse|dress|skirt|pants|jeans|bra|clothes|clothing",
        "take|pull off|down her|his|their|my t shirt", "remove clothing", "take off clothing", "bare chest",
        // tr
        "çıplak", "çırılçıplak", "seks", "seksi", "erotik", "üstsüz", "müstehcen", "soyunuk", "soyunmuş",
        "iç çamaşırı", "kıyafetsiz", "kıyafetlerini çıkar", "elbisesini çıkar", "soyundur*",
        "tişörtünü|üstünü|elbisesini|gömleğini|pantolonunu|eteğini|sütyenini|tişörtümü|üstümü|elbisemi|gömleğimi|pantolonumu|eteğimi|sütyenimi çıkar*",
        "onu|beni|onları soy", "soyun*",
        // es
        "desnuda", "desnudo", "desnudas", "desnudos", "desnudez", "sexo", "pornografía", "erótica", "erótico",
        "lencería", "tetas", "sin ropa", "quitar la ropa", "quítale la ropa", "ropa interior",
        // pt
        "nua", "nuas", "nudez", "pelada", "peladas", "pornô", "pornografia", "seios",
        "sem roupa", "tirar a roupa", "tire a roupa", "roupa íntima",
        // fr
        "nue", "nues", "nudité", "sexe", "sexuel", "sexuelle", "érotique", "déshabillée", "déshabiller", "seins",
        "sans vêtements", "enlever ses vêtements", "seins nus", "sous vêtements",
        // de
        "nackt", "nackte", "nackten", "nacktbild", "nacktbilder", "nacktheit", "erotisch", "erotische",
        "unterwäsche", "ausziehen", "busen", "ohne kleidung", "oben ohne", "kleidung ausziehen",
        // it
        "nuda", "nudo", "nudi", "sesso", "erotica", "erotico", "spogliata", "spogliare", "spogliarla",
        "senza vestiti", "togliere i vestiti", "biancheria intima",
        // ru
        "голая", "голый", "голые", "голую", "обнажённая", "обнаженную", "секс", "порно", "эротика", "эротический",
        "раздеть", "раздетая", "раздень", "сиськи", "голой", "голым", "голыми", "голышом", "обнажённой",
        "раздетой", "раздетую", "без одежды", "нижнее бельё", "сними одежду",
        // id
        "telanjang", "bugil", "erotis", "mesum", "payudara", "tanpa baju", "lepas baju", "pakaian dalam", "buka baju",
        // ja
        "ヌード", "全裸", "裸体", "エロ", "ポルノ", "脱がせ", "下着姿", "セクシー",
        // zh
        "色情", "裸照", "脱光", "黄图", "性感", "内衣照",
        // ko
        "누드", "나체", "알몸", "벗겨", "야동", "포르노", "섹시",
    ]

    /// Only sharpen the message of an otherwise blocked request.
    static let minorTerms: [String] = [
        "child", "children", "kid", "kids", "minor", "minors", "teen", "teens", "teenager",
        "underage", "boy", "girl", "baby", "toddler", "schoolgirl", "schoolboy", "loli", "preteen",
    ]

    static let revealingClothingTerms: [String] = [
        // Any language: the word is the same almost everywhere.
        "bikini*", "lingerie",
        // en
        "swimsuit*", "swimwear", "bathing suit*", "swim suit*", "underwear", "bra", "bras", "panties", "thong", "thongs",
        "cleavage", "seductive", "provocative", "skimpy", "revealing outfit|clothes|dress|top",
        "low cut", "less clothes|clothing", "fewer clothes", "see through dress|top|shirt|blouse|outfit",
        "sheer dress|top|blouse|outfit|lingerie",
        // tr ("mayo" alone is Spanish for May)
        "mayolu", "mayoyla", "mayo giy*", "sütyen*", "külot*", "tanga*", "dekolte*", "açık saçık",
        "kışkırtıcı", "baştan çıkarıcı", "az giyin*", "transparan elbise*|bluz*|kıyafet*",
        // es
        "bañador*", "traje de baño", "sujetador*", "brasier", "bragas", "escote pronunciado|profundo",
        "provocativa", "provocativo", "seductora", "poca ropa", "menos ropa",
        "ropa|vestido|blusa transparente",
        // pt
        "biquíni*", "roupa de banho", "traje de banho", "sutiã", "calcinha*", "fio dental", "decote profundo",
        "provocante", "sedutora", "pouca roupa", "roupa|vestido|blusa transparente",
        // fr
        "maillot de bain", "soutien gorge", "culotte", "en string", "décolleté plongeant", "provocante",
        "aguicheuse", "dénudée", "robe|tenue|chemise|haut transparente|transparent",
        // de
        "badeanzug*", "badeanzügen", "bh", "freizügig*", "verführerisch*", "aufreizend*",
        "tiefer|tiefen ausschnitt", "durchsichtiges|durchsichtige kleid|oberteil|top|bluse",
        // it ("costume" alone is the English word for a fun outfit)
        "costume da bagno", "costumi da bagno", "reggiseno", "mutandine", "perizoma", "scollatura profonda",
        "seducente", "vestito|abito|top|camicia trasparente",
        // ru
        "бикини", "купальник*", "лифчик*", "бюстгальтер*", "трусики", "трусы", "стринги", "декольте",
        "откровенн*", "соблазнительн*", "в белье", "прозрачн* плать*|блузк*|топ*|одежд*",
        // id
        "baju renang", "pakaian renang", "beha", "celana dalam", "kutang", "belahan dada",
        "baju transparan", "pakaian terbuka",
        // ja
        "ビキニ", "水着", "下着", "ブラジャー", "ランジェリー", "tバック", "谷間", "露出の多い", "露出度", "シースルー", "透けて",
        // zh
        "比基尼", "泳装", "泳衣", "内衣", "胸罩", "文胸", "内裤", "丁字裤", "乳沟", "透视装", "暴露",
        // ko
        "비키니", "수영복", "속옷", "브래지어", "팬티", "란제리", "가슴골", "노출 심한", "노출이 심한",
        "노출 많은", "노출이 많은", "시스루",
    ]

    /// Mocking or degrading someone. Subject-bound, so "ugly Christmas
    /// sweater", "fat cat" and Halloween makeup still work.
    static let humiliationTerms: [String] = [
        // en
        "make|makes|making|made|turn|turns|turning|turned her|him|them|everyone look ugly|uglier|fat|fatter|drunk|stupid|dumb|disgusting|gross|homeless|pathetic",
        "make|makes|making|made|turn|turns|turning|turned her|him|them ugly|uglier|fat|fatter|drunk|stupid|dumb|disgusting|gross",
        "make|makes|making|made|turn|turns|turning|turned me|my look ugly|uglier|drunk|stupid|disgusting|gross",
        "make her|him|them cry", "mugshot", "mug shot", "in jail", "in prison", "behind bars", "in handcuffs",
        "being|getting arrested", "arrest her|him|them|me", "beat her|him|them|me up", "look beaten up",
        // tr
        "onu|onları çirkin*|şişman*|sarhoş* yap*|göster*", "hapiste", "hapse at*", "tutuklan*", "kelepçeli",
        "sabıka fotoğraf*",
        // es
        "hazla|hazlo|hazlos|ponla|ponlo|ponlos fea|feo|feos|gorda|gordo|borracha|borracho",
        "en la cárcel", "en prisión", "arrestada", "arrestado", "esposada", "esposado", "foto policial",
        // pt
        "deixe|deixa ela|ele feia|feio|gorda|gordo|bêbada|bêbado", "na cadeia", "na prisão",
        "algemada", "algemado",
        // fr
        "rends|fais la|le|les moche|moches|laid|laide|grosse|gros|ivre|bourrée|bourré", "en prison",
        "derrière les barreaux", "menottée", "menotté", "photo d identité judiciaire",
        // de
        "mach|mache sie|ihn hässlich|hässlicher|fett|fetter|betrunken", "im gefängnis", "hinter gittern",
        "verhaftet", "in handschellen", "polizeifoto",
        // it
        "rendila|rendilo|rendili|falla|fallo brutta|brutto|grassa|grasso|ubriaca|ubriaco", "in prigione",
        "in carcere", "arrestata", "arrestato", "ammanettata", "ammanettato", "foto segnaletica",
        // ru
        "сделай её|его|их уродлив*|толст*|пьян*", "в тюрьме", "за решёткой", "арестован*", "в наручниках",
        // id
        "buat|bikin dia|mereka jelek|gendut|mabuk", "di penjara", "ditangkap polisi", "diborgol",
        // ja
        "ブサイクに", "不細工に", "逮捕", "刑務所", "牢屋", "マグショット", "酔っ払いに",
        // zh
        "变丑", "丑化", "坐牢", "监狱", "被逮捕", "被捕", "戴手铐", "嫌犯照",
        // ko
        "못생기게", "감옥", "체포", "수갑", "머그샷",
    ]

    /// Reshaping a face or body, changing skin tone either way, retouching skin
    /// or rating looks, including a poll question that asks friends to rate or
    /// compare her (or anyone's) body, weight, face or attractiveness. Subject-
    /// bound so "slim gold necklace", "make the lines thinner", "waist-length
    /// hair", "treasure chest" and "which sunset is prettier" still work.
    static let appearanceChangeTerms: [String] = [
        // en
        "make|makes|making|made|turn|turns|turning|turned me|her|him|them|us|everyone look? thinner|skinnier|slimmer|curvier|fatter|taller|shorter|prettier|hotter|cuter|whiter|paler|older|younger|skinny|thin|slim|curvy|attractive|beautiful|pretty|hot|fat|chubby|chubbier|heavier",
        "make|makes|making|made|turn|turns|turning|turned me|her|him|them|us|everyone look? more attractive|beautiful|pretty|handsome|hot|feminine",
        "make|turn me|her|him|them|us white|black|asian|caucasian|latina|latino",
        "make|makes|making|made my|her|his|their face|nose|lips|eyes|jaw|jawline|chin|cheeks|cheekbones|forehead|body|waist|hips|thighs|legs|arms|belly|stomach|tummy|butt|bust|breasts|boobs|chest|figure|skin look? smaller|bigger|larger|thinner|slimmer|skinnier|narrower|wider|fuller|plumper|longer|shorter|sharper|rounder|flatter|curvier|lighter|whiter|paler|darker|fairer|tanner|smoother|clearer|flawless|perfect",
        "smaller|thinner|slimmer|skinnier|narrower|bigger|larger|fuller|plumper|wider|longer|sharper|tinier|tiny|slim|thin|skinny nose|lips|eyes|face|jaw|jawline|chin|cheeks|cheekbones|forehead|waist|hips|thighs|legs|arms|belly|stomach|tummy|body|figure|butt|bust|breasts|boobs|chest",
        "v line", "vline", "v shaped face|jaw|jawline", "sharp|sharper|defined|chiseled jawline",
        "lose|losing weight", "weight loss", "slim down", "slim me|her|him|them down", "thigh gap", "six pack abs",
        "flat stomach|belly|tummy", "hourglass figure|body|shape", "double eyelid|eyelids",
        "lip filler|fillers|injection|injections", "botox", "nose job", "rhinoplasty", "bbl", "liposuction",
        "breast implants", "facelift", "face lift", "plastic surgery",
        "smooth|soften my|her|his|their skin|face", "give me|her|him|them abs|sixpack", "give me|her|him|them a six pack",
        "lighter|whiter|darker|paler|fairer|tanner|brighter skin|complexion|skintone",
        "lighter|whiter|darker|paler|fairer skin tone", "skin whitening|lightening|bleaching|brightening",
        "whiten|lighten|bleach|darken my|her|his|their skin|complexion",
        "change my|her|his|their skin color|colour|tone", "change my|her|his|their race|ethnicity",
        "flawless|perfect|smooth|smoother|poreless|porcelain|airbrushed skin", "airbrush me|her|him|them",
        "airbrush my|her|his|their face|skin",
        "remove|erase|hide|clear|delete|fix my|her|his|their|the? acne|pimples|pimple|zits|blemishes|wrinkles|pores|scars|moles|freckles",
        "rid of my|her|his|their|the? acne|pimples|zits|blemishes|wrinkles|pores|freckles",
        "rate me", "rate|rating|rank|score my|her|his|their|our looks|face|faces|body|bodies|appearance|figure|beauty|attractiveness|hotness|weight",
        "how pretty|hot|attractive|ugly|fat|skinny|thin|beautiful am|is i|she|he", "am i pretty|ugly|hot|attractive", "hot or not", "smash or pass",
        // Asking friends to rate or compare looks ("do I look fat in this", "who's hotter", "which pic is my body better in").
        "i|she|he|we look|looks|looked|looking the? more|most? fat|fatter|fattest|chubby|chubbier|heavier|skinny|skinnier|skinniest|thin|thinner|thinnest|slim|slimmer|slimmest|curvier|ugly|uglier|ugliest|prettier|prettiest|hotter|hottest|attractive|beautiful|gorgeous|sexier",
        "i m|am the? more|most? fat|fatter|fattest|chubby|chubbier|heavier|skinny|skinnier|skinniest|thin|thinner|thinnest|slim|slimmer|slimmest|curvier|ugly|uglier|ugliest|prettier|prettiest|hotter|hottest|attractive|beautiful|gorgeous|sexier", "am|is|are i|she|he|we the? more|most? fat|fatter|fattest|chubby|chubbier|heavier|skinny|skinnier|skinniest|thin|thinner|thinnest|slim|slimmer|slimmest|curvier|ugly|uglier|ugliest|prettier|prettiest|hotter|hottest|attractive|beautiful|gorgeous|sexier",
        "who|whos s|is|looks|was? the? more|most? fat|fatter|fattest|chubby|chubbier|heavier|skinny|skinnier|skinniest|thin|thinner|thinnest|slim|slimmer|slimmest|curvier|ugly|uglier|ugliest|prettier|prettiest|hotter|hottest|attractive|beautiful|gorgeous|sexier|pretty|hot",
        "of us is|are|looks|look the? more|most? fat|fatter|fattest|chubby|chubbier|heavier|skinny|skinnier|skinniest|thin|thinner|thinnest|slim|slimmer|slimmest|curvier|ugly|uglier|ugliest|prettier|prettiest|hotter|hottest|attractive|beautiful|gorgeous|sexier|pretty|hot",
        "my|her|his|our|their body|figure|weight|face|legs|thighs|waist|stomach|belly|tummy|arms|butt|hips|chest|boobs|bust|nose|jaw|jawline|cheeks|chin look|looks|looked better|best|worse|nicer",
        "is|was my|her|his|our|their body|figure|weight|legs|thighs|waist|stomach|belly|tummy|arms|butt|hips|chest|boobs|bust|nose|jaw|jawline|cheeks|chin better|best|worse|nicer",
        "my|her|his|our|their body|figure|weight|face|legs|thighs|waist|stomach|belly|tummy|arms|butt|hips|chest|boobs|bust|nose|jaw|jawline|cheeks|chin look|looks|looked|is|are|was thinner|slimmer|skinnier|fatter|chubbier|prettier|hotter|uglier|flatter|curvier|sexier",
        // tr
        "zayıflat*", "beni|onu daha zayıf|ince|güzel|çekici|seksi|beyaz|esmer|uzun|kilolu|şişman|genç|yaşlı yap*|göster*",
        "beni|onu|yüzümü|yüzünü güzelleştir*|incelt*|beyazlat*|esmerleştir*",
        "yüzümü|yüzünü|göğsümü|göğsünü|göğüslerimi|göğüslerini|kalçamı|kalçasını|popomu|poposunu|burnumu|burnunu|dudaklarımı|dudaklarını|gözlerimi|gözlerini|belimi|belini|bacaklarımı|bacaklarını|kollarımı|kollarını|vücudumu|vücudunu|çenemi|çenesini incelt*|küçült*|büyüt*|zayıflat*|dolgunlaştır*|şişir*|uzat*",
        "kilo ver*", "tenimi|cildimi|tenini|cildini beyazlat*|açıklaştır*|aydınlat*|pürüzsüzleştir*|koyulaştır*|esmerleştir*",
        "pürüzsüz|kusursuz|mükemmel cilt|ten", "sivilce*|akne*|kırışık* sil*|kaldır*|gider*|temizle*|yok",
        "dudak dolgu*", "burun estetiğ*", "estetik ameliyat*", "şişmanlat*",
        "daha? zayıf|şişman|kilolu|şişko|tombul|çirkin|güzel|çekici|ince|seksi|yakışıklı görünüyorum|gözüküyorum|duruyorum|görünürüm|görünüyordum|görünmüşüm|çıkmışım|çıkıyorum",
        "zayıf|şişman|kilolu|şişko|tombul|çirkin|güzel|çekici|ince|seksi|yakışıklı görünüyor|gözüküyor|duruyor|görünür|çıkmış|çıkıyor muyum|müyüm|mıyım|miyim",
        "zayıf|şişman|kilolu|şişko|tombul|çirkin|güzel|çekici|ince|seksi|yakışıklı|hoş miyim|mıyım|muyum|müyüm",
        "daha|en zayıfım|şişmanım|kiloluyum|şişkoyum|tombulum|çirkinim|güzelim|çekiciyim|inceyim|yakışıklıyım",
        "beni|bizi daha? zayıf|şişman|kilolu|şişko|tombul|çirkin|güzel|çekici|ince|seksi|yakışıklı göster*", "daha? zayıf|şişman|kilolu|şişko|tombul göster*",
        "kim|hangimiz|hanginiz daha|en zayıf|şişman|kilolu|şişko|tombul|çirkin|güzel|çekici|ince|seksi|yakışıklı|hoş",
        "yüzümü|vücudumu|bedenimi|görünüşümü|fiziğimi|güzelliğimi|beni|bizi puanla*",
        "yüzümü|vücudumu|bedenimi|görünüşümü|fiziğimi|güzelliğimi değerlendir*|oyla*",
        "yüzüme|vücuduma|bedenime|görünüşüme|fiziğime|güzelliğime|bana|bize puan ver*",
        "vücudum|bacaklarım|belim|karnım|kalçam|göğsüm|burnum|kollarım|fiziğim|bedenim daha|en iyi|güzel|ince|zayıf|şişman|kilolu|düz|kötü",
        "yüzüm daha|en iyi|güzel|ince|zayıf|şişman|kilolu|düz|kötü görünüyor*|gözüküyor*|duruyor*|çıkıyor*|çıkmış*|görünür*",
        // es
        "hazme|ponme|hazla|ponla|hazlo|ponlo ver|lucir|parecer? más? delgada|delgado|flaca|flaco|alta|alto|bonita|bonito|guapa|guapo|linda|lindo|atractiva|atractivo|blanca|blanco|curvilínea|joven",
        "adelgázame", "adelgázala", "adelgázalo", "bajar|perder de? peso",
        "nariz más pequeña|chica|fina|respingada", "labios más grandes|gruesos|carnosos", "ojos más grandes",
        "cintura más pequeña|fina|delgada|estrecha", "piel más clara|blanca|oscura|lisa|perfecta",
        "piel perfecta|impecable|lisa|blanca|clara", "aclarar|aclárame|blanquear|blanquéame mi|la|su|tu piel",
        "quita|quítame|quitar|elimina|elimíname|eliminar|borra|bórrame|borrar mis|los|sus|el|tus? granos|acné|espinillas|imperfecciones|arrugas",
        "relleno de labios", "cirugía estética",
        "me|te hace|hacen|hizo|haría|hacía ver|lucir|parecer? más? delgada|delgado|flaca|flaco|gorda|gordo|gordita|gordito|rellenita|rellenito|fea|feo|bonita|bonito|guapa|guapo|linda|lindo|atractiva|atractivo|hermosa|hermoso|sexy",
        "la|lo|las|los hace|hacen|hizo|haría|hacía ver|lucir|parecer? más? delgada|delgado|flaca|flaco|gorda|gordo|gordita|gordito|rellenita|rellenito|fea|feo",
        "me veo|vería|veía|miro|noto más? delgada|delgado|flaca|flaco|gorda|gordo|gordita|gordito|rellenita|rellenito|fea|feo|bonita|bonito|guapa|guapo|linda|lindo|atractiva|atractivo|hermosa|hermoso|sexy", "salgo|salí más? delgada|delgado|flaca|flaco|gorda|gordo|gordita|gordito|rellenita|rellenito|fea|feo|bonita|bonito|guapa|guapo|linda|lindo|atractiva|atractivo|hermosa|hermoso|sexy",
        "estoy|soy|estás|eres|parezco|pareces más? delgada|delgado|flaca|flaco|gorda|gordo|gordita|gordito|rellenita|rellenito|fea|feo|bonita|bonito|guapa|guapo|linda|lindo|atractiva|atractivo|hermosa|hermoso|sexy",
        "quién|quien es|está|luce? el|la? más? delgada|delgado|flaca|flaco|gorda|gordo|gordita|gordito|rellenita|rellenito|fea|feo|bonita|bonito|guapa|guapo|linda|lindo|atractiva|atractivo|hermosa|hermoso|sexy",
        "quién|quien se ve el|la? más? delgada|delgado|flaca|flaco|gorda|gordo|gordita|gordito|rellenita|rellenito|fea|feo|bonita|bonito|guapa|guapo|linda|lindo|atractiva|atractivo|hermosa|hermoso|sexy",
        "califica|calificar|puntúa|puntuar|valora|evalúa mi|su|nuestra|nuestro|tu cuerpo|cara|figura|cintura|abdomen|barriga|panza|nariz|piernas|rostro|trasero|físico|apariencia|belleza",
        "califícame|califícanos|puntúame|puntúanos|valórame",
        "mi|su|nuestro|nuestra cuerpo|cara|figura|cintura|abdomen|barriga|panza|nariz|piernas|rostro|trasero se? ve|luce|queda mejor|peor",
        "mi|su|nuestro|nuestra cuerpo|cara|figura|cintura|abdomen|barriga|panza|nariz|piernas|rostro|trasero se? ve|luce|queda más? delgada|delgado|flaca|flaco|gorda|gordo|gordita|gordito|rellenita|rellenito|fea|feo|bonita|bonito|guapa|guapo|linda|lindo|atractiva|atractivo|hermosa|hermoso|sexy", "ve|luce|queda mejor mi|su cuerpo|cara|figura|cintura|abdomen|barriga|panza|nariz|piernas|rostro|trasero",
        "senos|pechos|busto más grandes|grande", "aumentar|agrandar mis|sus|los senos|pechos|glúteos",
        // pt
        "me deixe|deixa mais magra|magro|alta|alto|bonita|bonito|linda|lindo|gostosa|gostoso|atraente|branca|branco|clara|nova",
        "deixe|deixa me|ela|ele mais magra|magro|alta|alto|bonita|bonito|linda|lindo|gostosa|gostoso|atraente|branca|branco|clara",
        "emagrec*", "perder peso", "nariz menor", "nariz mais fino|fina|pequeno", "lábios maiores", "lábios mais grossos|carnudos|grandes",
        "olhos maiores", "cintura mais fina", "pele mais clara|branca|escura|lisa", "pele perfeita|lisa|clara",
        "clarear|branquear minha|a|sua pele",
        "tirar|tire|remover|remova|apagar|apague as|minhas|meus|suas|seus espinhas|acne|cravos|imperfeições|rugas",
        "preenchimento labial", "cirurgia plástica",
        "me|te deixa|deixam|deixou|deixaria|deixando|faz|fazem|fez|faria parecer|ficar? mais? magra|magro|gorda|gordo|gordinha|gordinho|feia|feio|cheinha|bonita|bonito|linda|lindo|gostosa|gostoso|atraente|bela|belo",
        "eu? pareço|fico|fiquei|ficaria|estou|sou|saio|saí mais? magra|magro|gorda|gordo|gordinha|gordinho|feia|feio|cheinha|bonita|bonito|linda|lindo|gostosa|gostoso|atraente|bela|belo",
        "quem é|está|fica|parece? a|o? mais? magra|magro|gorda|gordo|gordinha|gordinho|feia|feio|cheinha|bonita|bonito|linda|lindo|gostosa|gostoso|atraente|bela|belo",
        "avalie|avalia|avaliem|julgue|julga|julguem meu|minha|nosso|nossa corpo|rosto|cara|barriga|cintura|nariz|pernas|bunda|coxas|físico|aparência|beleza",
        "me avalie|avaliem|avalia", "nota pro|para|pra|ao? meu|minha|nosso|nossa corpo|rosto|cara|barriga|cintura|nariz|pernas|bunda|coxas|físico|aparência|beleza",
        "meu|minha corpo|rosto|cara|barriga|cintura|nariz|pernas|bunda|coxas|físico fica|ficou|parece|está melhor|pior",
        "meu|minha corpo|rosto|cara|barriga|cintura|nariz|pernas|bunda|coxas|físico fica|ficou|parece|está mais? magra|magro|gorda|gordo|gordinha|gordinho|feia|feio|cheinha|bonita|bonito|linda|lindo|gostosa|gostoso|atraente|bela|belo",
        // fr
        "rends|fais moi|la|le plus? mince|minces|maigre|fine|grande|belle|jolie|sexy|attirante|blanche|claire|jeune",
        "maigrir", "amincis*", "amincir", "perdre du poids", "affine mon|ma|mes|son|sa|ses visage|nez|taille|corps|cuisses|jambes|bras",
        "nez plus petit|fin", "lèvres plus grosses|pulpeuses", "yeux plus grands", "taille plus fine",
        "peau plus claire|blanche|foncée|lisse", "peau parfaite|lisse|claire", "peau sans défauts|imperfections",
        "éclaircir|blanchir|éclaircis|blanchis ma|sa|la peau|teint",
        "enlève|enlever|retire|retirer|efface|effacer mes|ses|les acné|imperfections|rides",
        "enlève|retire|efface mes|ses boutons", "injections dans les lèvres", "chirurgie esthétique",
        "me|te rend|rends|rendent|rendait|rendrait|fait|font|faisait|ferait paraître|sembler? plus? mince|minces|maigre|grosse|gros|moche|moches|laide|laid|belle|beau|jolie|joli|sexy|attirante|attirant|canon",
        "m|t|me|te affine|affinent|amincit|amincissent|grossit|grossissent",
        "je suis|parais|semble|fais plus? mince|minces|maigre|grosse|gros|moche|moches|laide|laid|belle|beau|jolie|joli|sexy|attirante|attirant|canon", "suis je plus? mince|minces|maigre|grosse|gros|moche|moches|laide|laid|belle|beau|jolie|joli|sexy|attirante|attirant|canon", "j ai l air plus? mince|minces|maigre|grosse|gros|moche|moches|laide|laid|belle|beau|jolie|joli|sexy|attirante|attirant|canon",
        "qui est|sont|parait|semble le|la|les plus mince|minces|maigre|grosse|gros|moche|moches|laide|laid|belle|beau|jolie|joli|sexy|attirante|attirant|canon", "de nous|vous est le|la? plus? mince|minces|maigre|grosse|gros|moche|moches|laide|laid|belle|beau|jolie|joli|sexy|attirante|attirant|canon",
        "note|notez|noter|évalue|évaluez|juge|jugez mon|ma|notre corps|visage|silhouette|ventre|nez|cuisses|jambes|fesses|physique|beauté|apparence|tête",
        "note|notez|évalue|évaluez moi|nous",
        "mon|ma corps|visage|silhouette|ventre|nez|cuisses|jambes|fesses|physique rend|parait|semble mieux", "mon|ma corps|visage|silhouette|ventre|nez|cuisses|jambes|fesses|physique est|rend|parait|semble plus? mince|minces|maigre|grosse|gros|moche|moches|laide|laid|belle|beau|jolie|joli|sexy|attirante|attirant|canon",
        // de
        "mach|mache|macht mich|sie|ihn dünner|schlanker|schmaler|größer|hübscher|schöner|attraktiver|heißer|kurviger|dicker|heller|jünger|älter",
        "lass mich|sie|ihn abnehmen", "gewicht verlieren", "schlanke|schlankere|schmale|schmalere taille", "kleinere|schmalere nase", "größere|vollere lippen",
        "größere augen", "hellere|weißere|dunklere|glattere|makellose|perfekte haut", "haut aufhellen|bleichen|glätten",
        "pickel|akne|falten|hautunreinheiten entfernen|wegmachen|weg", "entferne|entfern meine|ihre|die pickel|akne|falten|hautunreinheiten",
        "lippen aufspritzen", "schönheitsoperation", "nasen op",
        "größere|größeren|vollere brüste|busen|oberweite", "brust|brüste vergrößern",
        "lässt|lasst|lassen|lass|ließ|liess|macht|machen|machte|mach|mache mich|dich|uns dünner|schlanker|schmaler|dicker|fetter|hübscher|schöner|hässlicher|attraktiver|heißer|heisser|kurviger|fülliger|magerer|dünn|schlank|dick|fett|hübsch|schön|hässlich|attraktiv",
        "sehe|seh|sah|wirke|wirk ich darin|da|hier|damit|so|dort? zu|so|viel|noch|am? dünn|dünner|dünnsten|schlank|schlanker|schlanksten|dick|dicker|dicksten|fett|fetter|hübsch|hübscher|hübschesten|schön|schöner|schönsten|hässlich|hässlicher|hässlichsten|attraktiv|attraktiver|attraktivsten|heiß|heißer|heißesten|heiss|heisser|mager|pummelig|moppelig",
        "ich sehe|seh|sah|wirke zu|so|viel|noch|am? dünn|dünner|dünnsten|schlank|schlanker|schlanksten|dick|dicker|dicksten|fett|fetter|hübsch|hübscher|hübschesten|schön|schöner|schönsten|hässlich|hässlicher|hässlichsten|attraktiv|attraktiver|attraktivsten|heiß|heißer|heißesten|heiss|heisser|mager|pummelig|moppelig",
        "bin|wäre|war ich zu|so|viel|noch|am? dünn|dünner|dünnsten|schlank|schlanker|schlanksten|dick|dicker|dicksten|fett|fetter|hübsch|hübscher|hübschesten|schön|schöner|schönsten|hässlich|hässlicher|hässlichsten|attraktiv|attraktiver|attraktivsten|heiß|heißer|heißesten|heiss|heisser|mager|pummelig|moppelig", "ich bin zu|so|viel|noch|am? dünn|dünner|dünnsten|schlank|schlanker|schlanksten|dick|dicker|dicksten|fett|fetter|hübsch|hübscher|hübschesten|schön|schöner|schönsten|hässlich|hässlicher|hässlichsten|attraktiv|attraktiver|attraktivsten|heiß|heißer|heißesten|heiss|heisser|mager|pummelig|moppelig",
        "wer von? uns|euch? ist|sieht|wirkt? am|der|die? dünn|dünner|dünnsten|schlank|schlanker|schlanksten|dick|dicker|dicksten|fett|fetter|hübsch|hübscher|hübschesten|schön|schöner|schönsten|hässlich|hässlicher|hässlichsten|attraktiv|attraktiver|attraktivsten|heiß|heißer|heißesten|heiss|heisser|mager|pummelig|moppelig",
        "bewerte|bewertet|bewerten|beurteile|beurteilt mein|meinen|meine|unser|unsere körper|gesicht|figur|bauch|beine|taille|nase|po|hintern|aussehen|schönheit|attraktivität",
        "bewerte|bewertet|beurteile|beurteilt mich|uns",
        "mein|meine|meinen körper|gesicht|figur|bauch|beine|taille|nase|po|hintern sieht|wirkt hier|da|darin|damit|so|dort? besser|dünner|schlanker|schmaler|dicker|fetter|hübscher|schöner|hässlicher|attraktiver|heißer|heisser|kurviger|fülliger|magerer|flacher",
        "sieht|wirkt mein|meine körper|gesicht|figur|bauch|beine|taille|nase|po|hintern hier|da|darin|damit|so|dort? besser|dünner|schlanker|schmaler|dicker|fetter|hübscher|schöner|hässlicher|attraktiver|heißer|heisser|kurviger|fülliger|magerer|flacher",
        "mein|meine körper|gesicht|figur|bauch|beine|taille|nase|po|hintern ist|wirkt dünner|schlanker|schmaler|dicker|fetter|hübscher|schöner|hässlicher|attraktiver|heißer|heisser|kurviger|fülliger|magerer",
        // it
        "rendimi|fammi|rendila|falla|rendilo|fallo più? magra|magro|snella|snello|alta|alto|bella|bello|carina|carino|attraente|bianca|chiara|sexy",
        "dimagr*", "perdere peso", "naso più piccolo|fino|sottile", "labbra più grandi|carnose|piene", "occhi più grandi",
        "vita più stretta|sottile|fina", "pelle più chiara|bianca|scura|liscia", "pelle perfetta|liscia|chiara",
        "schiarire|sbiancare|schiarisci|sbianca la|mia|sua pelle", "pelle senza imperfezioni",
        "togli|toglimi|rimuovi|elimina|cancella i|miei|suoi|l|le|mie|sue? brufoli|acne|imperfezioni|rughe",
        "filler alle labbra", "chirurgia estetica",
        "mi|ti fa|fanno|faceva|farebbe|rende|rendono|rendeva sembrare|apparire? più? magra|magro|snella|snello|grassa|grasso|cicciottella|cicciottello|grassoccia|brutta|brutto|bella|bello|carina|carino|attraente|sexy|figa|figo|gnocca",
        "la|lo|li|le fa|fanno|rende|rendono sembrare|apparire? più? magra|magro|snella|snello|grassa|grasso|cicciottella|cicciottello|grassoccia|brutta|brutto",
        "sembro|sono|appaio|esco|vengo|sto più? magra|magro|snella|snello|grassa|grasso|cicciottella|cicciottello|grassoccia|brutta|brutto|bella|bello|carina|carino|attraente|sexy|figa|figo|gnocca",
        "chi è|sta|sembra? il|la? più? magra|magro|snella|snello|grassa|grasso|cicciottella|cicciottello|grassoccia|brutta|brutto|bella|bello|carina|carino|attraente|sexy|figa|figo|gnocca",
        "di noi|voi è|sta|sembra il|la? più? magra|magro|snella|snello|grassa|grasso|cicciottella|cicciottello|grassoccia|brutta|brutto|bella|bello|carina|carino|attraente|sexy|figa|figo|gnocca",
        "vota|votate|valuta|valutate|giudica|giudicate|voto il|la|al|alla? mio|mia|nostro|nostra viso|faccia|corpo|aspetto|fisico|bellezza|lineamenti",
        "valutami|giudicami|valutateci",
        "mio|mia corpo|viso|faccia|fisico|pancia|naso|gambe|sedere|fianchi sta|sembra|appare meglio|peggio",
        "mio|mia corpo|viso|faccia|fisico|pancia|naso|gambe|sedere|fianchi è|sta|sembra|appare più? magra|magro|snella|snello|grassa|grasso|cicciottella|cicciottello|grassoccia|brutta|brutto|bella|bello|carina|carino|attraente|sexy|figa|figo|gnocca",
        // ru
        "сделай меня|её|его худее|стройнее|выше|красивее|симпатичнее|сексуальнее|тоньше|светлее|белее|моложе",
        "похуд*", "уменьши|уменьшить нос|губы|талию|лицо|бёдра|ноги|подбородок", "увеличь|увеличить губы|глаза|грудь",
        "отбели|отбелить|осветли|осветлить кожу|лицо", "кожу|кожа светлее|белее|темнее|глаже",
        "идеальная|идеальную|гладкая|гладкую|безупречная|безупречную кожа|кожу",
        "убери|убрать|удали|удалить прыщи|акне|морщины|прыщики", "пластическ* операци*",
        "делает|делают|сделает|сделало|сделал|сделала меня|нас ещё? худее|стройнее|тоньше|толще|полнее|жирнее|красивее|симпатичнее|привлекательнее|сексуальнее|уродливее|страшнее",
        "делает|делают|сделает|сделало|сделал|сделала её|ее|его ещё? худее|стройнее|толще|полнее|жирнее",
        "выгляжу|выглядела|выглядел|смотрюсь|смотрелась|кажусь|казалась ли? я? более|ещё|самой? худее|стройнее|тоньше|толще|полнее|жирнее|красивее|симпатичнее|привлекательнее|сексуальнее|уродливее|страшнее|толстой|толстая|толстый|толстым|жирной|жирная|жирный|полной|полная|полным|худой|худая|худым|тощей|тощая|стройной|стройная|красивой|красивая|красивый|красивым|некрасивой|некрасивая|страшной|страшная|уродливой|уродливая|уродиной|уродина|симпатичной|симпатичная|привлекательной|привлекательная",
        "я худее|стройнее|тоньше|толще|полнее|жирнее|красивее|симпатичнее|привлекательнее|сексуальнее|уродливее|страшнее|толстой|толстая|толстый|толстым|жирной|жирная|жирный|полной|полная|полным|худой|худая|худым|тощей|тощая|стройной|стройная|красивой|красивая|красивый|красивым|некрасивой|некрасивая|страшной|страшная|уродливой|уродливая|уродиной|уродина|симпатичной|симпатичная|привлекательной|привлекательная", "кто из? нас|вас? более|самая|самый? худее|стройнее|тоньше|толще|полнее|жирнее|красивее|симпатичнее|привлекательнее|сексуальнее|уродливее|страшнее|толстой|толстая|толстый|толстым|жирной|жирная|жирный|полной|полная|полным|худой|худая|худым|тощей|тощая|стройной|стройная|красивой|красивая|красивый|красивым|некрасивой|некрасивая|страшной|страшная|уродливой|уродливая|уродиной|уродина|симпатичной|симпатичная|привлекательной|привлекательная",
        "оцени|оцените|оценить моё|мою|мой|наше|нашу|наши? лицо|тело|внешность|фигуру|красоту|внешку",
        "оцени|оцените меня|нас", "полнит|полнят|стройнит|стройнят|худит",
        "моё|моя|мой|мои тело|лицо|фигура|живот|талия|нос|ноги|попа выглядит|выглядят|смотрится|смотрятся|кажется лучше|хуже",
        "моё|моя|мой|мои тело|лицо|фигура|живот|талия|нос|ноги|попа выглядит|выглядят|смотрится|смотрятся|кажется? худее|стройнее|тоньше|толще|полнее|жирнее|красивее|симпатичнее|привлекательнее|сексуальнее|уродливее|страшнее",
        // id
        "buat|bikin aku|saya|dia|gue|gw lebih kurus|langsing|ramping|tinggi|cantik|putih|seksi|mancung|tirus",
        "kurusin*", "kuruskan*", "langsingkan*", "langsingin*", "tiruskan*", "mancungkan*", "mancungin*",
        "putihkan*|putihin*|cerahkan*|cerahin* kulit*", "kulit|wajah lebih putih|cerah|mulus|terang", "kulit mulus",
        "turun* berat badan", "hidung lebih kecil|mancung", "bibir lebih tebal|besar", "pinggang lebih kecil|ramping",
        "hilangkan*|hapus*|ilangin* jerawat*|flek|kerutan",
        "membuat|buat|bikin|bikinin aku|saya|gue|gw|kamu|dia kelihatan|keliatan|terlihat|tampak|jadi? lebih? kurus|langsing|ramping|gemuk|gendut|jelek|cantik|ganteng|cakep|seksi|tembem|gemukan|kurusan|chubby|buncit",
        "membuatku|bikinku kelihatan|keliatan|terlihat|tampak|jadi? lebih? kurus|langsing|ramping|gemuk|gendut|jelek|cantik|ganteng|cakep|seksi|tembem|gemukan|kurusan|chubby|buncit",
        "aku|saya|gue|gw kelihatan|keliatan|kliatan|terlihat|tampak lebih|paling? kurus|langsing|ramping|gemuk|gendut|jelek|cantik|ganteng|cakep|seksi|tembem|gemukan|kurusan|chubby|buncit",
        "aku|saya|gue|gw lebih|paling kurus|langsing|ramping|gemuk|gendut|jelek|cantik|ganteng|cakep|seksi|tembem|gemukan|kurusan|chubby|buncit", "aku|saya|gue|gw kurus|langsing|ramping|gemuk|gendut|jelek|cantik|ganteng|cakep|seksi|tembem|gemukan|kurusan|chubby|buncit ga|gak|nggak|ngga|enggak|kah|tidak",
        "apakah|apa aku|saya|gue|gw kurus|langsing|ramping|gemuk|gendut|jelek|cantik|ganteng|cakep|seksi|tembem|gemukan|kurusan|chubby|buncit", "siapa yang? lebih|paling kurus|langsing|ramping|gemuk|gendut|jelek|cantik|ganteng|cakep|seksi|tembem|gemukan|kurusan|chubby|buncit",
        "nilai|nilailah|nilaiin|ratein badanku|tubuhku|wajahku|mukaku|perutku|pahaku|pinggangku|lenganku|hidungku|pipiku|penampilanku|fisikku",
        "nilai|nilailah|nilaiin|ratein wajah|muka|badan|tubuh|penampilan|fisik aku|saya|gue|gw|kami",
        "badanku|tubuhku|wajahku|mukaku|perutku|pahaku|pinggangku|lenganku|hidungku|pipiku kelihatan|keliatan|terlihat|tampak lebih|paling bagus|baik|kurus|langsing|ramping|gemuk|gendut|jelek|cantik|ganteng|cakep|seksi|tembem|gemukan|kurusan|chubby|buncit",
        "badan|tubuh|wajah|muka|perut aku|gue kelihatan|keliatan|terlihat|tampak lebih|paling bagus|baik|kurus|langsing|ramping|gemuk|gendut|jelek|cantik|ganteng|cakep|seksi|tembem|gemukan|kurusan|chubby|buncit",
        "operasi plastik",
        // ja
        "痩せ", "顔を細く", "脚を細く", "足を細く", "腕を細く", "ウエストを細く", "小顔", "鼻を小さく", "鼻を高く",
        "目を大きく", "唇を厚く", "唇を大きく", "美白", "肌を白く", "色白に", "美肌", "ニキビを消", "シミを消", "毛穴を消",
        "美人にして", "整形", "背を高く", "太らせ",
        "太って見え", "デブに見え", "デブ見え", "細見え", "太見え", "私太って", "私って太って", "私は太って", "私太った", "私って太った", "私デブ", "私ってデブ", "私はデブ",
        "私ブス", "私ってブス", "私はブス", "私ブサイク", "私ってブサイク", "私はブサイク", "私が可愛く見え", "私がかわいく見え", "私が綺麗に見え", "私がきれいに見え",
        "私が美人に見え", "私が細く見え", "私が一番可愛", "私が一番かわい", "私が一番美人", "私が一番綺麗", "私が一番きれい", "誰が一番可愛", "誰が一番かわい", "誰が一番美人",
        "誰が一番綺麗", "誰が一番きれい", "誰が一番イケメン", "誰が一番ブス", "誰が可愛いか", "誰がかわいいか", "誰が可愛いと思", "誰がかわいいと思", "誰がより可愛", "誰がよりかわい", "誰が美人", "誰がイケメン", "誰がブス", "どっちが美人", "どっちがイケメン",
        "顔面偏差値", "顔を採点", "顔面を採点", "顔を評価", "顔面評価", "顔の点数", "顔は何点", "顔何点", "体を採点", "体型を採点", "スタイルを採点", "私を採点", "私は何点",
        "私何点", "ルックスを採点", "見た目を採点", "見た目は何点", "容姿を採点", "容姿を評価", "体型が良く見え", "体型がよく見え", "スタイルが良く見え", "スタイルよく見え",
        "脚が細く見え", "足が細く見え", "脚が長く見え", "足が長く見え", "顔が細く見え", "私を可愛く", "私をかわいく", "私を綺麗にして", "私をきれいにして", "私を綺麗に見せ", "私をきれいに見せ", "私を美人に", "私を細く",
        // zh
        "瘦一点", "瘦一些", "变瘦", "更瘦", "瘦脸", "瘦身", "瘦腿", "瘦腰", "显瘦", "眼睛变大", "眼睛大一点", "放大眼睛",
        "瓜子脸", "v脸", "鼻子变小", "鼻子小一点", "高鼻梁", "隆鼻", "丰唇", "嘴唇变厚", "美白", "皮肤变白",
        "肤色变浅", "肤色变深", "磨皮", "祛痘", "去痘", "去掉痘痘", "去斑", "完美皮肤", "完美肌肤", "美颜",
        "我变漂亮", "我更漂亮", "我变美", "我更美", "我变好看", "她变漂亮", "她更漂亮", "她变美", "她更美",
        "整容", "长高", "丰胸", "变胖",
        "显胖", "我胖了", "我胖吗", "我胖不胖", "我好胖", "我很胖", "我太胖", "我丑吗", "我丑不丑", "我好丑", "我很丑", "我太丑", "我瘦了", "我瘦吗", "我瘦不瘦", "我好瘦", "我很瘦", "我太瘦", "我漂亮吗", "我好看吗", "我美吗", "我帅吗", "我是不是很胖", "我是不是胖", "我是不是太胖", "我是不是很瘦", "我是不是瘦", "我是不是太瘦", "我是不是很丑", "我是不是丑",
        "我看起来胖", "我看起来更胖", "我看起来瘦", "我看起来更瘦", "我看起来丑", "我看起来更丑", "我看起来更漂亮", "我看起来更好看", "我看起来更美", "我看着胖", "我看着瘦",
        "我显得胖", "我显得瘦", "我更瘦", "我更胖", "我更好看", "我更丑", "我更帅", "谁更漂亮", "谁更好看", "谁更美", "谁更帅", "谁更丑", "谁更胖", "谁更瘦",
        "谁最漂亮", "谁最好看", "谁最美", "谁最帅", "谁最丑", "谁比较漂亮", "谁比较好看", "颜值打分", "颜值评分", "颜值几分", "颜值多少", "测颜值", "我的颜值",
        "给我的脸打分", "给我打分", "给我们打分", "给我的身材打分", "身材打分", "长相打分", "外貌打分", "脸打分", "身材更好", "身材最好", "我的身材好", "我的身材怎么样", "我的身材如何", "我的身材更", "我的身材是不是", "我的身材看起来", "我的身材显", "显身材", "显腿长",
        "腿显长", "显脸小", "脸显小",
        // ko
        "날씬하게", "마르게", "살 빼", "살빼", "얼굴 작게", "얼굴을 작게", "브이라인", "v라인", "턱 깎", "코를 높게",
        "코 높게", "코를 작게", "눈을 크게", "눈 크게", "입술을 두껍게", "입술 크게", "피부를 하얗게", "피부 하얗게",
        "미백", "피부 보정", "뽀샵", "잡티 제거", "여드름 제거", "여드름 지워", "잡티 지워", "나를 더 예쁘게",
        "날 더 예쁘게", "나를 예쁘게", "날 예쁘게", "얼굴을 예쁘게", "얼굴 예쁘게", "키 크게", "성형", "뚱뚱하게",
        "날씬해 보", "날씬해보", "뚱뚱해 보", "뚱뚱해보", "살쪄 보", "살쪄보", "내가 통통해", "나 통통해 보", "나 통통해보", "내가 말라 보", "나 말라 보", "내가 너무 말라", "나 너무 말라", "내가 뚱뚱", "나 뚱뚱해", "나 살쪄",
        "나 살쪘", "내가 살쪘", "내가 못생", "나 못생겼", "내가 예뻐 보", "내가 예뻐보", "내가 예뻐요", "내가 예쁘게 나왔", "내가 예쁘게 보여", "내가 예쁘게 보이", "내가 예쁜지", "내가 예쁜가", "내가 예쁘냐", "내가 예쁘니", "내가 더 예뻐", "내가 더 예쁘게 나왔", "내가 더 예쁘게 나온", "내가 더 예쁘게 보여", "내가 더 예쁘게 보이", "내가 더 예쁜", "내가 제일 예뻐", "내가 제일 예쁘게 나왔", "내가 제일 예쁘게 나온", "누가 더 예뻐", "누가 더 예쁜", "누가 더 예쁘다", "누가 더 예쁘냐", "누가 더 예쁘니", "누가 더 예쁘지", "누가 더 예쁘게 나왔", "누가 제일 예뻐",
        "누가 제일 예쁜", "누가 제일 예쁘다", "누가 제일 예쁘냐", "누가 제일 예쁘니", "누가 제일 예쁘지", "누가 제일 예쁘게 나왔", "누가 예뻐", "누가 예쁜지", "누가 예쁘냐", "누가 예쁘니", "누가 더 잘생", "누가 제일 잘생", "누가 잘생", "누가 더 못생", "누가 더 날씬", "누가 더 뚱뚱", "누가더예뻐",
        "누가더예쁜", "누가더예쁘냐", "누가더예쁘니", "얼굴 평가", "얼굴평가", "얼평", "몸평", "외모 평가", "외모평가", "외모 점수", "외모점수", "얼굴 점수", "얼굴점수", "몸매 평가", "몸매평가",
        "몸매 점수", "몸매점수", "나 몇 점", "나 몇점", "몸매가 더 좋", "몸매 더 좋", "몸매가 좋아 보", "몸매 좋아 보", "몸매가 더 나아", "몸매가 더 예뻐",
        "몸매가 더 날씬",
    ]

    /// Everything the backend needs to run the same check
    /// (scripts/export-catalog.sh writes it to `_shared/policy-terms.json`).
    public static var exportedTerms: [String: [String]] {
        [
            "sexual": sexualTerms,
            "minor": minorTerms,
            "revealingClothing": revealingClothingTerms,
            "humiliation": humiliationTerms,
            "appearanceChange": appearanceChangeTerms,
        ]
    }

    public static var exportedMessages: [String: String] {
        var messages: [String: String] = [:]
        for category in PolicyCategory.allCases {
            if case .blocked(let reason, _) = verdict(for: category) { messages[category.rawValue] = reason }
        }
        return messages
    }

    // MARK: Matching

    struct Term: Equatable {
        struct Token: Equatable {
            var exact: Set<String> = []
            var prefixes: [String] = []
            var isOptional = false
        }

        /// Whole-word tokens, or nil for a CJK term.
        var tokens: [Token]?
        /// Normalised text for a CJK term.
        var substring: String = ""
    }

    struct Compiled {
        let sexual: [Term]
        let minor: [Term]
        let revealingClothing: [Term]
        let humiliation: [Term]
        let appearanceChange: [Term]
    }

    static let compiled = Compiled(
        sexual: sexualTerms.compactMap(compile),
        minor: minorTerms.compactMap(compile),
        revealingClothing: revealingClothingTerms.compactMap(compile),
        humiliation: humiliationTerms.compactMap(compile),
        appearanceChange: appearanceChangeTerms.compactMap(compile)
    )

    /// Terms that can't match because an alternative normalises to more or
    /// fewer than one word. Tests keep this empty.
    static var invalidTerms: [String] {
        exportedTerms.values.flatMap { $0 }.filter { compile($0) == nil }
    }

    static func compile(_ term: String) -> Term? {
        if term.unicodeScalars.contains(where: isCJK) {
            let text = words(in: term).joined(separator: " ")
            return text.isEmpty ? nil : Term(tokens: nil, substring: text)
        }
        var tokens: [Term.Token] = []
        for rawToken in term.split(separator: " ") {
            var token = Term.Token()
            var raw = String(rawToken)
            if raw.hasSuffix("?") {
                token.isOptional = true
                raw.removeLast()
            }
            for alternative in raw.split(separator: "|") {
                var text = String(alternative)
                let isPrefix = text.hasSuffix("*")
                if isPrefix { text.removeLast() }
                let normalized = words(in: text)
                guard normalized.count == 1 else { return nil }
                if isPrefix { token.prefixes.append(normalized[0]) } else { token.exact.insert(normalized[0]) }
            }
            tokens.append(token)
        }
        guard !tokens.isEmpty, tokens.contains(where: { !$0.isOptional }) else { return nil }
        return Term(tokens: tokens)
    }

    /// The prompt's words twice: as written, and squeezed ("na.ked", "n@ked").
    /// A term matches if it matches either view.
    struct MatchText {
        let views: [View]

        init(_ text: String) {
            // Control characters dropped or split on, each read plain and squeezed. A term matches any reading.
            let candidates = [
                View(ContentPolicy.words(in: text)),
                View(ContentPolicy.words(in: text, splitControls: true)),
                View(ContentPolicy.squeezedWords(in: text)),
                View(ContentPolicy.squeezedWords(in: text, splitControls: true)),
            ]
            var unique: [View] = []
            for view in candidates where !unique.contains(where: { $0.joined == view.joined }) {
                unique.append(view)
            }
            views = unique
        }

        func matches(_ term: Term) -> Bool {
            views.contains { $0.matches(term) }
        }
    }

    struct View {
        /// Each word with its stretched-letter variants ("skinnnier" → "skinnier", "skinier").
        let forms: [[String]]
        let joined: String

        init(_ words: [String]) {
            forms = words.map(ContentPolicy.forms(of:))
            joined = words.joined(separator: " ")
        }

        func matches(_ term: Term) -> Bool {
            guard let tokens = term.tokens else { return joined.contains(term.substring) }
            return forms.indices.contains { matches(tokens[...], at: $0) }
        }

        private func matches(_ tokens: ArraySlice<Term.Token>, at index: Int) -> Bool {
            guard let token = tokens.first else { return true }
            if index < forms.count, Self.matches(token, forms[index]), matches(tokens.dropFirst(), at: index + 1) {
                return true
            }
            return token.isOptional && matches(tokens.dropFirst(), at: index)
        }

        private static func matches(_ token: Term.Token, _ forms: [String]) -> Bool {
            forms.contains { form in
                token.exact.contains(form) || token.prefixes.contains { form.hasPrefix($0) }
            }
        }
    }

    // MARK: Normalisation (mirrored exactly in backend/.../_shared/policy.ts)

    /// NFKC, lowercase, Latin diacritics and Turkish dotless i folded, ё → е;
    /// split on anything that isn't a letter or digit; lookalike letters read
    /// in the word's script ("n\u{0430}ked", with a Cyrillic а); leetspeak undone in
    /// words that start with a letter ("s3xy", but not "1990s" or "3d"); runs
    /// of three or more single letters joined ("b i k i n i", "s.e.x").
    /// Invisible characters can't split a word ("bi\u{200B}kini"), and neither
    /// can control characters: they are dropped first, or split on with
    /// `splitControls` ("remove\nher" keeps its line break as a word break);
    /// next to Chinese, Japanese or Korean they always split (`dropControls`).
    static func words(in text: String, splitControls: Bool = false) -> [String] {
        let cleaned = splitControls ? clean(text) : dropControls(clean(text))
        return joinSpelledOut(tokens(in: cleaned).map(foldConfusables).map(undoLeet))
    }

    /// The same text squeezed: punctuation inside a run of non-space
    /// characters joins the pieces ("na.ked", "se-xy"), @ $ ! read as a s i,
    /// and leetspeak is undone in any word with a letter ("5exy"). Chunks
    /// with Chinese, Japanese or Korean characters keep their usual words:
    /// joining across 。 could form a term from two words. Control characters
    /// are dropped (`dropControls`), or split on with `splitControls`.
    static func squeezedWords(in text: String, splitControls: Bool = false) -> [String] {
        var chunks: [String] = []
        var chunk = String.UnicodeScalarView()
        for scalar in (splitControls ? clean(text) : dropControls(clean(text))).unicodeScalars {
            if scalar.properties.isWhitespace || scalar.properties.generalCategory == .control {
                if !chunk.isEmpty { chunks.append(String(chunk)) }
                chunk = String.UnicodeScalarView()
            } else {
                chunk.append(scalar)
            }
        }
        if !chunk.isEmpty { chunks.append(String(chunk)) }
        var result: [String] = []
        for piece in chunks {
            if piece.unicodeScalars.contains(where: isCJK) {
                result.append(contentsOf: tokens(in: piece))
                continue
            }
            var joined = String.UnicodeScalarView()
            for scalar in piece.unicodeScalars {
                let mapped = symbolLeet[scalar] ?? scalar
                if isWordScalar(mapped) { joined.append(mapped) }
            }
            if !joined.isEmpty { result.append(String(joined)) }
        }
        return joinSpelledOut(result.map(foldConfusables).map(undoLeetFully))
    }

    /// NFKC, lowercase and folded; invisible characters (format characters
    /// such as zero-width and bidi controls, combining marks, Hangul fillers)
    /// and control characters other than tabs and line breaks removed.
    static func clean(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in fold(text.precomposedStringWithCompatibilityMapping.lowercased()).unicodeScalars {
            switch scalar.properties.generalCategory {
            case .format, .nonspacingMark, .enclosingMark:
                continue
            case .control where !isSpacingControl(scalar):
                continue
            default:
                if isFiller(scalar) { continue }
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// Control characters removed before the split (`clean` keeps tabs and
    /// line breaks), so they can't split a word ("bi\tkini"). Next to Chinese,
    /// Japanese or Korean a run of them becomes a space instead: with no spaces
    /// between words, dropping a line break would join two words into a term
    /// ("女性\n感谢你" holds "性感"). A term broken by one then passes, as it
    /// already does when broken by a space or 。.
    static func dropControls(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard scalars[index].properties.generalCategory == .control else {
                result.append(scalars[index])
                index += 1
                continue
            }
            var end = index
            while end + 1 < scalars.count, scalars[end + 1].properties.generalCategory == .control { end += 1 }
            let neighbours = [index > 0 ? scalars[index - 1] : nil, end + 1 < scalars.count ? scalars[end + 1] : nil]
            if neighbours.contains(where: { $0.map(isCJK) ?? false }) { result.append(" ") }
            index = end + 1
        }
        return String(result)
    }

    static func tokens(in text: String) -> [String] {
        var words: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isWordScalar(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                words.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { words.append(String(current)) }
        return words
    }

    /// Tabs, line breaks and the like: kept by `clean`; `words` and `squeezedWords` drop them, or split on them with `splitControls`.
    static func isSpacingControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x1C...0x1F, 0x85: return true
        default: return false
        }
    }

    /// Hangul fillers: letters that draw nothing.
    static func isFiller(_ scalar: Unicode.Scalar) -> Bool {
        [0x115F, 0x1160, 0x3164, 0xFFA0].contains(scalar.value)
    }

    /// Cyrillic and Greek letters that look Latin, read as Latin inside a mostly Latin word.
    static let asLatin: [Unicode.Scalar: Unicode.Scalar] = [
        "\u{0430}": "a", "\u{0432}": "b", "\u{0441}": "c", "\u{0435}": "e", "\u{043D}": "h", "\u{0456}": "i",
        "\u{0458}": "j", "\u{043A}": "k", "\u{043C}": "m", "\u{043E}": "o", "\u{0440}": "p", "\u{0455}": "s",
        "\u{0442}": "t", "\u{0443}": "y", "\u{0445}": "x", "\u{0501}": "d", "\u{04CF}": "l",
        "\u{03B1}": "a", "\u{03B2}": "b", "\u{03B5}": "e", "\u{03B9}": "i", "\u{03BA}": "k", "\u{03BD}": "v",
        "\u{03BF}": "o", "\u{03C1}": "p", "\u{03C4}": "t", "\u{03C5}": "u", "\u{03C7}": "x",
    ]

    /// Latin letters that look Cyrillic, read as Cyrillic inside a mostly Cyrillic word.
    static let asCyrillic: [Unicode.Scalar: Unicode.Scalar] = [
        "a": "\u{0430}", "b": "\u{0432}", "c": "\u{0441}", "e": "\u{0435}", "h": "\u{043D}", "k": "\u{043A}",
        "m": "\u{043C}", "o": "\u{043E}", "p": "\u{0440}", "t": "\u{0442}", "x": "\u{0445}", "y": "\u{0443}",
    ]

    /// A word mixing Latin with Cyrillic or Greek, read in its main script ("n\u{0430}ked", "г\u{006F}лая").
    static func foldConfusables(_ word: String) -> String {
        var latin = 0, cyrillic = 0, greek = 0
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x61...0x7A, 0xDF...0x24F, 0x1E00...0x1EFF: latin += 1
            case 0x400...0x52F: cyrillic += 1
            case 0x370...0x3FF, 0x1F00...0x1FFF: greek += 1
            default: break
            }
        }
        guard latin > 0, cyrillic + greek > 0 else { return word }
        let table = cyrillic > latin ? asCyrillic : asLatin
        return String(String.UnicodeScalarView(word.unicodeScalars.map { table[$0] ?? $0 }))
    }

    static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0131: scalars.append("i") // ı
            case 0x0307: continue // the dot "İ" leaves behind when lowercased
            case 0x0451: scalars.append("\u{0435}") // ё → е
            case 0x03C2: scalars.append("\u{03C3}") // ς → σ: JavaScript lowercases a word-final Σ to ς, Swift to σ
            case 0x00C0...0x024F, 0x1E00...0x1EFF:
                let decomposed = String(Character(scalar)).decomposedStringWithCanonicalMapping.unicodeScalars
                scalars.append(contentsOf: decomposed.filter { !(0x0300...0x036F).contains($0.value) })
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    static let leet: [Unicode.Scalar: Unicode.Scalar] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t"]

    /// Read as letters only in the squeezed view ("n@ked", "$exy", "b!k!n!").
    static let symbolLeet: [Unicode.Scalar: Unicode.Scalar] = ["@": "a", "$": "s", "!": "i"]

    static func undoLeet(_ word: String) -> String {
        guard let first = word.unicodeScalars.first, !isNumber(first),
              word.unicodeScalars.contains(where: { leet[$0] != nil }) else { return word }
        return String(String.UnicodeScalarView(word.unicodeScalars.map { leet[$0] ?? $0 }))
    }

    /// The squeezed view's leetspeak: any word with a letter in it ("5exy").
    static func undoLeetFully(_ word: String) -> String {
        guard word.unicodeScalars.contains(where: isLetter),
              word.unicodeScalars.contains(where: { leet[$0] != nil }) else { return word }
        return String(String.UnicodeScalarView(word.unicodeScalars.map { leet[$0] ?? $0 }))
    }

    static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    static func isNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    static func joinSpelledOut(_ words: [String]) -> [String] {
        var result: [String] = []
        var run: [String] = []
        func flush() {
            if run.count >= 3 { result.append(run.joined()) } else { result.append(contentsOf: run) }
            run.removeAll()
        }
        for word in words {
            if word.unicodeScalars.count == 1 {
                run.append(word)
            } else {
                flush()
                result.append(word)
            }
        }
        flush()
        return result
    }

    /// Doubled letters stay: real words would collide ("tangga", "nuée").
    static func forms(of word: String) -> [String] {
        let scalars = Array(word.unicodeScalars)
        var longestRun = 1, run = 1
        for index in scalars.indices.dropFirst() {
            run = scalars[index] == scalars[index - 1] ? run + 1 : 1
            longestRun = max(longestRun, run)
        }
        guard longestRun >= 3 else { return [word] }
        return [word, collapse(scalars, keeping: 2), collapse(scalars, keeping: 1)]
    }

    static func collapse(_ scalars: [Unicode.Scalar], keeping limit: Int) -> String {
        var result = String.UnicodeScalarView()
        var run = 0
        for (index, scalar) in scalars.enumerated() {
            run = index > 0 && scalars[index - 1] == scalar ? run + 1 : 1
            if run <= limit { result.append(scalar) }
        }
        return String(result)
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }
}
