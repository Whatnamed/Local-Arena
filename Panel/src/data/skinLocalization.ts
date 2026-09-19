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

export type SkinSearchOptions = {
  query: string;
  language: string | null | undefined;
  weaponDefIndex: number;
  paint: number;
  fallbackName?: string;
  extraTerms?: (string | undefined | null)[];
};

export function matchSkinSearch({
  query,
  language,
  weaponDefIndex,
  paint,
  fallbackName,
  extraTerms,
}: SkinSearchOptions): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;

  // 1. Paint numeric match
  if (String(paint) === q || String(paint).includes(q)) return true;

  // 2. Localized skin full name and finish name
  const localized = localizedSkinName(language, weaponDefIndex, paint, fallbackName).toLowerCase();
  if (localized.includes(q)) return true;
  const finish = finishName(localized).toLowerCase();
  if (finish.includes(q)) return true;

  // 3. English alias match (e.g. user in Chinese UI searching "Blue Steel" or "Case Hardened")
  const key = `${weaponDefIndex}:${paint}`;
  const enName = names.english?.[key]?.toLowerCase();
  if (enName) {
    if (enName.includes(q) || finishName(enName).includes(q)) return true;
  }

  // 4. Simplified Chinese alias match (e.g. user in English UI searching "蓝钢")
  const zhName = names.schinese?.[key]?.toLowerCase();
  if (zhName) {
    if (zhName.includes(q) || finishName(zhName).includes(q)) return true;
  }

  // 5. Fallback name match
  if (fallbackName) {
    const fb = fallbackName.toLowerCase();
    if (fb.includes(q) || finishName(fb).includes(q)) return true;
  }

  // 6. Extra terms (phases, model names, etc.)
  if (extraTerms) {
    for (const term of extraTerms) {
      if (term && term.toLowerCase().includes(q)) return true;
    }
  }

  return false;
}
