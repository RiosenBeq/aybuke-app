// A second net for lines Aybik writes to sit next to her photo (look-finder
// reasons, poll question ideas, card text): no talk of bodies, faces, skin or
// weight, and no rating or ranking anyone's looks. The prompt policy
// (policy.ts) runs first and catches most of it in every language; this adds
// the plain words a kind, vibe-only line never needs ("hotter", "skinny",
// "body", "rate"), in the app's languages. A match only drops that line: it's
// never a block or a strike, so a few false alarms cost nothing but an idea.
//
// Words are matched whole, after policy.ts's normalisation (case, Latin
// diacritics and Turkish dotless i folded: "Körper" is "korper"); Chinese,
// Japanese and Korean have no spaces, so their terms are matched as
// substrings. Words that are mostly about something else are left out on
// purpose ("hot" chocolate, "gros bisous", 肌寒い chilly, 笑顔 smile, 얼굴 in a
// smiling face, Turkish "yüz" also meaning a hundred).
import { words } from "./policy.ts";

const WORDS = new Set([
  // English
  "hotter",
  "hottest",
  "hotness",
  "sexy",
  "sexier",
  "sexiest",
  "prettier",
  "prettiest",
  "attractive",
  "unattractive",
  "attractiveness",
  "ugly",
  "uglier",
  "ugliest",
  "skinny",
  "skinnier",
  "thin",
  "thinner",
  "slim",
  "slimmer",
  "slimming",
  "fat",
  "fatter",
  "chubby",
  "curvy",
  "weight",
  "diet",
  "body",
  "bodies",
  "figure",
  "waist",
  "thighs",
  "abs",
  "face",
  "faces",
  "skin",
  "nose",
  "jawline",
  "flawless",
  "rate",
  "rating",
  "ranking",
  // Turkish
  "vucut",
  "vucudu",
  "kilo",
  "kilolu",
  "zayif",
  "sisman",
  "seksi",
  "cirkin",
  "cilt",
  "diyet",
  // Spanish
  "cuerpo",
  "peso",
  "delgada",
  "delgado",
  "flaca",
  "gorda",
  "gordo",
  "fea",
  "feo",
  "piel",
  "guapa",
  "atractiva",
  "atractivo",
  "dieta",
  // Portuguese
  "corpo",
  "magra",
  "magro",
  "feia",
  "feio",
  "pele",
  "rosto",
  "gostosa",
  "atraente",
  // French
  "corps",
  "poids",
  "mince",
  "maigre",
  "grosse",
  "moche",
  "laide",
  "peau",
  "visage",
  "attirante",
  "regime",
  // German
  "korper",
  "gewicht",
  "dunn",
  "hasslich",
  "gesicht",
  "hubscher",
  "hubscheste",
  "figur",
  "attraktiv",
  "diat",
  // Italian
  "grassa",
  "grasso",
  "brutta",
  "brutto",
  "pelle",
  "viso",
  // Russian
  "тело",
  "вес",
  "худая",
  "худой",
  "толстая",
  "толстый",
  "некрасивая",
  "кожа",
  "лицо",
  "фигура",
  "сексуальная",
  "красивее",
  "диета",
  // Indonesian
  "tubuh",
  "kurus",
  "gemuk",
  "jelek",
  "kulit",
  "wajah",
  "seksi",
]);

/** Chinese, Japanese and Korean terms, matched anywhere in the line. */
const SUBSTRINGS = [
  // Japanese
  "体型",
  "体重",
  "痩せ",
  "太っ",
  "ブス",
  "顔面",
  "美肌",
  "セクシー",
  "ダイエット",
  // Korean
  "몸매",
  "몸무게",
  "체중",
  "다이어트",
  "살빼",
  "날씬",
  "뚱뚱",
  "못생",
  "피부",
  "섹시",
  "외모",
  // Chinese
  "身材",
  "减肥",
  "瘦",
  "胖",
  "丑",
  "皮肤",
  "颜值",
  "性感",
  "外貌",
];

/** "9/10", "out of 10": a score. */
const SCORE = /\b\d{1,2}\s*\/\s*10\b|\bout of (?:10|ten)\b/iu;

/** True when the line talks about bodies, faces, skin or weight, or rates looks. */
export function talksAboutLooks(text: string): boolean {
  if (words(text).some((word) => WORDS.has(word))) return true;
  const plain = text.normalize("NFKC");
  if (SUBSTRINGS.some((term) => plain.includes(term))) return true;
  return SCORE.test(plain);
}
