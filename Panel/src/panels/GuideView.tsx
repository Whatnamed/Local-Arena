import { useCallback, useEffect, useRef, useState } from "react";
import {
  Crosshair,
  Download,
  LifeBuoy,
  type LucideIcon,
} from "lucide-react";
import Modal from "../components/Modal";
import { useT, type I18nKey } from "../i18n";
import overviewImage from "../assets/guide/01-overview.png";
import weaponPresetsImage from "../assets/guide/02-weapon-presets.png";
import installationImage from "../assets/guide/04-installation-recovery.jpg";
import firstLanguageImage from "../assets/guide/08-first-language.jpg";
import firstDirectoryImage from "../assets/guide/09-first-directory.jpg";
import firstPreviewImage from "../assets/guide/10-first-preview.jpg";
import firstCompleteImage from "../assets/guide/11-first-complete.jpg";
import mixedEnvironmentImage from "../assets/guide/12-first-mixed.jpg";
import healthRepairImage from "../assets/guide/13-health-repair.jpg";
import processLockImage from "../assets/guide/14-process-lock.jpg";
import directoryMissingImage from "../assets/guide/15-directory-missing.jpg";
import "./GuideView.css";

type Severity = "red" | "yellow" | "green";

type GuideStep = {
  id: string;
  image: string;
  title: I18nKey;
  body: I18nKey;
  points: I18nKey[];
  severity?: Severity;
};

type Chapter = {
  id: string;
  num: string;
  icon: LucideIcon;
  title: I18nKey;
  body: I18nKey;
};

const CHAPTERS: Chapter[] = [
  { id: "guide-ch-install", num: "01", icon: Download, title: "guide.install.title", body: "guide.install.body" },
  { id: "guide-ch-cosmetics", num: "02", icon: Crosshair, title: "guide.cosmetics.title", body: "guide.cosmetics.body" },
  { id: "guide-ch-trouble", num: "03", icon: LifeBuoy, title: "guide.trouble.title", body: "guide.trouble.body" },
];

const INSTALL_STEPS: GuideStep[] = [
  { id: "guide-install-1", image: firstLanguageImage, title: "guide.install1.title", body: "guide.install1.body", points: ["guide.install1.point1", "guide.install1.point2"] },
  { id: "guide-install-2", image: firstDirectoryImage, title: "guide.install2.title", body: "guide.install2.body", points: ["guide.install2.point1", "guide.install2.point2", "guide.install2.point3"] },
  { id: "guide-install-3", image: firstPreviewImage, title: "guide.install3.title", body: "guide.install3.body", points: ["guide.install3.point1", "guide.install3.point2", "guide.install3.point3"] },
  { id: "guide-install-4", image: firstCompleteImage, title: "guide.install4.title", body: "guide.install4.body", points: ["guide.install4.point1"] },
];

const COSMETICS_STEPS: GuideStep[] = [
  {
    id: "guide-cosmetics-1",
    image: overviewImage,
    title: "guide.stepLaunch.title",
    body: "guide.stepLaunch.body",
    points: ["guide.stepLaunch.point1", "guide.stepLaunch.point2", "guide.stepLaunch.point3"],
  },
  { id: "guide-cosmetics-2", image: weaponPresetsImage, title: "guide.step5.title", body: "guide.step5.body", points: ["guide.step5.point1", "guide.step5.point2", "guide.step5.point3", "guide.step5.point4"] },
];

const TROUBLE_STEPS: GuideStep[] = [
  { id: "guide-issue-1", severity: "red", image: directoryMissingImage, title: "guide.issue1.title", body: "guide.issue1.body", points: ["guide.issue1.point1", "guide.issue1.point2", "guide.issue1.point3"] },
  { id: "guide-issue-2", severity: "red", image: mixedEnvironmentImage, title: "guide.issue2.title", body: "guide.issue2.body", points: ["guide.issue2.point1", "guide.issue2.point2", "guide.issue2.point3"] },
  { id: "guide-issue-3", severity: "yellow", image: healthRepairImage, title: "guide.issue3.title", body: "guide.issue3.body", points: ["guide.issue3.point1", "guide.issue3.point2"] },
  { id: "guide-issue-4", severity: "yellow", image: processLockImage, title: "guide.issue4.title", body: "guide.issue4.body", points: ["guide.issue4.point1", "guide.issue4.point2", "guide.issue4.point3"] },
  { id: "guide-issue-6", severity: "green", image: installationImage, title: "guide.issue6.title", body: "guide.issue6.body", points: ["guide.issue6.point2", "guide.issue6.point3"] },
];

const num = (n: number) => String(n).padStart(2, "0");

function Points({ items }: { items: I18nKey[] }) {
  const t = useT();
  return <ul className="guide__points">{items.map((item) => <li key={item}>{t(item)}</li>)}</ul>;
}

function Shot({ image, caption, eager, onZoom }: { image: string; caption: string; eager?: boolean; onZoom: (src: string, caption: string) => void }) {
  const t = useT();
  return (
    <figure className="shot">
      <button type="button" className="shot__btn" onClick={() => onZoom(image, caption)} aria-label={t("guide.enlarge")} title={t("guide.enlarge")}>
        <span className="shot__chrome" aria-hidden="true"><i /><i /><i /></span>
        <img src={image} alt={caption} loading={eager ? "eager" : "lazy"} />
      </button>
    </figure>
  );
}

type Props = {
  /** Anchor id requested from outside (e.g. the error modal). Consumed after scrolling. */
  anchor: string | null;
  onAnchorHandled: () => void;
};

export default function GuideView({ anchor, onAnchorHandled }: Props) {
  const t = useT();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(CHAPTERS[0].id);
  const [zoom, setZoom] = useState<{ src: string; caption: string } | null>(null);

  const scrollTo = useCallback((id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, []);

  useEffect(() => {
    if (!anchor) return;
    const raf = requestAnimationFrame(() => {
      scrollTo(anchor);
      onAnchorHandled();
    });
    return () => cancelAnimationFrame(raf);
  }, [anchor, onAnchorHandled, scrollTo]);

  useEffect(() => {
    const root = scrollRef.current;
    if (!root) return;
    const sections = CHAPTERS.map((c) => document.getElementById(c.id)).filter((el): el is HTMLElement => !!el);
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) setActive(entry.target.id);
        }
      },
      { root, rootMargin: "-20% 0px -70% 0px" }
    );
    sections.forEach((section) => observer.observe(section));
    return () => observer.disconnect();
  }, []);

  const onZoom = useCallback((src: string, caption: string) => setZoom({ src, caption }), []);

  return (
    <div className="guide-view" ref={scrollRef}>
      <header className="workspace__head guide-view__head">
        <span className="workspace__eyebrow">{t("guide.eyebrow")}</span>
        <h1>{t("guide.title")}</h1>
      </header>
      <p className="guide-view__intro">{t("guide.introCosmetics")}</p>

      <nav className="guide-view__toc" aria-label={t("guide.toc")}>
        {CHAPTERS.map(({ id, num: chapterNum, title }) => (
          <button
            key={id}
            type="button"
            className={`guide-view__toc-item ${active === id ? "is-active" : ""}`}
            onClick={() => scrollTo(id)}
            aria-current={active === id ? "true" : undefined}
          >
            <small>{chapterNum}</small>
            <span>{t(title)}</span>
          </button>
        ))}
      </nav>

      <article className="guide">
        <section className="guide__chapter" id="guide-ch-install">
          <header className="guide__chapter-head">
            <Download size={18} aria-hidden="true" />
            <span><small>01</small><h3>{t("guide.install.title")}</h3><p>{t("guide.install.body")}</p></span>
          </header>
          <div className="guide__install">
            {INSTALL_STEPS.map((step, index) => (
              <section className="guide__install-step" id={step.id} key={step.id}>
                <span className="guide__install-rail" aria-hidden="true">
                  <span className="guide__install-dot">{num(index + 1)}</span>
                </span>
                <div className="guide__install-card">
                  <Shot image={step.image} caption={t(step.title)} eager={index < 2} onZoom={onZoom} />
                  <div className="guide__copy">
                    <h4>{t(step.title)}</h4>
                    <p>{t(step.body)}</p>
                    <Points items={step.points} />
                  </div>
                </div>
              </section>
            ))}
          </div>
        </section>

        <section className="guide__chapter" id="guide-ch-cosmetics">
          <header className="guide__chapter-head">
            <Crosshair size={18} aria-hidden="true" />
            <span><small>02</small><h3>{t("guide.cosmetics.title")}</h3><p>{t("guide.cosmetics.body")}</p></span>
          </header>
          <div className="guide__steps">
            {COSMETICS_STEPS.map((step, index) => (
              <section className="guide__step" id={step.id} key={step.id}>
                <div className="guide__copy">
                  <span className="guide__number">{num(INSTALL_STEPS.length + index + 1)}</span>
                  <h4>{t(step.title)}</h4>
                  <p>{t(step.body)}</p>
                  <Points items={step.points} />
                </div>
                <Shot image={step.image} caption={t(step.title)} onZoom={onZoom} />
              </section>
            ))}
          </div>
        </section>

        <section className="guide__chapter" id="guide-ch-trouble">
          <header className="guide__chapter-head">
            <LifeBuoy size={18} aria-hidden="true" />
            <span><small>03</small><h3>{t("guide.trouble.title")}</h3><p>{t("guide.trouble.body")}</p></span>
          </header>
          <div className="guide__trouble-grid">
            {TROUBLE_STEPS.map((step, index) => (
              <section className={`guide__trouble guide__trouble--${step.severity}`} id={step.id} key={step.id}>
                <Shot image={step.image} caption={t(step.title)} onZoom={onZoom} />
                <div className="guide__copy">
                  <span className={`guide__number guide__number--${step.severity}`}>{num(INSTALL_STEPS.length + COSMETICS_STEPS.length + index + 1)}</span>
                  <h4>{t(step.title)}</h4>
                  <p>{t(step.body)}</p>
                  <Points items={step.points} />
                </div>
              </section>
            ))}
          </div>
        </section>
      </article>

      <Modal open={!!zoom} onClose={() => setZoom(null)} title={zoom?.caption} width={920}>
        {zoom && <img className="guide-view__zoom" src={zoom.src} alt={zoom.caption} />}
      </Modal>
    </div>
  );
}
