import type { AppConfig, KnifeCustomizerConfig, KnifePreset } from "../lib/api";
import StickersPanel from "../panels/StickersPanel";
import { AppStatePreviewProvider } from "../state/store";
import { WEAPON_ICONS } from "../data/weaponIcons";
import skinImages from "../data/skinImages.json";
import placementRows from "../data/cosmeticPlacements.json";
import charmRows from "../data/charmCatalog.json";
import { STICKERS } from "../data/stickers";
import { defaultStickerPlacement } from "../lib/stickerEditor";
import "./WorkshopBrowserPreview.css";

type SkinImage = { weapon_defindex: number; paint: number | string; legacy_model: boolean };
type WeaponPlacement = {
  stickerSchemaCount: number;
  stickerPositions: { schema: number }[];
  charmPositions: { placementId: number }[];
};

const placements = placementRows as Record<string, WeaponPlacement>;
const skins = skinImages as SkinImage[];
const previewCharms = charmRows as { id: number }[];

function previewPreset(weaponId: number, team: "ct" | "t"): KnifePreset {
  const paintedSkins = skins.filter((entry) => entry.weapon_defindex === weaponId && Number(entry.paint) > 0);
  const paint = Number(paintedSkins.find((entry) => entry.legacy_model)?.paint ?? paintedSkins[0]?.paint ?? 0);
  const capability = placements[String(weaponId)];
  const stickerCatalog = STICKERS.filter((entry) => entry.id > 0);
  const stickerStart = (weaponId * 5 + (team === "ct" ? 0 : 5)) % stickerCatalog.length;
  const stickers = Array.from({ length: 5 }, (_, slot) => stickerCatalog[(stickerStart + slot) % stickerCatalog.length]);
  const charm = previewCharms[(weaponId + (team === "ct" ? 0 : 1)) % previewCharms.length];
  const charmPosition = capability?.charmPositions[0];
  return {
    paint,
    seed: 0,
    wear: 0.08,
    name_tag: "",
    stattrak_enabled: false,
    stattrak_count: 0,
    souvenir_enabled: false,
    stickers: capability ? stickers.flatMap((sticker, slot) => {
      const placement = defaultStickerPlacement(slot, capability.stickerSchemaCount);
      return placement ? [{
        slot,
        id: sticker.id,
        ...placement,
        wear: 0,
        scale: 1,
        rotation: 0,
      }] : [];
    }) : [],
    charm: charm && charmPosition ? { id: charm.id, placement_id: charmPosition.placementId, seed: 0 } : null,
  };
}

function teamPresets(team: "ct" | "t") {
  return Object.fromEntries(WEAPON_ICONS
    .filter((weapon) => (weapon.availability === team || weapon.availability === "shared") && placements[String(weapon.id)])
    .map((weapon) => [String(weapon.id), previewPreset(weapon.id, team)]));
}

const previewConfig: KnifeCustomizerConfig = {
  schema_version: 5,
  enabled: true,
  apply_to_human_players: true,
  music_kit_id: 0,
  loadouts: {
    ct: {
      agent_model: "",
      default_knife_defindex: 0,
      knife_presets: {},
      glove: { enabled: false, defindex: 0, paint: 0, seed: 0, wear: 0.08 },
      gun_presets: teamPresets("ct"),
    },
    t: {
      agent_model: "",
      default_knife_defindex: 0,
      knife_presets: {},
      glove: { enabled: false, defindex: 0, paint: 0, seed: 0, wear: 0.08 },
      gun_presets: teamPresets("t"),
    },
  },
  shared_weapon_links: {},
  stickers_enabled: true,
  charms_enabled: true,
  agents_enabled: true,
};

const previewAppConfig: AppConfig = {
  language: "schinese",
  drop_knife_bind: "",
  drop_knife_subclasses: [],
  csgo_path: "browser-preview",
  first_run_done: true,
  welcome_story_prompt_presented: true,
  experimental_features_enabled: true,
  experimental_stickers_enabled: true,
};

export default function WorkshopBrowserPreview() {
  return <AppStatePreviewProvider value={{
    config: previewAppConfig,
    csgoPath: "browser-preview",
    process: { running: false, pid: null, executable: null, path_accessible: true, matches_selected: true },
    reportError: (error) => console.error("[workshop-preview]", error),
  }}>
    <main className="workshop-browser-preview">
      <StickersPanel browserPreviewConfig={previewConfig} />
    </main>
  </AppStatePreviewProvider>;
}
