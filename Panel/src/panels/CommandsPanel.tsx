import { useMemo, useRef, useState } from "react";
import {
  Check,
  Copy,
  Search,
  Terminal,
  Wifi,
  type LucideIcon,
} from "lucide-react";
import SubPage from "../components/SubPage";
import { useToast } from "../components/Toast";
import { useT, type I18nKey } from "../i18n";
import { COMMANDS_TXT } from "../data/commands";
import { writeClipboard } from "../lib/platform";
import "./CommandsPanel.css";

type TabId = "common" | "multiplayer";
type SectionId = "GAME MODE" | "CONNECTION";

const SECTION_META: Record<SectionId, { title: I18nKey; description: I18nKey; icon: LucideIcon }> = {
  "GAME MODE": {
    title: "cmd.h.gameMode",
    description: "cmd.desc.gameMode",
    icon: Terminal,
  },
  CONNECTION: {
    title: "cmd.h.connection",
    description: "cmd.desc.connection",
    icon: Wifi,
  },
};

const TABS: { id: TabId; label: I18nKey; icon: LucideIcon }[] = [
  { id: "common", label: "cmd.tab.common", icon: Terminal },
  { id: "multiplayer", label: "cmd.tab.multiplayer", icon: Wifi },
];

const TAB_SECTIONS: Record<TabId, SectionId[]> = {
  common: ["GAME MODE", "CONNECTION"],
  multiplayer: [],
};

function parseSections(text: string): Record<SectionId, string[]> {
  const result: Record<SectionId, string[]> = {
    "GAME MODE": [],
    CONNECTION: [],
  };
  const headers = new Set<string>(Object.keys(SECTION_META));
  let current: SectionId | null = null;

  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    // Everything from "BOT AIM STYLE" onwards is Bot-only content.
    if (line === "BOT AIM STYLE") break;
    if (headers.has(line)) {
      current = line as SectionId;
      continue;
    }
    if (current && line) result[current].push(line);
  }
  return result;
}

const COMMAND_SECTIONS = parseSections(COMMANDS_TXT);

const COMMAND_DESCRIPTION_KEYS: Record<string, I18nKey> = {
  scouts_on: "cmd.detail.scoutsOn",
  scouts_off: "cmd.detail.scoutsOff",
  status: "cmd.detail.status",
};

function commandDescription(command: string, t: ReturnType<typeof useT>): string {
  const directKey = COMMAND_DESCRIPTION_KEYS[command];
  return directKey ? t(directKey) : t("cmd.detail.fallback");
}

function CommandCard({
  command,
  description,
  icon: IconComponent,
  copied,
  onCopy,
}: {
  command: string;
  description: string;
  icon: LucideIcon;
  copied: boolean;
  onCopy: () => void;
}) {
  return (
    <button className={`cmd-card ${copied ? "is-copied" : ""}`} onClick={onCopy}>
      <span className="cmd-card__icon" aria-hidden="true">
        <IconComponent size={17} strokeWidth={1.9} />
      </span>
      <span className="cmd-card__body">
        <span className="cmd-card__description">{description}</span>
        <code>{command}</code>
      </span>
      <span className="cmd-card__copy" aria-hidden="true">
        {copied ? <Check size={16} /> : <Copy size={16} />}
      </span>
    </button>
  );
}

export default function CommandsPanel({ onBack }: { onBack?: () => void }) {
  const t = useT();
  const toast = useToast();
  const [tab, setTab] = useState<TabId>("common");
  const [query, setQuery] = useState("");
  const [copiedId, setCopiedId] = useState("");
  const copiedTimer = useRef<number | null>(null);
  const normalizedQuery = useMemo(() => query.trim().toLowerCase(), [query]);

  const copy = async (id: string, value: string) => {
    try {
      await writeClipboard(value);
      setCopiedId(id);
      if (copiedTimer.current) window.clearTimeout(copiedTimer.current);
      copiedTimer.current = window.setTimeout(() => setCopiedId(""), 900);
      toast.show(t("common.copied"), "green");
    } catch {
      toast.show(t("common.copyFailed"), "red");
    }
  };

  const renderCommandSections = (sectionIds: SectionId[]) => {
    const blocks = sectionIds
      .map((sectionId) => {
        const meta = SECTION_META[sectionId];
        const commands = COMMAND_SECTIONS[sectionId].filter((command) =>
          `${command} ${commandDescription(command, t)} ${t(meta.title)} ${t(meta.description)}`
            .toLowerCase()
            .includes(normalizedQuery)
        );
        return { sectionId, meta, commands };
      })
      .filter((block) => block.commands.length > 0);

    if (!blocks.length) return <div className="cmd__empty">{t("cmd.noResults")}</div>;

    return blocks.map(({ sectionId, meta, commands }) => (
      <section className="cmd-group" key={sectionId}>
        <div className="cmd-group__heading">
          <span className="cmd-group__heading-icon">
            <meta.icon size={16} strokeWidth={1.9} />
          </span>
          <span>
            <strong>{t(meta.title)}</strong>
            <small>{t(meta.description)}</small>
          </span>
          <span className="cmd-group__count">{commands.length}</span>
        </div>
        <div className="cmd-grid">
          {commands.map((command) => {
            const id = `${sectionId}:${command}`;
            return (
              <CommandCard
                key={command}
                command={command}
                description={commandDescription(command, t)}
                icon={meta.icon}
                copied={copiedId === id}
                onCopy={() => copy(id, command)}
              />
            );
          })}
        </div>
      </section>
    ));
  };

  const multiplayerSteps = [
    {
      id: "status",
      number: "01",
      title: t("cmd.multi.statusTitle"),
      description: t("cmd.multi.statusDesc"),
      command: "status",
    },
    {
      id: "steamid",
      number: "02",
      title: t("cmd.multi.steamIdTitle"),
      description: t("cmd.multi.steamIdDesc"),
      command: "steamid",
    },
    {
      id: "connect",
      number: "03",
      title: t("cmd.multi.connectTitle"),
      description: t("cmd.multi.connectDesc"),
      command: "connect <steamid>",
    },
  ].filter((step) =>
    `${step.title} ${step.description} ${step.command}`
      .toLowerCase()
      .includes(normalizedQuery)
  );

  return (
    <SubPage title={t("cmd.title")} onBack={onBack}>
      <div className="cmd__toolbar">
        <div className="cmd__tabs" role="tablist" aria-label={t("cmd.categories")}>
          {TABS.map(({ id, label, icon: IconComponent }) => (
            <button
              key={id}
              role="tab"
              aria-selected={tab === id}
              className={tab === id ? "is-active" : ""}
              onClick={() => setTab(id)}
            >
              <IconComponent size={15} strokeWidth={2} />
              <span>{t(label)}</span>
            </button>
          ))}
        </div>
        <label className="cmd__search-wrap">
          <Search size={16} aria-hidden="true" />
          <input
            className="cmd__search"
            type="search"
            value={query}
            placeholder={t("cmd.searchCommands")}
            onChange={(event) => setQuery(event.target.value)}
          />
        </label>
      </div>

      <div className="cmd__content selectable">
        {tab === "common" && renderCommandSections(TAB_SECTIONS.common)}

        {tab === "multiplayer" && (
          <section className="multiplayer-guide">
            <div className="cmd__section-intro">
              <span>
                <strong>{t("cmd.multi.title")}</strong>
                <small>{t("cmd.multi.subtitle")}</small>
              </span>
            </div>
            {multiplayerSteps.length ? (
              <div className="multiplayer-guide__steps">
                {multiplayerSteps.map((step) => {
                  const id = `multi:${step.id}`;
                  return (
                    <button
                      key={step.id}
                      className={`multiplayer-step ${copiedId === id ? "is-copied" : ""}`}
                      onClick={() => copy(id, step.command)}
                    >
                      <span className="multiplayer-step__number">{step.number}</span>
                      <span className="multiplayer-step__body">
                        <strong>{step.title}</strong>
                        <small>{step.description}</small>
                        <code>{step.command}</code>
                      </span>
                      <span className="multiplayer-step__copy" aria-hidden="true">
                        {copiedId === id ? <Check size={17} /> : <Copy size={17} />}
                      </span>
                    </button>
                  );
                })}
              </div>
            ) : (
              <div className="cmd__empty">{t("cmd.noResults")}</div>
            )}
            <div className="multiplayer-guide__note">
              <Terminal size={17} />
              <span>{t("cmd.multi.note")}</span>
            </div>
          </section>
        )}
      </div>
    </SubPage>
  );
}
