import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import ts from "../Panel/node_modules/typescript/lib/typescript.js";

const panel = new URL("../Panel/", import.meta.url);

async function load(module, { resolveSkinNames = false } = {}) {
  const url = new URL(`src/data/${module}.ts`, panel);
  let source = await readFile(url, "utf8");
  if (resolveSkinNames) {
    const json = pathToFileURL(new URL("src/data/skinNames.json", panel).pathname.replace(/^\//, "")).href;
    source = source.replace('from "./skinNames.json"', `from "${json}" with { type: "json" }`);
  }
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
    fileName: `${module}.ts`,
  });
  return import(`data:text/javascript;base64,${Buffer.from(compiled.outputText).toString("base64")}`);
}

const order = await load("cosmeticOrder");
const localization = await load("skinLocalization", { resolveSkinNames: true });
const gloveNames = JSON.parse(await readFile(new URL("src/data/gloveSkins.json", panel), "utf8"));
const gloveZh = JSON.parse(await readFile(new URL("src/data/gloveFinishNames.json", panel), "utf8"));
const skinNames = JSON.parse(await readFile(new URL("src/data/skinNames.json", panel), "utf8"));
const weaponSkins = JSON.parse(await readFile(new URL("src/data/weaponSkins.json", panel), "utf8"));

const tail = (label) => label.slice(label.lastIndexOf("|") + 1).trim();

// Knife ordering is the product's preference list, and nothing is hidden.
assert.deepEqual(
  order.KNIFE_TYPE_ORDER.slice(0, order.DEFAULT_SHORTCUT_KNIVES.length),
  order.DEFAULT_SHORTCUT_KNIVES,
  "The default shortcut rotation must be the head of the preferred knife order."
);
assert.deepEqual(
  order.DEFAULT_SHORTCUT_KNIVES,
  [507, 515, 508, 500, 525, 512],
  "Karambit, Butterfly, M9, Bayonet, Skeleton and Falchion are the documented defaults."
);
const knifeIds = [...new Set(weaponSkins.map((row) => row.weapon_defindex).filter((id) => id >= 500 && id <= 540))];
const orderedKnives = knifeIds.map((id) => ({ id })).sort(order.compareKnifeTypes).map((knife) => knife.id);
assert.equal(orderedKnives.length, knifeIds.length, "Sorting must never drop a knife type.");
assert.deepEqual(orderedKnives.slice(0, 15), order.KNIFE_TYPE_ORDER, "The preferred knives must lead in the documented order.");
for (const id of knifeIds) assert.ok(orderedKnives.includes(id), `Knife ${id} must stay selectable.`);

// Preference lists must name finishes that actually exist, or they are dead code.
const knifeFinishNames = new Set(weaponSkins
  .filter((row) => row.weapon_defindex >= 500 && row.weapon_defindex <= 540 && Number(row.paint) > 0)
  .map((row) => tail(skinNames.english[`${row.weapon_defindex}:${row.paint}`] ?? "").toLocaleLowerCase()));
for (const finish of order.PREFERRED_KNIFE_FINISHES)
  assert.ok(knifeFinishNames.has(finish), `Knife preference "${finish}" is not in the catalog.`);
const gloveFinishNames = new Set(gloveNames.map((row) => row.name.toLocaleLowerCase()));
for (const finish of order.PREFERRED_GLOVE_FINISHES)
  assert.ok(gloveFinishNames.has(finish), `Glove preference "${finish}" is not in the catalog.`);

// Preferred finishes lead, the rest keeps catalog order, and the set is unchanged.
const rows = [...knifeFinishNames].map((name, index) => ({ name, index }));
const sorted = order.orderByPreferredFinish(rows, (row) => row.name, order.PREFERRED_KNIFE_FINISHES);
assert.equal(sorted.length, rows.length, "Ranking must be a permutation of the catalog.");
assert.deepEqual([...sorted].map((row) => row.name).sort(), [...rows].map((row) => row.name).sort());
assert.equal(sorted[0].name, order.PREFERRED_KNIFE_FINISHES[0], "The most preferred finish must come first.");
const unprefixed = sorted.filter((row) => !order.PREFERRED_KNIFE_FINISHES.includes(row.name));
assert.deepEqual(unprefixed.map((row) => row.index), [...unprefixed].map((row) => row.index).sort((a, b) => a - b),
  "Unpreferred finishes must keep their original catalog order.");
assert.equal(order.knifeFinishRank("not a real finish"), order.PREFERRED_TAIL);
assert.ok(order.knifeFinishRank("blue steel") < order.knifeFinishRank("crimson web"));
assert.ok(order.gloveFinishRank("black tie") < order.gloveFinishRank("badlands"));

// Simplified Chinese is a first-class display language for skin labels.
assert.ok(localization.localizedSkinName("schinese", 507, 0).includes("爪子刀"),
  "Karambit must have a Chinese name.");
assert.ok(localization.localizedSkinName("schinese", 500, 42).includes("蓝钢"),
  "Blue Steel must have a Chinese name.");
assert.equal(localization.localizedSkinName("schinese", 99999, 99999), "Paint Kit 99999",
  "An unknown entry must fall back to its paint id, not crash.");
const schineseRows = weaponSkins.filter((row) => /[一-鿿]/.test(
  localization.localizedSkinName("schinese", row.weapon_defindex, Number(row.paint), row.name)
));
assert.ok(schineseRows.length / weaponSkins.length > 0.95,
  `Chinese labels must cover the catalog, got ${schineseRows.length}/${weaponSkins.length}.`);

// One search box has to answer to the current language, English, and raw ids.
const blueSteel = { weapon_defindex: 500, paint: 42 };
const fields = (row) => [
  localization.localizedSkinName("schinese", row.weapon_defindex, row.paint),
  localization.localizedSkinName("english", row.weapon_defindex, row.paint),
  ...localization.skinNameAliases(row.weapon_defindex, row.paint),
  row.paint,
];
assert.ok(localization.matchesCosmeticSearch("", fields(blueSteel)), "An empty query matches everything.");
assert.ok(localization.matchesCosmeticSearch("蓝钢", fields(blueSteel)), "A Chinese name must match.");
assert.ok(localization.matchesCosmeticSearch("blue steel", fields(blueSteel)),
  "English must match inside the Chinese interface.");
assert.ok(localization.matchesCosmeticSearch("BLUE STEEL", fields(blueSteel)), "Matching must be case-insensitive.");
assert.ok(localization.matchesCosmeticSearch("42", fields(blueSteel)), "A paint kit id must be searchable.");
assert.ok(!localization.matchesCosmeticSearch("vanilla", fields(blueSteel)), "A wrong name must not match.");
assert.ok(localization.skinNameAliases(500, 42).some((label) => label.includes("Blue Steel")),
  "Aliases must expose the English label regardless of the interface language.");

// Glove finish translations are derived from the paint kit table, so they must
// stay real Chinese text against real glove names and nothing else.
assert.ok(Object.keys(gloveZh).length > 0, "Some glove finishes must be localised.");
for (const [english, chinese] of Object.entries(gloveZh)) {
  assert.ok(gloveFinishNames.has(english.toLocaleLowerCase()), `"${english}" is not a glove finish.`);
  assert.match(chinese, /[一-鿿]/, `"${english}" mapped to non-Chinese "${chinese}".`);
}

console.log(`Cosmetic ordering, Simplified Chinese coverage and search tests passed (${knifeIds.length} knives, ${weaponSkins.length} skins, ${gloveNames.length} glove finishes, ${Object.keys(gloveZh).length} localised).`);
