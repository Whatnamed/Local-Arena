import { useState } from "react";
import Card from "../components/Card";
import { useToast } from "../components/Toast";
import { useStore } from "../state/store";
import { useT } from "../i18n";
import { api } from "../lib/api";
import "./ModeCard.css";

/** The only launch mode exposed by the Cosmetics-only Panel. */
export default function ModeCard() {
  const { mode, config, csgoPath, applyMode, reportError } = useStore();
  const toast = useToast();
  const t = useT();
  const [working, setWorking] = useState(false);
  const current = mode?.current ?? config?.mode ?? "online";
  const localReady = current === "preview";

  const prepareLocalMode = async () => {
    if (!csgoPath || working) return;
    setWorking(true);
    try {
      const info = await applyMode("preview");
      if (info) toast.show(t("mode.launchPreview"), "green");
    } finally {
      setWorking(false);
    }
  };

  const launch = async () => {
    if (!csgoPath || working) return;
    setWorking(true);
    try {
      await applyMode("preview");
      await api.launchCs2();
      toast.show(t("mode.launchPreview"), "green");
    } catch (error) {
      reportError(error);
    } finally {
      setWorking(false);
    }
  };

  return (
    <Card title={t("mode.title")}>
      <p className="selection-detail" aria-live="polite">
        {localReady ? t("mode.preview") : t("mode.online")}
      </p>
      <div className="mode__actions">
        <button disabled={!csgoPath || working || localReady} onClick={() => void prepareLocalMode()}>
          {t("mode.preview")}
        </button>
        <button className="mode__launch" disabled={!csgoPath || working} onClick={() => void launch()}>
          {working ? t("mode.launching") : t("mode.launchPreview")}
        </button>
      </div>
    </Card>
  );
}
