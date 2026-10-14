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
/// stretched letters and "b i k i n i" spacing don't matter.
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
            return .blocked(reason: "Glowlit keeps you, you. Try hair color, makeup colors, outfits, light or backgrounds.", category: .appearanceChange)
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
        // tr
        "çıplak", "çırılçıplak", "seks", "seksi", "erotik", "üstsüz", "müstehcen", "soyunuk", "soyunmuş",
        "iç çamaşırı", "kıyafetsiz", "kıyafetlerini çıkar", "elbisesini çıkar", "soyundur*",
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
        "make|turn her|him|them|everyone look ugly|uglier|fat|fatter|drunk|stupid|dumb|disgusting|gross|homeless|pathetic",
        "make|turn her|him|them ugly|uglier|fat|fatter|drunk|stupid|dumb|disgusting|gross",
        "make me|my look ugly|uglier|drunk|stupid|disgusting|gross",
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
    /// or rating looks. Subject-bound so "slim gold necklace", "make the lines
    /// thinner", "waist-length hair" and "treasure chest" still work.
    static let appearanceChangeTerms: [String] = [
        // en
        "make|turn me|her|him|them|us|everyone look? thinner|skinnier|slimmer|curvier|fatter|taller|shorter|prettier|hotter|cuter|whiter|paler|older|younger|skinny|thin|slim|curvy|attractive|beautiful|pretty|hot",
        "make|turn me|her|him|them|us|everyone look? more attractive|beautiful|pretty|handsome|hot|feminine",
        "make|turn me|her|him|them|us white|black|asian|caucasian|latina|latino",
        "make my|her|his|their face|nose|lips|eyes|jaw|jawline|chin|cheeks|cheekbones|forehead|body|waist|hips|thighs|legs|arms|belly|stomach|tummy|butt|bust|breasts|boobs|chest|figure|skin smaller|bigger|larger|thinner|slimmer|skinnier|narrower|wider|fuller|plumper|longer|shorter|sharper|rounder|flatter|curvier|lighter|whiter|paler|darker|fairer|tanner|smoother|clearer|flawless|perfect",
        "smaller|thinner|slimmer|skinnier|narrower|bigger|larger|fuller|plumper|wider|longer|sharper|tinier|tiny|slim|thin|skinny nose|lips|eyes|face|jaw|jawline|chin|cheeks|cheekbones|forehead|waist|hips|thighs|legs|arms|belly|stomach|tummy|body|figure|butt|bust|breasts|boobs|chest",
        "v line", "vline", "v shaped face|jaw|jawline", "sharp|sharper|defined|chiseled jawline",
        "lose|losing weight", "weight loss", "slim down", "slim me|her|him|them down", "thigh gap", "six pack abs",
        "flat stomach|belly|tummy", "hourglass figure|body|shape", "double eyelid|eyelids",
        "lip filler|fillers|injection|injections", "botox", "nose job", "rhinoplasty", "bbl", "liposuction",
        "breast implants", "facelift", "face lift", "plastic surgery",
        "lighter|whiter|darker|paler|fairer|tanner|brighter skin|complexion|skintone",
        "lighter|whiter|darker|paler|fairer skin tone", "skin whitening|lightening|bleaching|brightening",
        "whiten|lighten|bleach|darken my|her|his|their skin|complexion",
        "change my|her|his|their skin color|colour|tone", "change my|her|his|their race|ethnicity",
        "flawless|perfect|smooth|smoother|poreless|porcelain|airbrushed skin", "airbrush me|her|him|them",
        "airbrush my|her|his|their face|skin",
        "remove|erase|hide|clear|delete|fix my|her|his|their|the? acne|pimples|pimple|zits|blemishes|wrinkles|pores|scars|moles|freckles",
        "rid of my|her|his|their|the? acne|pimples|zits|blemishes|wrinkles|pores|freckles",
        "rate me", "rate my|her|his looks|face|body|appearance",
        "how pretty|hot|attractive|ugly am i", "am i pretty|ugly|hot|attractive", "hot or not",
        // tr
        "zayıflat*", "beni|onu daha zayıf|ince|güzel|çekici|seksi|beyaz|esmer|uzun|kilolu|şişman|genç|yaşlı yap*|göster*",
        "beni|onu|yüzümü|yüzünü güzelleştir*|incelt*|beyazlat*|esmerleştir*",
        "yüzümü|yüzünü|burnumu|burnunu|dudaklarımı|dudaklarını|gözlerimi|gözlerini|belimi|belini|bacaklarımı|bacaklarını|kollarımı|kollarını|vücudumu|vücudunu|çenemi|çenesini incelt*|küçült*|büyüt*|zayıflat*|dolgunlaştır*|şişir*|uzat*",
        "kilo ver*", "tenimi|cildimi|tenini|cildini beyazlat*|açıklaştır*|aydınlat*|pürüzsüzleştir*|koyulaştır*|esmerleştir*",
        "pürüzsüz|kusursuz|mükemmel cilt|ten", "sivilce*|akne*|kırışık* sil*|kaldır*|gider*|temizle*|yok",
        "dudak dolgu*", "burun estetiğ*", "estetik ameliyat*",
        // es
        "hazme|ponme|hazla|ponla|hazlo|ponlo más? delgada|delgado|flaca|flaco|alta|alto|bonita|bonito|guapa|guapo|linda|lindo|atractiva|atractivo|blanca|blanco|curvilínea|joven",
        "adelgázame", "adelgázala", "adelgázalo", "bajar|perder de? peso",
        "nariz más pequeña|chica|fina|respingada", "labios más grandes|gruesos|carnosos", "ojos más grandes",
        "cintura más pequeña|fina|delgada|estrecha", "piel más clara|blanca|oscura|lisa|perfecta",
        "piel perfecta|impecable|lisa|blanca|clara", "aclarar|aclárame|blanquear|blanquéame mi|la|su|tu piel",
        "quita|quítame|quitar|elimina|elimíname|eliminar|borra|bórrame|borrar mis|los|sus|el|tus? granos|acné|espinillas|imperfecciones|arrugas",
        "relleno de labios", "cirugía estética",
        // pt
        "me deixe|deixa mais magra|magro|alta|alto|bonita|bonito|linda|lindo|gostosa|gostoso|atraente|branca|branco|clara|nova",
        "deixe|deixa me|ela|ele mais magra|magro|alta|alto|bonita|bonito|linda|lindo|gostosa|gostoso|atraente|branca|branco|clara",
        "emagrec*", "perder peso", "nariz menor", "nariz mais fino|fina|pequeno", "lábios maiores", "lábios mais grossos|carnudos|grandes",
        "olhos maiores", "cintura mais fina", "pele mais clara|branca|escura|lisa", "pele perfeita|lisa|clara",
        "clarear|branquear minha|a|sua pele",
        "tirar|tire|remover|remova|apagar|apague as|minhas|meus|suas|seus espinhas|acne|cravos|imperfeições|rugas",
        "preenchimento labial", "cirurgia plástica",
        // fr
        "rends|fais moi|la|le plus? mince|minces|maigre|fine|grande|belle|jolie|sexy|attirante|blanche|claire|jeune",
        "maigrir", "amincis*", "amincir", "perdre du poids", "affine mon|ma|mes|son|sa|ses visage|nez|taille|corps|cuisses|jambes|bras",
        "nez plus petit|fin", "lèvres plus grosses|pulpeuses", "yeux plus grands", "taille plus fine",
        "peau plus claire|blanche|foncée|lisse", "peau parfaite|lisse|claire", "peau sans défauts|imperfections",
        "éclaircir|blanchir|éclaircis|blanchis ma|sa|la peau|teint",
        "enlève|enlever|retire|retirer|efface|effacer mes|ses|les acné|imperfections|rides",
        "enlève|retire|efface mes|ses boutons", "injections dans les lèvres", "chirurgie esthétique",
        // de
        "mach|mache|macht mich|sie|ihn dünner|schlanker|schmaler|größer|hübscher|schöner|attraktiver|heißer|kurviger|dicker|heller|jünger|älter",
        "lass mich|sie|ihn abnehmen", "gewicht verlieren", "schlanke|schlankere|schmale|schmalere taille", "kleinere|schmalere nase", "größere|vollere lippen",
        "größere augen", "hellere|weißere|dunklere|glattere|makellose|perfekte haut", "haut aufhellen|bleichen|glätten",
        "pickel|akne|falten|hautunreinheiten entfernen|wegmachen|weg", "entferne|entfern meine|ihre|die pickel|akne|falten|hautunreinheiten",
        "lippen aufspritzen", "schönheitsoperation", "nasen op",
        // it
        "rendimi|fammi|rendila|falla|rendilo|fallo più? magra|magro|snella|snello|alta|alto|bella|bello|carina|carino|attraente|bianca|chiara|sexy",
        "dimagr*", "perdere peso", "naso più piccolo|fino|sottile", "labbra più grandi|carnose|piene", "occhi più grandi",
        "vita più stretta|sottile|fina", "pelle più chiara|bianca|scura|liscia", "pelle perfetta|liscia|chiara",
        "schiarire|sbiancare|schiarisci|sbianca la|mia|sua pelle", "pelle senza imperfezioni",
        "togli|toglimi|rimuovi|elimina|cancella i|miei|suoi|l|le|mie|sue? brufoli|acne|imperfezioni|rughe",
        "filler alle labbra", "chirurgia estetica",
        // ru
        "сделай меня|её|его худее|стройнее|выше|красивее|симпатичнее|сексуальнее|тоньше|светлее|белее|моложе",
        "похуд*", "уменьши|уменьшить нос|губы|талию|лицо|бёдра|ноги|подбородок", "увеличь|увеличить губы|глаза|грудь",
        "отбели|отбелить|осветли|осветлить кожу|лицо", "кожу|кожа светлее|белее|темнее|глаже",
        "идеальная|идеальную|гладкая|гладкую|безупречная|безупречную кожа|кожу",
        "убери|убрать|удали|удалить прыщи|акне|морщины|прыщики", "пластическ* операци*",
        // id
        "buat|bikin aku|saya|dia|gue|gw lebih kurus|langsing|ramping|tinggi|cantik|putih|seksi|mancung|tirus",
        "kurusin*", "kuruskan*", "langsingkan*", "langsingin*", "tiruskan*", "mancungkan*", "mancungin*",
        "putihkan*|putihin*|cerahkan*|cerahin* kulit*", "kulit|wajah lebih putih|cerah|mulus|terang", "kulit mulus",
        "turun* berat badan", "hidung lebih kecil|mancung", "bibir lebih tebal|besar", "pinggang lebih kecil|ramping",
        "hilangkan*|hapus*|ilangin* jerawat*|flek|kerutan",
        "operasi plastik",
        // ja
        "痩せ", "顔を細く", "脚を細く", "足を細く", "腕を細く", "ウエストを細く", "小顔", "鼻を小さく", "鼻を高く",
        "目を大きく", "唇を厚く", "唇を大きく", "美白", "肌を白く", "色白に", "美肌", "ニキビを消", "シミを消", "毛穴を消",
        "美人にして", "整形", "背を高く", "太らせ",
        // zh
        "瘦一点", "瘦一些", "变瘦", "更瘦", "瘦脸", "瘦身", "瘦腿", "瘦腰", "显瘦", "眼睛变大", "眼睛大一点", "放大眼睛",
        "瓜子脸", "v脸", "鼻子变小", "鼻子小一点", "高鼻梁", "隆鼻", "丰唇", "嘴唇变厚", "美白", "皮肤变白",
        "肤色变浅", "肤色变深", "磨皮", "祛痘", "去痘", "去掉痘痘", "去斑", "完美皮肤", "完美肌肤", "美颜",
        "我变漂亮", "我更漂亮", "我变美", "我更美", "我变好看", "她变漂亮", "她更漂亮", "她变美", "她更美",
        "整容", "长高", "丰胸", "变胖",
        // ko
        "날씬하게", "마르게", "살 빼", "살빼", "얼굴 작게", "얼굴을 작게", "브이라인", "v라인", "턱 깎", "코를 높게",
        "코 높게", "코를 작게", "눈을 크게", "눈 크게", "입술을 두껍게", "입술 크게", "피부를 하얗게", "피부 하얗게",
        "미백", "피부 보정", "뽀샵", "잡티 제거", "여드름 제거", "여드름 지워", "잡티 지워", "나를 더 예쁘게",
        "날 더 예쁘게", "나를 예쁘게", "날 예쁘게", "얼굴을 예쁘게", "얼굴 예쁘게", "키 크게", "성형", "뚱뚱하게",
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

    struct MatchText {
        /// Each word with its stretched-letter variants ("skinnnier" → "skinnier", "skinier").
        let forms: [[String]]
        let joined: String

        init(_ text: String) {
            let words = ContentPolicy.words(in: text)
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
    /// split on anything that isn't a letter or digit; leetspeak undone in
    /// words that start with a letter ("s3xy", but not "1990s" or "3d");
    /// runs of three or more single letters joined ("b i k i n i").
    static func words(in text: String) -> [String] {
        var words: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in fold(text.precomposedStringWithCompatibilityMapping.lowercased()).unicodeScalars {
            if isWordScalar(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                words.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { words.append(String(current)) }
        return joinSpelledOut(words.map(undoLeet))
    }

    static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0131: scalars.append("i") // ı
            case 0x0307: continue // the dot "İ" leaves behind when lowercased
            case 0x0451: scalars.append("\u{0435}") // ё → е
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

    static func undoLeet(_ word: String) -> String {
        guard let first = word.unicodeScalars.first, !isNumber(first),
              word.unicodeScalars.contains(where: { leet[$0] != nil }) else { return word }
        return String(String.UnicodeScalarView(word.unicodeScalars.map { leet[$0] ?? $0 }))
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
