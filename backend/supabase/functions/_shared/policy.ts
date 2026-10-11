// Server-side prompt policy. Mirrors ios/Packages/AppCore ContentPolicy.swift and
// runs before any provider call; the provider's own safety checker and the
// optional output NSFW check run after it. Sexualised edits of real people are
// blocked outright (App Review 1.1.4, EU AI Act Art. 5(1)(ba) from 2 Dec 2026).

const SEXUAL_TERMS = new Set([
  "nude",
  "nudes",
  "naked",
  "nsfw",
  "porn",
  "porno",
  "pornographic",
  "sex",
  "sexual",
  "sexy",
  "topless",
  "lingerie",
  "undress",
  "undressed",
  "undressing",
  "nudify",
  "nipple",
  "nipples",
  "genital",
  "genitals",
  "erotic",
  "hentai",
  "xxx",
  "onlyfans",
]);

const MINOR_TERMS = new Set([
  "child",
  "children",
  "kid",
  "kids",
  "minor",
  "minors",
  "teen",
  "teens",
  "teenager",
  "underage",
  "boy",
  "girl",
  "baby",
  "toddler",
  "schoolgirl",
  "schoolboy",
  "loli",
  "preteen",
]);

const UNDRESSING_PHRASES = [
  "remove clothes",
  "remove her clothes",
  "remove his clothes",
  "remove their clothes",
  "take off clothes",
  "take off her clothes",
  "take off his clothes",
  "without clothes",
  "no clothes",
  "see through clothes",
  "x-ray clothes",
];

export type Verdict = { allowed: true } | { allowed: false; reason: string };

export function evaluatePrompt(prompt: string): Verdict {
  const lower = prompt.toLowerCase();
  const words = new Set(lower.split(/[^\p{L}\p{N}]+/u).filter(Boolean));
  const isSexual = [...words].some((w) => SEXUAL_TERMS.has(w)) ||
    UNDRESSING_PHRASES.some((phrase) => lower.includes(phrase));
  if (!isSexual) return { allowed: true };
  if ([...words].some((w) => MINOR_TERMS.has(w))) {
    return { allowed: false, reason: "This request violates our content policy and can't be created." };
  }
  return { allowed: false, reason: "Nudity and sexual content aren't allowed. Try a different idea." };
}
