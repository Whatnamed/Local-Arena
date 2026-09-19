import { useState } from "react";
import type { AppConfig, KnifeShortcutState } from "../lib/api";
import WeaponPresetsPanel from "../panels/WeaponPresetsPanel";
import { DEFAULT_SHORTCUT_KNIVES } from "../data/cosmeticOrder";
import { AppStatePreviewProvider } from "../state/store";
import "./WorkshopBrowserPreview.css";

const previewAppConfig: AppConfig = {
  language: "schinese",
  knife_shortcut_bind: "\\",
  csgo_path: "browser-preview",
  first_run_done: true,
  welcome_story_prompt_presented: true,
};

const bindLineFor = (key: string) => `bind ${key} "css_cs2bi_knife_next"`;

/** Browser-only harness for the optional quick-knife rotation. The save path is
 *  replaced by local state so the card can be operated without Tauri or CS2. */
export default function WeaponPresetsBrowserPreview() {
  const [shortcut, setShortcut] = useState<KnifeShortcutState>({
    bind_key: "\\",
    defindexes: [...DEFAULT_SHORTCUT_KNIVES],
    enabled: false,
    bind_line: bindLineFor("\\"),
    cs2_running: false,
  });

  return <AppStatePreviewProvider value={{
    config: previewAppConfig,
    csgoPath: "browser-preview",
    process: { running: false, pid: null, executable: null, path_accessible: true, matches_selected: true },
    reportError: (error) => console.error("[weapon-preview]", error),
    knifeShortcut: shortcut,
    applyKnifeShortcut: async (bindKey, defindexes, enabled) => {
      const next = { ...shortcut, bind_key: bindKey, defindexes, enabled, bind_line: bindLineFor(bindKey) };
      setShortcut(next);
      return next;
    },
  }}>
    <main className="workshop-browser-preview">
      <WeaponPresetsPanel />
    </main>
  </AppStatePreviewProvider>;
}
