import { useEffect, useState } from "react";
import { Crosshair, LayoutDashboard, Settings2, Sticker, type LucideIcon } from "lucide-react";
import TitleBar from "./components/TitleBar";
import ErrorModal from "./components/ErrorModal";
import OverviewDashboard, { type DashboardTarget } from "./panels/OverviewDashboard";
import WeaponPresetsPanel from "./panels/WeaponPresetsPanel";
import SettingsView from "./panels/settings/SettingsView";
import StickersPanel from "./panels/StickersPanel";
import FirstRunLanguages from "./panels/settings/FirstRunLanguages";
import { useStore } from "./state/store";
import { useT, type I18nKey } from "./i18n";
import appLogo from "./assets/app-logo.png";
import { stickerFeatureEnabled } from "./lib/stickerEditor";
import { APP_DISPLAY_VERSION } from "./lib/version";
import { useAppearance } from "./state/appearance";
import "./App.css";

type View = "main" | DashboardTarget;

export default function App() {
  const { error, clearError, ready, config, exportDiagnostics } = useStore();
  const { appearance } = useAppearance();
  const t = useT();
  const stickersVisible = stickerFeatureEnabled(config);
  const [view, setView] = useState<View>(() => {
    const stored = localStorage.getItem("cs2bi.view");
    return stored === "weaponPresets" || stored === "stickers" || stored === "settings" ? stored : "main";
  });

  useEffect(() => {
    localStorage.setItem("cs2bi.view", view);
  }, [view]);

  useEffect(() => {
    if (view === "stickers" && !stickersVisible) setView("main");
  }, [stickersVisible, view]);

  const firstRun = ready && !!config && !config.first_run_done;
  const nav: { view: View; key: I18nKey; icon: LucideIcon }[] = [
    { view: "main", key: "nav.overview", icon: LayoutDashboard },
    { view: "weaponPresets", key: "weapons.title", icon: Crosshair },
    ...(stickersVisible ? [{ view: "stickers" as const, key: "stickers.title" as I18nKey, icon: Sticker }] : []),
    { view: "settings", key: "set.title", icon: Settings2 },
  ];

  return (
    <div className="shell">
      <TitleBar
        title={`${appearance.brand_name} v${APP_DISPLAY_VERSION}`}
        showSettings
        onSettings={() => setView((current) => current === "settings" ? "main" : "settings")}
      />

      <div className="shell__frame">
        <aside className="sidebar">
          <div className="sidebar__brand">
            <img
              className={`sidebar__mark sidebar__mark--${appearance.logo?.shape ?? "rounded"}`}
              src={appearance.logo?.data_url || appLogo}
              style={{ objectFit: appearance.logo?.fit ?? "cover" }}
              alt=""
              aria-hidden="true"
            />
            <span className="sidebar__brand-copy"><strong>{appearance.brand_name}</strong></span>
          </div>

          <span className="sidebar__label">{t("nav.workspace")}</span>
          <nav className="sidebar__nav" aria-label={t("nav.workspace")}>
            {nav.map(({ view: target, key, icon: Icon }) => (
              <button
                key={target}
                className={`sidebar__item ${view === target ? "is-active" : ""}`}
                onClick={() => setView(target)}
                aria-current={view === target ? "page" : undefined}
              >
                <Icon size={18} strokeWidth={1.9} />
                <span>{t(key)}</span>
              </button>
            ))}
          </nav>

          <div className="sidebar__footer">
            <span>Local Cosmetics</span>
            <small>v{APP_DISPLAY_VERSION}</small>
          </div>
        </aside>

        <main className="workspace">
          {view === "settings" ? <SettingsView />
            : view === "weaponPresets" ? <WeaponPresetsPanel />
              : view === "stickers" ? <StickersPanel />
                : <OverviewDashboard onNavigate={setView} stickersVisible={stickersVisible} />}
        </main>
      </div>

      <ErrorModal error={error} onClose={clearError} onExport={exportDiagnostics} />
      {firstRun && <FirstRunLanguages />}
    </div>
  );
}
