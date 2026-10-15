// Server-side prompt policy. Runs the same terms as ios/Packages/AppCore
// ContentPolicy.swift (exported to policy-terms.json by scripts/export-catalog.sh)
// with the same normalisation, before any provider call; the provider's own
// safety checker and the output checks run after it. Sexualised edits of real
// people are blocked outright (App Review 1.1.4, EU AI Act Art. 5(1)(ba) from
// 2 Dec 2026), and so are body, face and skin reshaping, revealing clothing
// and humiliating edits (teen safety). A block here is a strike (20261022
// migration). Shared test vectors: policy-vectors.json.

import policy from "./policy-terms.json" with { type: "json" };

export type Category = "sexual" | "sexualMinor" | "revealingClothing" | "humiliation" | "appearanceChange";
export type Verdict = { allowed: true } | { allowed: false; reason: string; category: Category };

/** Appended to every Magic Edit (PromptBuilder.editGuard in the app). */
export const EDIT_GUARD: string = policy.editGuard;

const MESSAGES: Record<string, string> = policy.messages;

type Token = { exact: Set<string>; prefixes: string[]; optional: boolean };
type Term = { tokens: Token[] } | { substring: string };

// MARK: Normalisation (mirrors ContentPolicy.swift exactly)

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t" };
/** Read as letters only in the squeezed view ("n@ked", "$exy", "b!k!n!"). */
const SYMBOL_LEET: Record<string, string> = { "@": "a", "$": "s", "!": "i" };
const WORD_CHAR = /^[\p{L}\p{N}]$/u;
const LETTER = /^\p{L}$/u;
const NUMBER_CHAR = /^\p{N}$/u;
/** Zero-width and bidi controls, soft hyphens, tag characters, combining marks (strikethrough, zalgo), variation selectors. */
const INVISIBLE = /^[\p{Cf}\p{Mn}\p{Me}]$/u;
const CONTROL = /^\p{Cc}$/u;
const BOUNDARY = /^[\p{White_Space}\p{Cc}]$/u;

/** Cyrillic and Greek letters that look Latin, read as Latin inside a mostly Latin word. */
const AS_LATIN: Record<string, string> = {
  "а": "a",
  "в": "b",
  "с": "c",
  "е": "e",
  "н": "h",
  "і": "i",
  "ј": "j",
  "к": "k",
  "м": "m",
  "о": "o",
  "р": "p",
  "ѕ": "s",
  "т": "t",
  "у": "y",
  "х": "x",
  "ԁ": "d",
  "ӏ": "l",
  "α": "a",
  "β": "b",
  "ε": "e",
  "ι": "i",
  "κ": "k",
  "ν": "v",
  "ο": "o",
  "ρ": "p",
  "τ": "t",
  "υ": "u",
  "χ": "x",
};
/** Latin letters that look Cyrillic, read as Cyrillic inside a mostly Cyrillic word. */
const AS_CYRILLIC: Record<string, string> = {
  a: "а",
  b: "в",
  c: "с",
  e: "е",
  h: "н",
  k: "к",
  m: "м",
  o: "о",
  p: "р",
  t: "т",
  x: "х",
  y: "у",
};

const isLatin = (cp: number) =>
  (cp >= 0x61 && cp <= 0x7a) || (cp >= 0xdf && cp <= 0x24f) || (cp >= 0x1e00 && cp <= 0x1eff);
const isCyrillic = (cp: number) => cp >= 0x400 && cp <= 0x52f;
const isGreek = (cp: number) => (cp >= 0x370 && cp <= 0x3ff) || (cp >= 0x1f00 && cp <= 0x1fff);
/** Hangul fillers: letters that draw nothing. */
const isFiller = (cp: number) => cp === 0x115f || cp === 0x1160 || cp === 0x3164 || cp === 0xffa0;
/** Tabs, line breaks and the like: kept by clean(); words() and squeezedWords() drop them, or split on them with splitControls. */
const isSpacingControl = (cp: number) => (cp >= 0x09 && cp <= 0x0d) || (cp >= 0x1c && cp <= 0x1f) || cp === 0x85;

function fold(text: string): string {
  let out = "";
  for (const ch of text) {
    const cp = ch.codePointAt(0)!;
    if (cp === 0x0131) out += "i"; // ı
    else if (cp === 0x0307) continue; // the dot "İ" leaves behind when lowercased
    else if (cp === 0x0451) out += "е"; // ё → е
    else if (cp === 0x03c2) out += "σ"; // ς → σ: JavaScript lowercases a word-final Σ to ς, Swift to σ
    else if ((cp >= 0x00c0 && cp <= 0x024f) || (cp >= 0x1e00 && cp <= 0x1eff)) {
      out += ch.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    } else out += ch;
  }
  return out;
}

/**
 * NFKC, lowercase and folded; invisible characters and non-spacing control
 * characters removed, so they can't split a word ("bi\u200bkini").
 */
export function clean(text: string): string {
  let out = "";
  for (const ch of fold(text.normalize("NFKC").toLowerCase())) {
    const cp = ch.codePointAt(0)!;
    if (INVISIBLE.test(ch) || isFiller(cp)) continue;
    if (CONTROL.test(ch) && !isSpacingControl(cp)) continue;
    out += ch;
  }
  return out;
}

function tokens(text: string): string[] {
  const result: string[] = [];
  let current = "";
  for (const ch of text) {
    if (WORD_CHAR.test(ch)) current += ch;
    else if (current) {
      result.push(current);
      current = "";
    }
  }
  if (current) result.push(current);
  return result;
}

/** A word mixing Latin with Cyrillic or Greek lookalikes, read in its main script ("n\u0430ked", "г\u006fлая"). */
export function foldConfusables(word: string): string {
  let latin = 0;
  let cyrillic = 0;
  let greek = 0;
  for (const ch of word) {
    const cp = ch.codePointAt(0)!;
    if (isLatin(cp)) latin++;
    else if (isCyrillic(cp)) cyrillic++;
    else if (isGreek(cp)) greek++;
  }
  if (latin === 0 || cyrillic + greek === 0) return word;
  const table = cyrillic > latin ? AS_CYRILLIC : AS_LATIN;
  return [...word].map((ch) => table[ch] ?? ch).join("");
}

function undoLeet(word: string): string {
  const chars = [...word];
  if (NUMBER_CHAR.test(chars[0]) || !chars.some((c) => c in LEET)) return word;
  return chars.map((c) => LEET[c] ?? c).join("");
}

/** The squeezed view's leetspeak: any word with a letter in it ("5exy"). */
function undoLeetFully(word: string): string {
  const chars = [...word];
  if (!chars.some((c) => LETTER.test(c)) || !chars.some((c) => c in LEET)) return word;
  return chars.map((c) => LEET[c] ?? c).join("");
}

function joinSpelledOut(words: string[]): string[] {
  const result: string[] = [];
  let run: string[] = [];
  const flush = () => {
    if (run.length >= 3) result.push(run.join(""));
    else result.push(...run);
    run = [];
  };
  for (const word of words) {
    if ([...word].length === 1) run.push(word);
    else {
      flush();
      result.push(word);
    }
  }
  flush();
  return result;
}

/**
 * The words a prompt is matched on: split on anything that isn't a letter or
 * digit, Latin diacritics, Turkish dotless i and ё folded, lookalike letters
 * read in the word's script, leetspeak undone in words that start with a
 * letter ("s3xy", but not "1990s" or "3d"), runs of three or more single
 * letters joined ("b i k i n i", "s.e.x"). Control characters are dropped
 * before the split ("bi\tkini"), or split on with splitControls ("remove\nher");
 * next to Chinese, Japanese or Korean they always split (dropControls).
 */
export function words(text: string, splitControls = false): string[] {
  const cleaned = splitControls ? clean(text) : dropControls(clean(text));
  return joinSpelledOut(tokens(cleaned).map(foldConfusables).map(undoLeet));
}

/**
 * Control characters removed, so they can't split a word ("bi\tkini"). Next
 * to Chinese, Japanese or Korean a run of them becomes a space instead: with
 * no spaces between words, dropping a line break would join two words into a
 * term ("女性\n感谢你" holds "性感"). A term broken by one then passes, as it
 * already does when broken by a space or 。.
 */
function dropControls(text: string): string {
  const chars = [...text];
  let out = "";
  for (let i = 0; i < chars.length; i++) {
    if (!CONTROL.test(chars[i])) {
      out += chars[i];
      continue;
    }
    let end = i;
    while (end + 1 < chars.length && CONTROL.test(chars[end + 1])) end++;
    if ([chars[i - 1], chars[end + 1]].some((c) => c !== undefined && isCJK(c.codePointAt(0)!))) out += " ";
    i = end;
  }
  return out;
}

/**
 * The same text squeezed: punctuation inside a run of non-space characters
 * joins the pieces ("na.ked", "se-xy"), @ $ ! read as a s i, and leetspeak is
 * undone in any word with a letter ("5exy"). Chunks with Chinese, Japanese or
 * Korean characters keep their usual words: joining across 。 could form a
 * term from two words. Control characters are dropped (dropControls), or
 * split on with splitControls.
 */
export function squeezedWords(text: string, splitControls = false): string[] {
  const chunks: string[] = [];
  let chunk = "";
  for (const ch of splitControls ? clean(text) : dropControls(clean(text))) {
    if (BOUNDARY.test(ch)) {
      if (chunk) chunks.push(chunk);
      chunk = "";
    } else chunk += ch;
  }
  if (chunk) chunks.push(chunk);
  const result: string[] = [];
  for (const piece of chunks) {
    if ([...piece].some((c) => isCJK(c.codePointAt(0)!))) {
      result.push(...tokens(piece));
      continue;
    }
    let joined = "";
    for (const ch of piece) {
      const mapped = SYMBOL_LEET[ch] ?? ch;
      if (WORD_CHAR.test(mapped)) joined += mapped;
    }
    if (joined) result.push(joined);
  }
  return joinSpelledOut(result.map(foldConfusables).map(undoLeetFully));
}

function collapse(chars: string[], limit: number): string {
  let out = "";
  let run = 0;
  chars.forEach((c, i) => {
    run = i > 0 && chars[i - 1] === c ? run + 1 : 1;
    if (run <= limit) out += c;
  });
  return out;
}

/**
 * The word plus its stretched-letter variants ("skinnnier" → "skinnier",
 * "skinier"). Doubled letters stay: real words would collide ("tangga",
 * "nuée").
 */
export function forms(word: string): string[] {
  const chars = [...word];
  let longest = 1;
  let run = 1;
  for (let i = 1; i < chars.length; i++) {
    run = chars[i] === chars[i - 1] ? run + 1 : 1;
    longest = Math.max(longest, run);
  }
  if (longest < 3) return [word];
  return [word, collapse(chars, 2), collapse(chars, 1)];
}

function isCJK(cp: number): boolean {
  return (cp >= 0x3040 && cp <= 0x30ff) || (cp >= 0x3400 && cp <= 0x4dbf) || (cp >= 0x4e00 && cp <= 0x9fff) ||
    (cp >= 0xf900 && cp <= 0xfaff) || (cp >= 0x1100 && cp <= 0x11ff) || (cp >= 0x3130 && cp <= 0x318f) ||
    (cp >= 0xac00 && cp <= 0xd7af);
}

// MARK: Terms

function compile(term: string): Term | null {
  if ([...term].some((c) => isCJK(c.codePointAt(0)!))) {
    const substring = words(term).join(" ");
    return substring ? { substring } : null;
  }
  const tokens: Token[] = [];
  for (let raw of term.split(" ").filter(Boolean)) {
    const token: Token = { exact: new Set(), prefixes: [], optional: false };
    if (raw.endsWith("?")) {
      token.optional = true;
      raw = raw.slice(0, -1);
    }
    for (let alternative of raw.split("|").filter(Boolean)) {
      const isPrefix = alternative.endsWith("*");
      if (isPrefix) alternative = alternative.slice(0, -1);
      const normalized = words(alternative);
      if (normalized.length !== 1) return null;
      if (isPrefix) token.prefixes.push(normalized[0]);
      else token.exact.add(normalized[0]);
    }
    tokens.push(token);
  }
  if (!tokens.some((t) => !t.optional)) return null;
  return { tokens };
}

const TERMS: Record<string, string[]> = policy.terms;
const COMPILED: Record<string, Term[]> = Object.fromEntries(
  Object.entries(TERMS).map(([key, list]) => [key, list.map(compile).filter((t): t is Term => t !== null)]),
);

/** Terms that can never match; tests keep this empty. */
export function invalidTerms(): string[] {
  return Object.values(TERMS).flat().filter((t) => compile(t) === null);
}

// MARK: Matching

class View {
  readonly forms: string[][];
  readonly joined: string;

  constructor(list: string[]) {
    this.forms = list.map(forms);
    this.joined = list.join(" ");
  }

  matches(term: Term): boolean {
    if ("substring" in term) return this.joined.includes(term.substring);
    return this.forms.some((_, i) => this.matchesAt(term.tokens, 0, i));
  }

  private matchesAt(tokens: Token[], t: number, index: number): boolean {
    if (t >= tokens.length) return true;
    const token = tokens[t];
    if (
      index < this.forms.length &&
      this.forms[index].some((f) => token.exact.has(f) || token.prefixes.some((p) => f.startsWith(p))) &&
      this.matchesAt(tokens, t + 1, index + 1)
    ) return true;
    return token.optional && this.matchesAt(tokens, t + 1, index);
  }
}

class MatchText {
  readonly views: View[];

  constructor(text: string) {
    // Two readings of control characters (dropped or split on), each plain and squeezed. A term matches any reading.
    const readings = [words(text), words(text, true), squeezedWords(text), squeezedWords(text, true)].map(
      (list) => new View(list),
    );
    this.views = readings.filter((view, i) => readings.findIndex((other) => other.joined === view.joined) === i);
  }

  matchesAny(key: string): boolean {
    return COMPILED[key].some((term) => this.views.some((view) => view.matches(term)));
  }
}

/** The policy's refusal for a category, with its message (also for Claude's prompt check in ai-image). */
export function blocked(category: Category): Verdict {
  return { allowed: false, reason: MESSAGES[category], category };
}

export function evaluatePrompt(prompt: string, operation: string): Verdict {
  const text = new MatchText(prompt);
  const involvesMinor = text.matchesAny("minor");
  if (text.matchesAny("sexual")) return blocked(involvesMinor ? "sexualMinor" : "sexual");
  // Every operation: a text prompt with no person noun still draws one.
  if (text.matchesAny("revealingClothing")) return blocked(involvesMinor ? "sexualMinor" : "revealingClothing");
  // A brand-new image has nobody to reshape or mock.
  if (operation === "text_to_image") return { allowed: true };
  if (text.matchesAny("humiliation")) return blocked("humiliation");
  if (text.matchesAny("appearanceChange")) return blocked("appearanceChange");
  return { allowed: true };
}
