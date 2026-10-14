// Server-side prompt policy. Runs the same terms as ios/Packages/AppCore
// ContentPolicy.swift (exported to policy-terms.json by scripts/export-catalog.sh)
// with the same normalisation, before any provider call; the provider's own
// safety checker and the optional output NSFW check run after it. Sexualised
// edits of real people are blocked outright (App Review 1.1.4, EU AI Act
// Art. 5(1)(ba) from 2 Dec 2026), and so are body, face and skin reshaping,
// revealing clothing and humiliating edits (teen safety). Shared test vectors:
// policy-vectors.json.

import policy from "./policy-terms.json" with { type: "json" };

export type Category = "sexual" | "sexualMinor" | "revealingClothing" | "humiliation" | "appearanceChange";
export type Verdict = { allowed: true } | { allowed: false; reason: string; category: Category };

/** Appended to every Magic Edit (PromptBuilder.editGuard in the app). */
export const EDIT_GUARD: string = policy.editGuard;

const MESSAGES: Record<string, string> = policy.messages;

type Token = { exact: Set<string>; prefixes: string[]; optional: boolean };
type Term = { tokens: Token[] } | { substring: string };

// MARK: Normalisation (mirrors ContentPolicy.words(in:) exactly)

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t" };
const WORD_CHAR = /^[\p{L}\p{N}]$/u;
const NUMBER_CHAR = /^\p{N}$/u;

function fold(text: string): string {
  let out = "";
  for (const ch of text) {
    const cp = ch.codePointAt(0)!;
    if (cp === 0x0131) out += "i"; // ı
    else if (cp === 0x0307) continue; // the dot "İ" leaves behind when lowercased
    else if (cp === 0x0451) out += "е"; // ё → е
    else if ((cp >= 0x00c0 && cp <= 0x024f) || (cp >= 0x1e00 && cp <= 0x1eff)) {
      out += ch.normalize("NFD").replace(/[̀-ͯ]/g, "");
    } else out += ch;
  }
  return out;
}

function undoLeet(word: string): string {
  const chars = [...word];
  if (NUMBER_CHAR.test(chars[0]) || !chars.some((c) => c in LEET)) return word;
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

export function words(text: string): string[] {
  const result: string[] = [];
  let current = "";
  for (const ch of fold(text.normalize("NFKC").toLowerCase())) {
    if (WORD_CHAR.test(ch)) current += ch;
    else if (current) {
      result.push(current);
      current = "";
    }
  }
  if (current) result.push(current);
  return joinSpelledOut(result.map(undoLeet));
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

/** The word plus its stretched-letter variants ("skinnnier" → "skinnier", "skinier"). */
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

class MatchText {
  readonly forms: string[][];
  readonly joined: string;

  constructor(text: string) {
    const list = words(text);
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

  matchesAny(key: string): boolean {
    return COMPILED[key].some((term) => this.matches(term));
  }
}

function blocked(category: Category): Verdict {
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
