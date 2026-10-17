// Renders every owner mail with sample numbers to build/mail-previews/<name>.html
// and .txt, to look at in a browser (or headless Chrome) in light and dark mode:
//
//   deno run --allow-write=build backend/scripts/owner-mail-previews.ts   (from the repository root)
//
// build/ is git-ignored. The samples live in _shared/owner-mail-samples.ts.
import { renderOwnerMail } from "../supabase/functions/_shared/owner-mail.ts";
import { sampleMails } from "../supabase/functions/_shared/owner-mail-samples.ts";

const out = Deno.args[0] ?? "build/mail-previews";
await Deno.mkdir(out, { recursive: true });
for (const [name, mail] of Object.entries(sampleMails())) {
  const rendered = renderOwnerMail(mail);
  await Deno.writeTextFile(`${out}/${name}.html`, rendered.html);
  await Deno.writeTextFile(`${out}/${name}.txt`, `Subject: ${rendered.subject}\n\n${rendered.text}\n`);
  console.log(`${out}/${name}.html  ${rendered.subject}`);
}
