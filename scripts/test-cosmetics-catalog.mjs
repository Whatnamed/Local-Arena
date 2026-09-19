import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import ts from "../Panel/node_modules/typescript/lib/typescript.js";

const compile = (source, fileName) => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
  fileName,
}).outputText;

const orderingSource = await readFile(new URL("../Panel/src/data/cosmeticOrdering.ts", import.meta.url), "utf8");
const ordering = await import(`data:text/javascript;base64,${Buffer.from(compile(orderingSource, "cosmeticOrdering.ts")).toString("base64")}`);

const expectedKnifeOrder = [507, 515, 508, 500, 525, 512, 522, 523, 509, 505, 519, 503, 521, 526, 514];
assert.deepEqual(ordering.PREFERRED_KNIFE_IDS, expectedKnifeOrder);

const skinImages = JSON.parse(await readFile(new URL("../Panel/src/data/skinImages.json", import.meta.url), "utf8"));
const catalogKnifeIds = [...new Set(skinImages.filter((row) => Number(row.paint) === 0).map((row) => Number(row.weapon_defindex)))].filter((id) => id >= 500 && id <= 526);
assert.ok(expectedKnifeOrder.every((id) => catalogKnifeIds.includes(id)), "every preferred knife must remain in the catalog");
assert.equal(new Set([...expectedKnifeOrder, ...catalogKnifeIds]).size, catalogKnifeIds.length, "ordering must not add or remove catalog knife IDs");

assert.ok(ordering.finishPreferenceRank("Vanilla") < ordering.finishPreferenceRank("Rust Coat"));
assert.ok(ordering.finishPreferenceRank("Blue Steel") < ordering.finishPreferenceRank("Rust Coat"));
assert.ok(ordering.finishPreferenceRank("Black Laminate") < ordering.finishPreferenceRank("Rust Coat"));
assert.ok(ordering.finishPreferenceRank("Night Stripe") < ordering.finishPreferenceRank("Rust Coat"));
assert.ok(ordering.glovePreferenceRank("Nocts") < ordering.glovePreferenceRank("Fade"));

const names = JSON.parse(await readFile(new URL("../Panel/src/data/skinNames.json", import.meta.url), "utf8"));
const localizationSource = await readFile(new URL("../Panel/src/data/skinLocalization.ts", import.meta.url), "utf8");
const injectedLocalization = localizationSource.replace(
  'import namesByLanguage from "./skinNames.json";',
  `const namesByLanguage = ${JSON.stringify(names)};`,
);
const localization = await import(`data:text/javascript;base64,${Buffer.from(compile(injectedLocalization, "skinLocalization.ts")).toString("base64")}`);
const bilingualKey = Object.keys(names.english).find((key) => names.schinese?.[key] && names.english[key]);
assert.ok(bilingualKey, "skin catalog must contain a bilingual entry");
const [weaponDefIndex, paint] = bilingualKey.split(":").map(Number);
const searchText = localization.localizedSkinSearchText("schinese", weaponDefIndex, paint);
assert.ok(searchText.includes(names.english[bilingualKey]), "Chinese search must include the English alias");
assert.ok(searchText.includes(String(paint)), "skin search must include the Paint Kit ID");

console.log("Cosmetics catalog ordering, bilingual alias, and compatibility tests passed.");
