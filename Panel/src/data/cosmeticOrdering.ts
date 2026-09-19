export const PREFERRED_KNIFE_IDS = [
  507, 515, 508, 500, 525, 512, 522, 523, 509, 505,
  519, 503, 521, 526, 514,
] as const;

const PREFERRED_FINISHES = [
  "vanilla",
  "blue steel",
  "black laminate",
  "doppler",
  "night stripe",
  "night",
  "damascus steel",
  "ultraviolet",
];

const PREFERRED_GLOVE_FINISHES = ["nocts", "black tie", "smoke out"];

export function finishPreferenceRank(name: string): number {
  const normalized = name.toLocaleLowerCase();
  const index = PREFERRED_FINISHES.findIndex((finish) => normalized.includes(finish));
  return index < 0 ? PREFERRED_FINISHES.length : index;
}

export function glovePreferenceRank(name: string): number {
  const normalized = name.toLocaleLowerCase();
  const index = PREFERRED_GLOVE_FINISHES.findIndex((finish) => normalized.includes(finish));
  return index < 0 ? PREFERRED_GLOVE_FINISHES.length : index;
}

export function sortByPreference<T>(
  rows: readonly T[],
  getName: (row: T) => string,
  getStableKey: (row: T) => number | string,
  rank: (name: string) => number,
): T[] {
  return rows
    .map((row, index) => ({ row, index }))
    .sort((left, right) => {
      const preferred = rank(getName(left.row)) - rank(getName(right.row));
      if (preferred !== 0) return preferred;
      const leftKey = getStableKey(left.row);
      const rightKey = getStableKey(right.row);
      if (typeof leftKey === "number" && typeof rightKey === "number") return leftKey - rightKey || left.index - right.index;
      return String(leftKey).localeCompare(String(rightKey)) || left.index - right.index;
    })
    .map(({ row }) => row);
}
