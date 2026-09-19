import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import ts from "../Panel/node_modules/typescript/lib/typescript.js";

const sourcePath = new URL("../Panel/src/lib/stickerEditor.ts", import.meta.url);
const source = await readFile(sourcePath, "utf8");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
  fileName: "stickerEditor.ts",
});
const editor = await import(`data:text/javascript;base64,${Buffer.from(compiled.outputText).toString("base64")}`);

const sticker = (slot, id, patch = {}) => ({
  slot, id, schema: slot, wear: 0, scale: 1, rotation: 0,
  offset_x: 0, offset_y: 0, custom_position: false,
  ...patch,
});
const preset = { paint: 661, seed: 0, wear: 0.01, name_tag: "", stattrak_enabled: false, stattrak_count: 0, souvenir_enabled: false, stickers: [] };
const loadout = () => ({ agent_model: "", default_knife_defindex: 0, knife_presets: {}, glove: { enabled: false, defindex: 5030, paint: 10048, seed: 0, wear: 0.01 }, gun_presets: { "9": { ...preset } } });
const config = { schema_version: 5, enabled: true, apply_to_human_players: true, music_kit_id: 0, loadouts: { ct: loadout(), t: loadout() }, shared_weapon_links: { "9": true }, stickers_enabled: true, charms_enabled: true, agents_enabled: true };

assert.equal(editor.STICKER_RELEASE_ENABLED, true);
assert.equal(editor.stickerFeatureEnabled({ experimental_features_enabled: true, experimental_stickers_enabled: true }), true);
assert.equal(editor.stickerFeatureEnabled({ experimental_features_enabled: false, experimental_stickers_enabled: true }), false);
assert.equal(editor.availableStickerSlotCount(4), 5);
assert.equal(editor.availableStickerSlotCount(5), 5);
assert.equal(editor.availableStickerSlotCount(6), 5);
assert.equal(editor.availableStickerSlotCount(0), 0);
assert.equal(editor.availableStickerSlotCount(Number.NaN), 0);
assert.deepEqual(editor.defaultStickerPlacement(3, 4), {
  schema: 3, offset_x: 0, offset_y: 0, custom_position: false,
});
assert.deepEqual(editor.defaultStickerPlacement(4, 4), {
  schema: 3, offset_x: 0.45, offset_y: 0.45, custom_position: true,
});
assert.deepEqual(editor.defaultStickerPlacement(4, 6), {
  schema: 4, offset_x: 0, offset_y: 0, custom_position: false,
});
assert.equal(editor.defaultStickerPlacement(5, 4), null);

const entries = [{ id: 1, name: "Alpha" }, { id: 22, name: "Bravo" }, { id: 3, name: "Charlie" }];
assert.deepEqual(editor.filterStickerCatalog(entries, "22", (entry) => entry.name).map((entry) => entry.id), [22]);
assert.deepEqual(editor.filterStickerCatalog(entries, "bravo", (entry) => entry.name).map((entry) => entry.id), [22]);
assert.deepEqual(editor.paginateStickerCatalog(entries, 8, 2), { page: 1, pageCount: 2, entries: [entries[2]] });

let stickers = editor.replaceSticker([], sticker(2, 10));
stickers = editor.replaceSticker(stickers, sticker(2, 11, { wear: 0.5 }));
assert.deepEqual(stickers, [sticker(2, 11, { wear: 0.5 })]);
stickers = editor.replaceSticker(stickers, sticker(3, 12));
stickers = editor.swapStickerSlots(stickers, 2, 3);
assert.deepEqual(stickers, [sticker(2, 12, { schema: 3 }), sticker(3, 11, { schema: 2, wear: 0.5 })]);
assert.deepEqual(editor.removeSticker(stickers, 2), [sticker(3, 11, { schema: 2, wear: 0.5 })]);

assert.equal(editor.clampStickerValue(Number.NaN, -1, 1), -1);
assert.equal(editor.clampStickerValue(4, -1, 1), 1);
assert.equal(editor.clampStickerValue(-4, -1, 1), -1);

const linked = editor.updateGunPresetStickers(config, "ct", 9, config.loadouts.ct.gun_presets["9"], [sticker(0, 10)]);
assert.equal(linked.loadouts.ct.gun_presets["9"].stickers.length, 1);
assert.equal(linked.loadouts.t.gun_presets["9"].stickers.length, 0);
assert.equal(linked.shared_weapon_links["9"], true);
const untouchedPreset = { ...preset, paint: 37, stickers: [sticker(0, 77)] };
const multiWeaponConfig = {
  ...config,
  loadouts: {
    ...config.loadouts,
    ct: { ...config.loadouts.ct, gun_presets: { ...config.loadouts.ct.gun_presets, "1": untouchedPreset } },
  },
};
const oneWeaponChanged = editor.updateGunPresetStickers(multiWeaponConfig, "ct", 9, multiWeaponConfig.loadouts.ct.gun_presets["9"], [sticker(0, 10)]);
assert.deepEqual(oneWeaponChanged.loadouts.ct.gun_presets["1"], untouchedPreset);

const charm = { id: 37, placement_id: 2, seed: 99 };
const charmLinked = editor.updateGunPresetCharm(config, "ct", 9, config.loadouts.ct.gun_presets["9"], charm);
assert.deepEqual(charmLinked.loadouts.ct.gun_presets["9"].charm, charm);
assert.equal(charmLinked.loadouts.t.gun_presets["9"].charm, undefined);
const decoratedPreset = { ...preset, paint: 344, stickers: [sticker(0, 22)], charm };
const linkedBase = editor.withPreservedGunPresetDecorations({ ...preset, paint: 279 }, decoratedPreset);
assert.equal(linkedBase.paint, 279);
assert.deepEqual(linkedBase.stickers, decoratedPreset.stickers);
assert.deepEqual(linkedBase.charm, decoratedPreset.charm);
assert.notEqual(linkedBase.stickers, decoratedPreset.stickers);
assert.notEqual(linkedBase.charm, decoratedPreset.charm);

const agents = JSON.parse(await readFile(new URL("../Panel/src/data/agentCatalog.json", import.meta.url), "utf8"));
const charms = JSON.parse(await readFile(new URL("../Panel/src/data/charmCatalog.json", import.meta.url), "utf8"));
assert.equal(agents.filter((entry) => entry.team === "ct").length, 35);
assert.equal(agents.filter((entry) => entry.team === "t").length, 44);
assert.equal(new Set(agents.map((entry) => entry.model)).size, agents.length);
assert.ok(agents.every((entry) => entry.model.startsWith(`agents\\models\\${entry.team === "ct" ? "ctm_" : "tm_"}`)));
assert.equal(agents.filter((entry) => entry.image).length, 63);
assert.equal(charms.filter((entry) => entry.image).length, 78);
assert.ok([...agents, ...charms].filter((entry) => entry.image).every((entry) =>
  entry.image.startsWith("https://community.akamai.steamstatic.com/economy/image/")));

console.log("Cosmetic editor release gate, catalog, inventory images, slot, bounds, charm, agent, and shared-link tests passed.");
