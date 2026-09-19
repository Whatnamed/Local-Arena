/**
 * Display order and search text for the cosmetics pickers.
 *
 * Nothing here changes the compatibility catalog: every weapon and every paint
 * stays selectable, and these ranks only decide what the user sees first. Ranks
 * are keyed on stable numeric defindexes and on the English finish name, which is
 * the one label present in every language table, so a language switch cannot
 * silently reshuffle the list.
 */

/** Product preference: the knives most players reach for first. */
export const KNIFE_TYPE_ORDER: number[] = [
  507, // Karambit
  515, // Butterfly Knife
  508, // M9 Bayonet
  500, // Bayonet
  525, // Skeleton Knife
  512, // Falchion Knife
  522, // Stiletto Knife
  523, // Talon Knife
  509, // Huntsman Knife
  505, // Flip Knife
  519, // Ursus Knife
  503, // Classic Knife
  521, // Nomad Knife
  526, // Kukri Knife
  514, // Bowie Knife
];

/** Default rotation for the optional knife shortcut. */
export const DEFAULT_SHORTCUT_KNIVES: number[] = [507, 515, 508, 500, 525, 512];

const KNIFE_RANK = new Map(KNIFE_TYPE_ORDER.map((id, index) => [id, index]));

export function knifeTypeRank(defindex: number): number {
  return KNIFE_RANK.has(defindex) ? KNIFE_RANK.get(defindex)! : KNIFE_TYPE_ORDER.length;
}

export function compareKnifeTypes(a: { id: number }, b: { id: number }): number {
  return knifeTypeRank(a.id) - knifeTypeRank(b.id) || a.id - b.id;
}

/**
 * Dark and neutral finishes first, matching the default look most players pick
 * for a knife. Names are the English tail after "|", lowercase.
 */
export const PREFERRED_KNIFE_FINISHES: string[] = [
  "blue steel",
  "black laminate",
  "night",
  "night stripe",
  "damascus steel",
  "ultraviolet",
  "doppler",
  "gamma doppler",
  "boreal forest",
  "forest ddpat",
  "scorched",
  "urban masked",
  "stained",
  "safari mesh",
  "crimson web",
  "rust coat",
  "case hardened",
];

/**
 * Gloves favour versatile dark and neutral combinations. Every entry is a name
 * that exists in the shipped glove catalog; scripts/test-cosmetic-order.mjs
 * refuses a preference list that names something the catalog does not have.
 */
export const PREFERRED_GLOVE_FINISHES: string[] = [
  "black tie",
  "nocts",
  "occult",
  "racing green",
  "mangrove",
  "arboreal",
  "leather",
  "bronzed",
  "charred",
  "buckshot",
  "field agent",
  "cobalt skulls",
  "convoy",
  "foundation",
  "emerald",
  "pandora's box",
  "scarlet shamagh",
  "snakebite",
  "king snake",
  "garden",
];

const GLOVE_RANK = new Map(PREFERRED_GLOVE_FINISHES.map((name, index) => [name, index]));
const KNIFE_FINISH_RANK = new Map(PREFERRED_KNIFE_FINISHES.map((name, index) => [name, index]));

export const PREFERRED_TAIL = Number.MAX_SAFE_INTEGER;

function rankIn(lowercaseFinishName: string, table: Map<string, number>): number {
  const exact = table.get(lowercaseFinishName);
  if (exact !== undefined) return exact;
  for (const [name, index] of table) if (lowercaseFinishName.startsWith(`${name} `)) return index;
  return PREFERRED_TAIL;
}

/** Position of a finish inside a preference list; unlisted finishes sort last. */
export function finishIndexOf(lowercaseFinishName: string, preferred: string[]): number {
  return rankIn(lowercaseFinishName, new Map(preferred.map((name, index) => [name, index])));
}

/**
 * Stable sort that lifts preferred finishes to the front and otherwise leaves the
 * catalog's own order untouched, so a re-rank can never drop an entry.
 */
export function orderByPreferredFinish<T>(
  rows: T[],
  finishOf: (row: T) => string,
  preferred: string[]
): T[] {
  const table = new Map(preferred.map((name, index) => [name, index]));
  return rows
    .map((row, index) => ({ row, index, rank: rankIn(finishOf(row).toLocaleLowerCase(), table) }))
    .sort((a, b) => a.rank - b.rank || a.index - b.index)
    .map(entry => entry.row);
}

export function knifeFinishRank(lowercaseFinishName: string): number {
  return rankIn(lowercaseFinishName, KNIFE_FINISH_RANK);
}

export function gloveFinishRank(lowercaseFinishName: string): number {
  return rankIn(lowercaseFinishName, GLOVE_RANK);
}
