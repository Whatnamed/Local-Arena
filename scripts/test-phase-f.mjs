import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import ts from "../Panel/node_modules/typescript/lib/typescript.js";

const skinNamesJson = await readFile(new URL("../Panel/src/data/skinNames.json", import.meta.url), "utf8");

async function transpileAndImport(relPath, fileName) {
  const sourcePath = new URL(relPath, import.meta.url);
  let source = await readFile(sourcePath, "utf8");
  if (source.includes('./skinNames.json')) {
    source = source.replace('import namesByLanguage from "./skinNames.json";',
      `const namesByLanguage = ${skinNamesJson};`);
  }
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
    fileName,
  });
  return import(`data:text/javascript;base64,${Buffer.from(compiled.outputText).toString("base64")}`);
}

const knifeOrdering = await transpileAndImport("../Panel/src/data/knifeOrdering.ts", "knifeOrdering.ts");
const skinLocalization = await transpileAndImport("../Panel/src/data/skinLocalization.ts", "skinLocalization.ts");

// 1. Knife Order Verification
const order = knifeOrdering.DEFAULT_KNIFE_ORDER;
assert.equal(order.length, 20, "Must contain all 20 knife models.");
assert.deepEqual(order.slice(0, 6), [507, 515, 508, 500, 525, 512],
  "Must start with Karambit -> Butterfly -> M9 -> Bayonet -> Skeleton -> Falchion.");

// 2. Finish sorting test
const testSkins = [
  { paint: 561 }, // Lore (38)
  { paint: 42 },  // Blue Steel (100)
  { paint: 100 }, // Unknown (0)
  { paint: 40 },  // Night (95)
  { paint: 98 },  // Ultraviolet (90)
];
const sorted = knifeOrdering.sortKnifeSkins(testSkins);
assert.equal(sorted.length, 5, "Sorted skins must retain all elements.");
assert.deepEqual(sorted.map(s => s.paint), [42, 40, 98, 561, 100],
  "Dark/neutral finishes (Blue Steel, Night, Ultraviolet) must be prioritized at top.");

// 3. Multi-language Search Tests
// AK-47 Case Hardened (defindex 7, paint 44, zh: 表面淬火, en: Case Hardened)
assert.equal(skinLocalization.matchSkinSearch({
  query: "表面淬火",
  language: "schinese",
  weaponDefIndex: 7,
  paint: 44,
}), true, "Should match Chinese name in Chinese UI");

assert.equal(skinLocalization.matchSkinSearch({
  query: "Case Hardened",
  language: "schinese",
  weaponDefIndex: 7,
  paint: 44,
}), true, "Should match English alias even in Chinese UI");

assert.equal(skinLocalization.matchSkinSearch({
  query: "44",
  language: "schinese",
  weaponDefIndex: 7,
  paint: 44,
}), true, "Should match numeric paint ID");

assert.equal(skinLocalization.matchSkinSearch({
  query: "Blue Steel",
  language: "schinese",
  weaponDefIndex: 508,
  paint: 42,
}), true, "Should match Blue Steel on knife in Chinese UI");

assert.equal(skinLocalization.matchSkinSearch({
  query: "蓝钢",
  language: "english",
  weaponDefIndex: 508,
  paint: 42,
}), true, "Should match Chinese alias even in English UI");

assert.equal(skinLocalization.matchSkinSearch({
  query: "completely_unrelated_query",
  language: "schinese",
  weaponDefIndex: 7,
  paint: 44,
}), false, "Mismatched query must return false");

// Extra terms (e.g. ruby phase)
assert.equal(skinLocalization.matchSkinSearch({
  query: "ruby",
  language: "schinese",
  weaponDefIndex: 507,
  paint: 415,
  extraTerms: ["红宝石", "Ruby"],
}), true, "Extra terms like phase labels must match");

// Fallback test
const fallback = skinLocalization.localizedSkinName("unknown_lang", 9999, 9999, "Custom Fallback");
assert.equal(fallback, "Custom Fallback", "Missing localized name must use fallback");

console.log("Phase F tests passed successfully.");
