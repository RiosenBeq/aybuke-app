// One-tap template recipes, kept server-side so models and prompts can change
// without an app release. The data is generated from the iOS catalog
// (scripts/export-catalog.sh) and checked by AppCore's CatalogSyncTests.
import catalog from "./catalog.json" with { type: "json" };

export interface TemplateRecipe {
  id: string;
  title: string;
  isPro: boolean;
  prompt: string;
  /** Optional per-template model override (defaults to the edit model). */
  endpoint?: string;
}

const RECIPES = new Map<string, TemplateRecipe>(
  (catalog.templates as TemplateRecipe[]).map((recipe) => [recipe.id, recipe]),
);

/** Identity-critical templates route to the model that ranks best at preserving faces. */
const ENDPOINT_OVERRIDES: Record<string, string> = {};

export function templateRecipe(id: string): TemplateRecipe | undefined {
  const recipe = RECIPES.get(id);
  if (!recipe) return undefined;
  const endpoint = ENDPOINT_OVERRIDES[id];
  return endpoint ? { ...recipe, endpoint } : recipe;
}

export const PRO_STYLES = new Set<string>(catalog.proStyles as string[]);
