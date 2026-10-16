// Enhance's modes: Unblur & sharpen, Restore old photo (optionally with
// colour), Brighten low light and HD 2×. The app only names a mode
// (`enhance_mode`); the instruction comes from catalog.json, exported from
// AppCore's EnhanceMode by scripts/export-catalog.sh, so a client can never
// send its own words with an Enhance. Every instruction keeps the original
// skin and identity guard word for word and never asks for smoothing.
import catalog from "./catalog.json" with { type: "json" };
import { HttpError } from "./http.ts";

export type EnhanceMode = "unblur" | "restore" | "restore_color" | "low_light" | "hd";

/** An app before 1.1 sends no mode: its "AI Enhance" is Unblur & sharpen. */
export const DEFAULT_ENHANCE_MODE: EnhanceMode = "unblur";

/** In every mode's instruction, word for word (EnhanceMode.skinGuard in AppCore). */
export const ENHANCE_SKIN_GUARD =
  "Keep real skin texture, freckles, moles, pores and blemishes; don't retouch or smooth the skin, and don't reshape the face or body.";

const PROMPTS = new Map<string, string>(
  (catalog.enhanceModes as { id: string; prompt: string }[]).map((mode) => [mode.id, mode.prompt]),
);

export const ENHANCE_MODES: readonly string[] = [...PROMPTS.keys()];

/** The mode a request asks for. None is Unblur; one this server doesn't know is refused before anything is charged. */
export function enhanceMode(raw: unknown): EnhanceMode {
  if (raw === undefined || raw === null) return DEFAULT_ENHANCE_MODE;
  if (typeof raw === "string" && PROMPTS.has(raw)) return raw as EnhanceMode;
  throw new HttpError(400, "bad_request", "This fix isn't available. Update the app to see the latest.");
}

/** The instruction for a mode (Unblur when none is given). */
export function enhancePrompt(mode: EnhanceMode = DEFAULT_ENHANCE_MODE): string {
  return PROMPTS.get(mode) ?? PROMPTS.get(DEFAULT_ENHANCE_MODE)!;
}
