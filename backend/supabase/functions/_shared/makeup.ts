// Makeup Studio's catalog on the server (catalog.json's "makeup", generated
// from ios/Packages/AppCore/Sources/AppCore/MakeupStudio.swift by
// scripts/export-catalog.sh): the ids the assist function may answer, the
// JSON schema that holds Claude to them, and the check that drops any id the
// catalog doesn't have. "none" ("As is") is never an answer: null means as is.
import catalog from "./catalog.json" with { type: "json" };

export interface MakeupOption {
  id: string;
  name: string;
}

export interface MakeupLook {
  id: string;
  name: string;
  lips: string;
  eyes: string;
  cheeks: string;
  extras: string[];
  hair: string;
  intensity: string;
}

export interface MakeupCatalog {
  looks: MakeupLook[];
  lips: MakeupOption[];
  eyes: MakeupOption[];
  cheeks: MakeupOption[];
  extras: MakeupOption[];
  hair: MakeupOption[];
  intensity: MakeupOption[];
  skinGuard: string;
}

export const MAKEUP: MakeupCatalog = catalog.makeup;

/** "As is": a choice the catalog has, never one the server answers. */
export const AS_IS = "none";

/**
 * The last sentence of every makeup request (MakeupStudio.skinGuard). A Magic
 * Edit that carries it was written by the catalog, so ai-image leaves it as is.
 */
export const MAKEUP_SKIN_GUARD: string = MAKEUP.skinGuard;

/** One pick: every field is a catalog id or null (as is). */
export interface MakeupPick {
  look: string | null;
  lips: string | null;
  eyes: string | null;
  cheeks: string | null;
  extras: string[];
  hair: string | null;
  intensity: string | null;
}

const ids = (options: { id: string }[]) => options.map((option) => option.id).filter((id) => id !== AS_IS);

export const MAKEUP_IDS = {
  look: ids(MAKEUP.looks),
  lips: ids(MAKEUP.lips),
  eyes: ids(MAKEUP.eyes),
  cheeks: ids(MAKEUP.cheeks),
  extras: ids(MAKEUP.extras),
  hair: ids(MAKEUP.hair),
  intensity: ids(MAKEUP.intensity),
};

const nullable = (values: string[]) => ({ anyOf: [{ type: "string", enum: values }, { type: "null" }] });

/** The answer's schema: catalog ids only, plus her note. The same for every request, so the API caches it. */
export function makeupSchema(): Record<string, unknown> {
  return {
    type: "object",
    properties: {
      look: nullable(MAKEUP_IDS.look),
      lips: nullable(MAKEUP_IDS.lips),
      eyes: nullable(MAKEUP_IDS.eyes),
      cheeks: nullable(MAKEUP_IDS.cheeks),
      extras: { type: "array", items: { type: "string", enum: MAKEUP_IDS.extras } },
      hair: nullable(MAKEUP_IDS.hair),
      intensity: nullable(MAKEUP_IDS.intensity),
      note: { type: "string" },
    },
    required: ["look", "lips", "eyes", "cheeks", "extras", "hair", "intensity", "note"],
    additionalProperties: false,
  };
}

/** The catalog for Claude, one line per look and per kind of choice, ids first. */
export function catalogText(): string {
  const list = (options: MakeupOption[]) =>
    options.filter((option) => option.id !== AS_IS).map((option) => `${option.id} (${option.name})`).join(", ");
  const looks = MAKEUP.looks.map((look) => {
    const parts = [
      look.lips !== AS_IS ? `lips ${look.lips}` : "",
      look.eyes !== AS_IS ? `eyes ${look.eyes}` : "",
      look.cheeks !== AS_IS ? `cheeks ${look.cheeks}` : "",
      look.extras.length > 0 ? `extras ${look.extras.join(" + ")}` : "",
      `intensity ${look.intensity}`,
    ].filter(Boolean);
    return `- ${look.id} (${look.name}): ${parts.join(", ")}`;
  });
  return [
    "Looks:",
    ...looks,
    `Lips: ${list(MAKEUP.lips)}`,
    `Eyes: ${list(MAKEUP.eyes)}`,
    `Cheeks: ${list(MAKEUP.cheeks)}`,
    `Extras: ${list(MAKEUP.extras)}`,
    `Hair colors: ${list(MAKEUP.hair)}`,
    `Intensity: ${list(MAKEUP.intensity)}`,
  ].join("\n");
}

function known(value: unknown, allowed: string[]): string | null {
  return typeof value === "string" && allowed.includes(value) ? value : null;
}

/**
 * Claude's picks with every unknown id dropped. A look becomes its whole
 * recipe, with the parts Claude named on top and its extras added to the
 * look's, so every field is the final choice. Undefined when nothing known is
 * left (no look, no choice, no extra).
 */
export function readMakeupPick(value: unknown): MakeupPick | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
  const answer = value as Record<string, unknown>;
  const extras = Array.isArray(answer.extras)
    ? MAKEUP_IDS.extras.filter((id) => (answer.extras as unknown[]).includes(id))
    : [];
  const pick: MakeupPick = {
    look: known(answer.look, MAKEUP_IDS.look),
    lips: known(answer.lips, MAKEUP_IDS.lips),
    eyes: known(answer.eyes, MAKEUP_IDS.eyes),
    cheeks: known(answer.cheeks, MAKEUP_IDS.cheeks),
    extras,
    hair: known(answer.hair, MAKEUP_IDS.hair),
    intensity: known(answer.intensity, MAKEUP_IDS.intensity),
  };
  const look = MAKEUP.looks.find((candidate) => candidate.id === pick.look);
  if (look) {
    const own = (id: string) => (id === AS_IS ? null : id);
    pick.lips ??= own(look.lips);
    pick.eyes ??= own(look.eyes);
    pick.cheeks ??= own(look.cheeks);
    pick.hair ??= own(look.hair);
    pick.intensity ??= own(look.intensity);
    pick.extras = MAKEUP_IDS.extras.filter((id) => look.extras.includes(id) || pick.extras.includes(id));
  }
  const anything = pick.look !== null || pick.lips !== null || pick.eyes !== null || pick.cheeks !== null ||
    pick.extras.length > 0 || pick.hair !== null;
  return anything ? pick : undefined;
}
