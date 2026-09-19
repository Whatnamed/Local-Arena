import { ShieldCheck } from "lucide-react";
import { useT } from "../../i18n";

/** Kept as a safe fallback for older local navigation state; it has no install action. */
export default function OnlineUpdatePage() {
  const t = useT();
  return (
    <section className="online-update-page">
      <div className="upd-card">
        <ShieldCheck size={22} aria-hidden="true" />
        <h2>{t("set.updates")}</h2>
        <p>{t("set.updatesDesc")}</p>
        <p>Online installation is disabled for Cosmetics-only v1. Install a reviewed package manually.</p>
      </div>
    </section>
  );
}
