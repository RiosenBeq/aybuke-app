// Pro tries: one Pro look (a restyle template) or Pro Create style that a free
// member unlocks for one job by watching a rewarded ad (migration
// 20261101000000). ad-reward hands out the token for one (unlockRequest);
// ai-image lets a job use it (proItemsFor → requireUnlock → admissionCall).
// The database decides whether she holds a try and spends it with the job
// (ad_unlock_available(), admit_unlocked_job()); a refunded job gives it back.
import { HttpError } from "./http.ts";
import { PRO_STYLES, templateRecipe } from "./templates.ts";

/** "template": a Pro one-tap look (restyle). "style": a Pro Create style. */
export type UnlockType = "template" | "style";

export interface ProItem {
  type: UnlockType;
  id: string;
}

/** The field that names a try of each kind, in requests and answers. */
export function itemField(type: UnlockType): "template_id" | "style_id" {
  return type === "template" ? "template_id" : "style_id";
}

/** Only the catalog's Pro looks and Pro styles can be tried with an ad. */
export function isUnlockable(item: ProItem): boolean {
  return item.type === "template" ? templateRecipe(item.id)?.isPro === true : PRO_STYLES.has(item.id);
}

// MARK: - ad-reward

const NAME_ONE = "Name one look or style to try.";

/**
 * What POST /ad-reward { "kind": "unlock" } names: exactly one of
 * `template_id` and `style_id`, a Pro one in the catalog. Anything else is
 * refused before an ad is shown, so an ad can't pay for a try nobody can use.
 */
export function unlockRequest(templateId: unknown, styleId: unknown): ProItem {
  const named = ([["template", templateId], ["style", styleId]] as [UnlockType, unknown][])
    .filter(([, id]) => id !== undefined && id !== null);
  if (named.length !== 1) throw new HttpError(400, "bad_request", NAME_ONE);
  const [type, id] = named[0];
  if (typeof id !== "string" || id.length === 0 || id.length > 100) {
    throw new HttpError(400, "bad_request", NAME_ONE);
  }
  const item = { type, id };
  if (!isUnlockable(item)) {
    throw new HttpError(400, "not_unlockable", "Only Pro looks and styles can be tried with an ad.");
  }
  return item;
}

// MARK: - ai-image

/** ai-image's answer to a Pro look or style without Pro or a try, as before tries existed. */
export const PRO_REQUIRED: Record<UnlockType, string> = {
  template: "This template is part of Pro.",
  style: "This style is part of Pro.",
};

/** admit_unlocked_job()'s arguments on top of admit_job()'s. */
export interface UnlockArgs {
  p_unlock_type: UnlockType;
  p_unlock_id: string;
}

/**
 * The Pro looks and styles a job asks for, unless she's Pro: a Pro Create
 * style (`style_id`) and a Pro restyle template (the job's recipe). In that
 * order, as ai-image always checked them.
 */
export function proItemsFor(
  isPro: boolean,
  styleId: string | undefined,
  recipe: { id: string; isPro: boolean } | undefined,
): ProItem[] {
  if (isPro) return [];
  const items: ProItem[] = [];
  if (styleId && PRO_STYLES.has(styleId)) items.push({ type: "style", id: styleId });
  if (recipe?.isPro) items.push({ type: "template", id: recipe.id });
  return items;
}

type Rpc = (
  fn: string,
  args: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: { message: string } | null }>;

/**
 * ad_unlock_available() for one user: does she hold an unused, live try of
 * this look or style, or (for a free retry) did the original job spend one on
 * it? A failed read is an error, never "no try": she may have just watched the
 * ad for it.
 */
export function unlockChecker(rpc: Rpc, userId: string): (item: ProItem, retryOf: string | null) => Promise<boolean> {
  return async (item, retryOf) => {
    const { data, error } = await rpc("ad_unlock_available", {
      p_user: userId,
      p_unlock_type: item.type,
      p_unlock_id: item.id,
      p_retry_of: retryOf,
    });
    if (error) {
      console.error("ad_unlock_available failed", error.message);
      throw new HttpError(500, "internal", "Couldn't start the job.");
    }
    return data === true;
  };
}

/**
 * The Pro looks and styles a job asks for (`items`: none for Pro members or
 * free looks) need a try of exactly that one, or, for a free retry
 * (`retryOf`), the try the original job spent. `available` asks the database
 * (unlockChecker). Without one: 402 pro_required, before anything is checked
 * or booked. One try covers one look or style, never two at once. Returns the
 * arguments that make admission spend the try (undefined: plain admit_job()).
 */
export async function requireUnlock(
  items: readonly ProItem[],
  retryOf: string | null,
  available: (item: ProItem, retryOf: string | null) => Promise<boolean>,
): Promise<UnlockArgs | undefined> {
  if (items.length === 0) return undefined;
  const [item] = items;
  if (items.length > 1 || !await available(item, retryOf)) {
    throw new HttpError(402, "pro_required", PRO_REQUIRED[item.type]);
  }
  return { p_unlock_type: item.type, p_unlock_id: item.id };
}

/**
 * The admission call for a job: admit_job() as always, or, when the job uses
 * a try, admit_unlocked_job() with the same arguments and the try's.
 */
export function admissionCall(
  unlock: UnlockArgs | undefined,
  args: Record<string, unknown>,
): { fn: "admit_job" | "admit_unlocked_job"; args: Record<string, unknown> } {
  return unlock ? { fn: "admit_unlocked_job", args: { ...args, ...unlock } } : { fn: "admit_job", args };
}
