// deno test _shared/
// Every owner mail, rendered from the samples (owner-mail-samples.ts): subjects,
// the email-client scaffolding (light and dark, phone and desktop, no remote
// content), a plain-text part with the same facts, contrast, and nothing private.
import assert from "node:assert/strict";
import { escapeHtml, formatValue, type OwnerMail, renderOwnerMail } from "./owner-mail.ts";
import { PRIVATE_VALUES, SAMPLE_APP_USER_IDS, sampleMails } from "./owner-mail-samples.ts";

const mails = sampleMails();
const rendered = Object.fromEntries(Object.entries(mails).map(([name, mail]) => [name, renderOwnerMail(mail)]));

Deno.test("subjects are short and say what happened", () => {
  assert.deepEqual(Object.fromEntries(Object.entries(rendered).map(([name, mail]) => [name, mail.subject])), {
    "pro-member": "New Pro member · Yearly",
    "pro-member-sandbox": "[TEST] New Pro member · Monthly",
    "credit-pack": "Credit pack sold · 100 credits",
    "ai-paused": "AI paused · xAI out of credit",
    "balance-low": "xAI balance low · about $1.96 left",
    "digest": "Daily digest · 16 Oct · 312 AI jobs · 12 Pro",
    "digest-quiet": "Daily digest · 16 Oct · 312 AI jobs · 12 Pro",
    "digest-unreadable": "Daily digest · 16 Oct · – AI jobs · – Pro",
  });
  for (const { subject } of Object.values(rendered)) assert.ok(subject.length <= 60, subject);
});

Deno.test("every mail is a 600 px table layout for light and dark, phones and desktops, with nothing remote", () => {
  for (const [name, { html }] of Object.entries(rendered)) {
    for (
      const part of [
        "<!doctype html>",
        '<meta name="color-scheme" content="light dark">',
        '<meta name="supported-color-schemes" content="light dark">',
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        '<meta name="format-detection" content="telephone=no,date=no,address=no,email=no,url=no">',
        ":root{color-scheme:light dark;supported-color-schemes:light dark;}",
        "@media (prefers-color-scheme:dark){",
        "@media only screen and (max-width:480px){",
        "[data-ogsc] .gl-ink",
        "max-width:600px",
        '<table role="presentation" align="center" width="600"', // Outlook's ghost table
        'bgcolor="#F8E0EA"', // petal page, as an attribute for clients that drop styles
        'role="article"',
        "mso-hide:all", // the hidden preview line
      ]
    ) assert.ok(html.includes(part), `${name}: ${part}`);
    assert.equal(html.match(/<h1\b/g)?.length, 1, `${name}: one headline`);
    assert.match(html, />aybuke<\/span><span[^>]*aria-hidden="true"[^>]*>&#10022;<\/span>/, `${name}: live wordmark`);
    for (const remote of ["<img", "<link", "@import", "src=", "url(", "<script"]) {
      assert.ok(!html.includes(remote), `${name}: ${remote}`);
    }
    for (const [, href] of html.matchAll(/href="([^"]*)"/g)) assert.match(href, /^https:\/\//, `${name}: ${href}`);
    // Every text colour class has its dark-mode override.
    const dark = html.slice(html.indexOf("@media (prefers-color-scheme:dark){"));
    for (const cls of new Set(html.match(/\bgl-(?:ink|muted|warn|good|h-ink|h-soft|h-brand)\b/g))) {
      assert.ok(dark.includes(`.${cls}{`) || dark.includes(`.${cls},`), `${name}: dark .${cls}`);
    }
  }
});

/** WCAG contrast of two #RRGGBB colours. */
function contrast(a: string, b: string): number {
  const luminance = (hex: string) => {
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
      .map((c) => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const [x, y] = [luminance(a), luminance(b)].sort((m, n) => n - m);
  return (x + 0.05) / (y + 0.05);
}

Deno.test("text keeps at least 4.5:1 contrast in light and in dark mode", () => {
  const { html } = rendered["digest"];
  const darkRule = (cls: string, property: string) => {
    const css = html.slice(html.indexOf("@media (prefers-color-scheme:dark){"));
    const match = new RegExp(`\\.${cls}[^{]*\\{[^}]*${property}:(#[0-9A-F]{6})`).exec(css);
    assert.ok(match, `${cls} ${property}`);
    return match[1];
  };
  const light = { card: "#FFFFFF", tile: "#FDF2F6", blush: "#F7C1D9", ink: "#121212" };
  for (
    const [text, background] of [
      [light.ink, light.card],
      ["#6B5560", light.card],
      ["#6B5560", light.tile],
      [
        "#B0144F",
        light.card,
      ],
      ["#1C6E46", light.card],
      ["#3B2A32", light.blush],
      ["#FBEFF4", light.ink],
      [light.ink, light.blush],
    ]
  ) {
    assert.ok(contrast(text, background) >= 4.5, `light ${text} on ${background}`);
  }
  const card = darkRule("gl-card", "background-color");
  const tile = darkRule("gl-tile", "background-color");
  const head = darkRule("gl-head", "background-color");
  for (
    const [text, background] of [
      [darkRule("gl-ink", "color"), card],
      [darkRule("gl-muted", "color"), card],
      [darkRule("gl-muted", "color"), tile],
      [darkRule("gl-warn", "color"), card],
      [darkRule("gl-good", "color"), card],
      [darkRule("gl-h-ink", "color"), head],
      [darkRule("gl-h-soft", "color"), head],
      [darkRule("gl-btn-text", "color"), darkRule("gl-btn-bg", "background-color")],
    ]
  ) assert.ok(contrast(text, background) >= 4.5, `dark ${text} on ${background}`);
});

/** Every fact the HTML shows, as the plain-text part should show it. */
function facts(mail: OwnerMail): string[] {
  return [
    mail.headline,
    mail.summary,
    mail.reason,
    ...(mail.stamp ? [mail.stamp] : []),
    ...(mail.badge ? [mail.badge] : []),
    ...(mail.attention ?? []),
    ...mail.stats.map((stat) => `${stat.label}: ${formatValue(stat.value)}${stat.note ? ` (${stat.note})` : ""}`),
    ...mail.sections.flatMap((section) => [
      section.title.toUpperCase(),
      ...section.rows.map((row) => `${row.label}: ${formatValue(row.value)}`),
    ]),
    ...(mail.actions ?? []).map((action) => `${action.label}: ${action.url}`),
  ];
}

Deno.test("the plain-text part carries the same facts as the HTML, without markup", () => {
  for (const [name, mail] of Object.entries(mails)) {
    const { html, text } = rendered[name];
    for (const fact of facts(mail)) assert.ok(text.includes(fact), `${name} text: ${fact}`);
    for (const stat of mail.stats) {
      assert.ok(html.includes(escapeHtml(formatValue(stat.value))), `${name} html: ${stat.label}`);
    }
    for (const row of mail.sections.flatMap((section) => section.rows)) {
      const shown = escapeHtml(formatValue(row.value));
      const code = shown.replace(/([(,.])/g, "$1<wbr>");
      assert.ok(html.includes(shown) || html.includes(code), `${name} html: ${row.label}`);
    }
    assert.ok(!/<[a-z!/]/i.test(text.replace(/<new cents>/g, "")), `${name}: markup in the text part`);
    assert.equal(html.match(/class="gl-kpi /g)?.length ?? 0, mail.stats.length, `${name}: one tile per number`);
  }
});

Deno.test("no mail shows an email, user id, transaction id, token, prompt or install key", () => {
  for (const [name, { subject, html, text }] of Object.entries(rendered)) {
    for (const secret of PRIVATE_VALUES) {
      assert.ok(![subject, html, text].some((part) => part.includes(secret)), `${name}: ${secret}`);
    }
    assert.ok(!/[\w.+-]+@[\w-]+\.[\w.]+/.test(text), `${name}: an email address`);
    // Only the digest lists RevenueCat App User IDs, of accounts already deleted.
    const ids = SAMPLE_APP_USER_IDS.filter((id) => text.includes(id) || html.includes(id));
    assert.deepEqual(ids, name === "digest" ? SAMPLE_APP_USER_IDS : [], name);
  }
});

Deno.test("the digest leads with what needs the owner, and says so when nothing does", () => {
  const busy = mails["digest"];
  assert.deepEqual(busy.attention, [
    "xAI balance about $1.96 left (estimate)",
    "Free jobs: 52 of the daily cap of 60",
    "1 open report to review",
    "2 open poll reports to review",
    "3 RevenueCat customers of deleted accounts to delete",
  ]);
  assert.match(busy.summary, /5 things need you\.$/);
  assert.ok(rendered["digest"].html.includes(">Needs you</p>"));
  assert.deepEqual(busy.actions?.map((action) => action.label), [
    "Open Supabase",
    "Open RevenueCat",
    "Open the xAI Console",
  ]);
  assert.equal(busy.headline, "Friday 16 October");

  const quiet = mails["digest-quiet"];
  assert.deepEqual(quiet.attention, []);
  assert.match(quiet.summary, /Nothing needs you\.$/);
  assert.ok(!rendered["digest-quiet"].html.includes(">Needs you</p>"));
  assert.deepEqual(quiet.actions, []);
  assert.ok(rendered["digest-quiet"].text.includes("Deleted automatically now · failed: 2 · 0"));

  assert.match(mails["digest-unreadable"].summary, /dashes/);
});

Deno.test("alerts that need the owner use the ink header, steps and a console button", () => {
  const paused = rendered["ai-paused"];
  assert.ok(paused.html.includes('bgcolor="#121212"'));
  assert.ok(paused.text.includes("  2. Then resume AI: select public.ops_resume_ai();"));
  assert.ok(paused.html.includes('href="https://console.x.ai"'));
  assert.ok(paused.html.includes('class="gl-code"'));
  assert.equal(mails["pro-member"].tone, "celebrate");
  assert.equal(mails["pro-member-sandbox"].tone, "info", "a sandbox purchase isn't news to celebrate");
});

Deno.test("buttons only link to https; anything else is dropped", () => {
  const { html, text } = renderOwnerMail({
    ...mails["balance-low"],
    actions: [
      { label: "Fine", url: "https://example.test/path" },
      { label: "Script", url: "javascript:alert(1)" },
      { label: "Quote", url: 'https://x.test/"onmouseover="y' },
    ],
  });
  assert.ok(html.includes('href="https://example.test/path"') && text.includes("Fine: https://example.test/path"));
  for (const bad of ["javascript:", "onmouseover", "Script", "Quote"]) {
    assert.ok(!html.includes(bad) && !text.includes(bad), bad);
  }
});
