import namesByLanguage from "./skinNames.json";

type SkinNameTable = Record<string, Record<string, string>>;

const names = namesByLanguage as SkinNameTable;

export function localizedSkinName(
  language: string | null | undefined,
  weaponDefIndex: number,
  paint: number,
  fallback?: string
): string {
  const key = `${weaponDefIndex}:${paint}`;
  return names[language ?? "english"]?.[key]
    ?? names.english?.[key]
    ?? fallback
    ?? `Paint Kit ${paint}`;
}

export function finishName(fullName: string): string {
  const separator = fullName.indexOf("|");
  return separator >= 0 ? fullName.slice(separator + 1).trim() : fullName.trim();
}

export function itemName(fullName: string): string {
  const separator = fullName.indexOf("|");
  return separator >= 0 ? fullName.slice(0, separator).trim() : fullName.trim();
}

/**
 * Every localized label the catalog carries for one entry, English included. The
 * pickers search over this set so a Simplified Chinese interface still finds an
 * entry typed in English, and an English interface still finds a Chinese one.
 */
export function skinNameAliases(weaponDefIndex: number, paint: number): string[] {
  const key = `${weaponDefIndex}:${paint}`;
  const aliases: string[] = [];
  for (const table of Object.values(names)) {
    const value = table?.[key];
    if (value) aliases.push(value);
  }
  return aliases;
}

/**
 * One substring match shared by all cosmetics pickers. Besides the names it takes
 * the numeric paint kit and weapon ids, so searching "507", "417" or "10048" finds
 * the entry the same way a name does.
 */
export function matchesCosmeticSearch(
  query: string,
  fields: Array<string | number | null | undefined>
): boolean {
  const needle = query.trim().toLocaleLowerCase();
  if (!needle) return true;
  return fields
    .filter((field): field is string | number => field !== null && field !== undefined && field !== "")
    .join(" ")
    .toLocaleLowerCase()
    .includes(needle);
}
