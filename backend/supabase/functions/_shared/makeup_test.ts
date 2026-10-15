// deno test _shared/
// Makeup Studio's ids on the server: the catalog the exporter wrote, the
// schema that holds Claude to it, and the check that drops whatever isn't in it.
import assert from "node:assert/strict";
import { AS_IS, catalogText, MAKEUP, MAKEUP_IDS, MAKEUP_SKIN_GUARD, makeupSchema, readMakeupPick } from "./makeup.ts";
import { evaluatePrompt } from "./policy.ts";

Deno.test("the catalog from MakeupStudio.swift: 14 looks, every part of a look is a known id", () => {
  assert.equal(MAKEUP.looks.length, 14);
  assert.ok(MAKEUP.looks.some((look) => look.id === "softGlam" && look.name === "Soft Glam"));
  for (const look of MAKEUP.looks) {
    for (const [part, id] of [["lips", look.lips], ["eyes", look.eyes], ["cheeks", look.cheeks], ["hair", look.hair]]) {
      assert.ok(
        id === AS_IS || MAKEUP_IDS[part as "lips" | "eyes" | "cheeks" | "hair"].includes(id),
        `${look.id} ${part}`,
      );
    }
    assert.ok(look.extras.every((id) => MAKEUP_IDS.extras.includes(id)), look.id);
    assert.ok(MAKEUP_IDS.intensity.includes(look.intensity), look.id);
    // Looks never set a hair color: that stays her own choice.
    assert.equal(look.hair, AS_IS, look.id);
  }
  assert.deepEqual(MAKEUP_IDS.intensity, ["soft", "medium", "bold"]);
  // The protective sentence passes the policy itself, so a makeup request never trips it.
  assert.ok(MAKEUP_SKIN_GUARD.startsWith("Keep the same expression"));
  assert.ok(evaluatePrompt(MAKEUP_SKIN_GUARD, "magic_edit").allowed);
});

Deno.test("the schema offers catalog ids only, never 'none', null for as is", () => {
  const schema = makeupSchema() as {
    properties: Record<string, { anyOf?: { enum?: string[] }[]; items?: { enum: string[] } }>;
    required: string[];
    additionalProperties: boolean;
  };
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required, ["look", "lips", "eyes", "cheeks", "extras", "hair", "intensity", "note"]);
  for (const key of ["look", "lips", "eyes", "cheeks", "hair", "intensity"] as const) {
    const values = schema.properties[key].anyOf?.[0].enum ?? [];
    assert.deepEqual(values, MAKEUP_IDS[key], key);
    assert.ok(!values.includes(AS_IS), key);
    assert.deepEqual(schema.properties[key].anyOf?.[1], { type: "null" }, key);
  }
  assert.deepEqual(schema.properties.extras.items?.enum, ["faceGems", "fauxFreckles", "starStickers", "glitter"]);
  // Stable between requests, so the API compiles it once.
  assert.deepEqual(makeupSchema(), makeupSchema());
  const text = catalogText();
  assert.ok(text.includes("- softGlam (Soft Glam): lips softPink, eyes smokyBrown, cheeks softBlush, intensity soft"));
  assert.ok(text.includes("Hair colors: pastelPink (Pastel pink)"));
  assert.ok(!text.includes("none ("), "as is isn't offered");
});

Deno.test("a look comes with its whole recipe; Claude's parts go on top and its extras are added", () => {
  assert.deepEqual(
    readMakeupPick({
      look: "strawberryGirl",
      lips: null,
      eyes: null,
      cheeks: null,
      extras: [],
      hair: null,
      intensity: null,
    }),
    {
      look: "strawberryGirl",
      lips: "cherryRed",
      eyes: "softShimmer",
      cheeks: "rosyFlush",
      extras: ["fauxFreckles"],
      hair: null,
      intensity: "medium",
    },
  );
  assert.deepEqual(
    readMakeupPick({
      look: "softGlam",
      lips: "berry",
      eyes: null,
      cheeks: null,
      extras: ["glitter"],
      hair: "lilac",
      intensity: "bold",
    }),
    {
      look: "softGlam",
      lips: "berry",
      eyes: "smokyBrown",
      cheeks: "softBlush",
      extras: ["glitter"],
      hair: "lilac",
      intensity: "bold",
    },
  );
});

Deno.test("unknown ids are dropped; nothing known left is no pick", () => {
  assert.deepEqual(
    readMakeupPick({
      look: "celebrityGlam",
      lips: "nudeLip",
      eyes: "glitterLid",
      cheeks: "contour",
      extras: ["glitter", "lipFiller", "glitter", 7],
      hair: "none",
      intensity: "extreme",
    }),
    { look: null, lips: null, eyes: "glitterLid", cheeks: null, extras: ["glitter"], hair: null, intensity: null },
  );
  // A hair color alone is a pick (Makeup Studio changes only the hair then).
  assert.deepEqual(readMakeupPick({ hair: "blue" }), {
    look: null,
    lips: null,
    eyes: null,
    cheeks: null,
    extras: [],
    hair: "blue",
    intensity: null,
  });
  for (const value of [null, [], "softGlam", { look: "bogus" }, { intensity: "soft" }, { lips: "none" }, {}]) {
    assert.equal(readMakeupPick(value), undefined, JSON.stringify(value));
  }
});
