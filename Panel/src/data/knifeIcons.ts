import skins from "./skinImages.json";
import { PREFERRED_KNIFE_IDS } from "./cosmeticOrdering";

export type KnifeIcon = { id: number; url: string };

const CATALOG_KNIFE_IDS = [500, 503, 505, 506, 507, 508, 509, 512, 514, 515, 516,
  517, 518, 519, 520, 521, 522, 523, 525, 526];
const KNIFE_IDS = [
  ...PREFERRED_KNIFE_IDS,
  ...CATALOG_KNIFE_IDS.filter((id) => !PREFERRED_KNIFE_IDS.includes(id as (typeof PREFERRED_KNIFE_IDS)[number])),
];

type SkinRow = {
  weapon_defindex: number;
  paint: number | string;
  image: string;
};

const rows = skins as SkinRow[];

export const KNIFE_ICONS: KnifeIcon[] = KNIFE_IDS.map(
  (id) => {
    const base = rows.find(
      (row) => Number(row.weapon_defindex) === id && Number(row.paint) === 0
    );
    return { id, url: base?.image ?? "" };
  }
);
