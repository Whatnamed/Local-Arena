import { Crosshair, Settings2, Sticker, type LucideIcon } from "lucide-react";
import StatusBar from "../components/StatusBar";
import ModeCard from "./ModeCard";
import { useStore } from "../state/store";
import { useT, type I18nKey } from "../i18n";

export type DashboardTarget = "settings" | "weaponPresets" | "stickers";

type Tile = { view: DashboardTarget; key: I18nKey; icon: LucideIcon };

export default function OverviewDashboard({ onNavigate, stickersVisible }: {
  onNavigate: (view: DashboardTarget) => void;
  stickersVisible: boolean;
}) {
  const t = useT();
  const { directory } = useStore();
  const tiles: Tile[] = [
    { view: "weaponPresets", key: "weapons.title", icon: Crosshair },
    ...(stickersVisible ? [{ view: "stickers" as const, key: "stickers.title" as I18nKey, icon: Sticker }] : []),
    { view: "settings", key: "set.title", icon: Settings2 },
  ];

  return (
    <div className="dashboard">
      <header className="workspace__head">
        <span className="workspace__eyebrow">Local Cosmetics</span>
        <h1>{t("nav.overview")}</h1>
      </header>
      <StatusBar onOpenSettings={() => onNavigate("settings")} />

      <div className="dashboard__controls">
        <ModeCard />
        <section className="cos-card dashboard__note">
          <strong>{t("cosmetics.sectionWeapons")}</strong>
          <p>{directory?.valid ? t("mode.preview") : t("set.noCsgo")}</p>
        </section>
      </div>

      <div className="quick-grid" role="navigation" aria-label={t("overview.quickActions")}>
        {tiles.map(({ view, key, icon: Icon }) => (
          <button key={view} className="quick-tile" onClick={() => onNavigate(view)}>
            <Icon size={18} strokeWidth={1.9} aria-hidden="true" />
            <span>{t(key)}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
