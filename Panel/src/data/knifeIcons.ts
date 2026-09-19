import skins from "./skinImages.json";
import { DEFAULT_KNIFE_ORDER } from "./knifeOrdering";

export type KnifeIcon = { id: number; url: string };

const KNIFE_IDS = DEFAULT_KNIFE_ORDER;

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
