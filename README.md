<div align="center">

# Local Cosmetics

**English** | [简体中文](README.zh-CN.md)

<br/>

<img alt="Platform" src="https://img.shields.io/badge/platform-Windows-0078D4">
<a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-green"></a>

<br/>
<br/>

[Cosmetics](#what-you-configure) · [Launch isolation](#two-ways-to-start-cs2) · [Install](#four-step-first-installation) · [Recovery](#installation-recovery-and-diagnostics) · [Attribution](#upstream-source-and-attribution)

</div>

> [!IMPORTANT]
> Local Cosmetics is a lightweight Windows toolkit for **player cosmetics in local CS2 matches**. It is a fork of the player-cosmetics capability of
> [Local Arena](https://github.com/numakkiyu/Local-Arena) and is independently developed and maintained
>
> It is not a bot-enhancement project, not a public or online skin server, and not an in-game overlay. It never edits your real Steam inventory and never
> touches a VAC-secured server
>
> `docs/PRODUCT-SCOPE.md` is the canonical product boundary. `docs/UPSTREAM.md` records what is carried over from upstream and what is deliberately not

<div align="center">

The current `main` branch targets **1.4.3.3** · package `LocalCosmetics-v1.4.3.3-windows.zip`

</div>

## What this project is for

You build knife, glove, and gun-skin presets for the human player in an external desktop Panel, then start CS2 from that Panel to apply them in an offline
local match. Official normal bots keep working; nothing in this project changes bot behavior.

## Two ways to start CS2

This is the most important behavior of the whole product:

| How you start CS2 | What you get |
| --- | --- |
| **Directly from Steam** | Ordinary, unmodified CS2. No Panel must be open, no managed search path is left in `gameinfo.gi`, and you never have to "switch back to Normal" first |
| **From the Panel** | Local cosmetics mode. The Panel opens a launch transaction, adds the managed `gameinfo.gi` search path for this run only, and launches CS2 with `-insecure` |

`-insecure` means the session is offline: official matchmaking and VAC-secured servers are unavailable, which is exactly where local cosmetics can be applied.
When CS2 exits, the in-game plugin and the Panel restore the clean state. If a previous run was killed instead of closed, the next launch, repair, or restore
finishes the recovery before doing anything else — see `docs/MANUAL-ACCEPTANCE.md` for the in-game checks.

## What you configure

### Knives, gloves, guns

- Every knife in the current catalog, each with its own saved skin preset, so switching back restores that knife's last PaintKit, wear, and pattern seed
- Gloves and gun skins with independent CT and T presets; shared weapons link both sides by default and can be split
- Compatible catalog entries expose StatTrak or Souvenir options where the item supports them
- Wear is clamped to the valid range of the selected PaintKit; Doppler and Gamma Doppler phases stay separate catalog entries rather than seed guesses
- Human-player music kit presets
- Gun presets apply only to weapons the player owns — bought, spawned, or created by this project; a gun picked up off the ground keeps its original appearance

### Live changes while CS2 is running

Saving a preset while a local match is loaded is applied through a config-change watcher with debouncing and bounded retries. There is no permanent tick or
frame polling of your configuration or inventory, and only the regions that actually changed are re-applied.

### Optional quick-knife rotation

The Weapon Presets page can build an ordered quick-knife rotation and shows the matching console bind line, ready to copy. The Panel never writes a bind, a
cfg, or an autoexec: until you paste the line yourself, your key bindings are untouched, and disabling the feature leaves nothing behind.

### Experimental surfaces

**Settings → Experimental Features** adds stickers, validated charm placements, and CT/T agent models for the human player. Charm positions snap to the local
catalog, presets store numeric identifiers rather than localized text, and knives do not accept stickers or charms.

### Simplified Chinese

Simplified Chinese is a first-class language: Panel copy, knife names, glove finishes, and skin names come from local catalog data, and search matches the
displayed name as well as English names and identifiers.

## Before you start

> [!WARNING]
> Close CS2 before installing, repairing, restoring, or changing experimental settings

- Windows only
- Extract the complete ZIP to a normal folder; do not open the Panel from inside the archive
- Keep the Panel executable, `addons`, `LICENSE`, `README.md`, `UPSTREAM.md`, and `plus-payload-manifest.json` in the same folder
- The correct game directory is the one that ends with `Counter-Strike Global Offensive\game\csgo` and directly contains `gameinfo.gi`
- Panel state, logs, backups, and presets live in the portable `.csbip` folder beside the Panel executable

## Four-step first installation

1. **Choose the Panel language.** This only changes the Panel and writes nothing to CS2
2. **Confirm the `game/csgo` directory.** The Panel searches Steam registry data, every `libraryfolders.vdf`, and the CS2 app manifest; one valid installation
   is selected automatically, several require you to pick the installation Steam actually launches
3. **Review the installation plan.** The preview classifies the environment before any file changes: clean CS2, an already managed installation, a legacy
   installation, an original upstream plugin, or a mixed and unknown environment. Mixed or unknown blocks automatic installation
4. **Install.** The transaction journal verifies every copied file and rolls back completed steps if an operation fails. Do not launch CS2, close the Panel,
   or click install again while the transaction is running

## Updating

Local Cosmetics has no automatic update channel and publishes no update manifest: the Panel never downloads another project's package, and no path in the
shipped Panel can overwrite this fork with an upstream build. Updating means closing CS2 and the Panel, extracting a newer package into the same folder, and
keeping the hidden `.csbip` folder. If you move to a different folder, copy the old `.csbip` folder beside the new Panel first so the original backups,
installation records, presets, and logs stay connected.

Upstream synchronization happens through Git review, not through a release channel — see `docs/UPSTREAM.md`.

## Installation, recovery, and diagnostics

**Settings → Installation and Recovery** shows the detected environment, installed version, managed-file health, backup location, and available actions. The
ownership boundary is `plus-payload-manifest.json`: only files this project can prove it owns are replaced or removed.

| Action | Use it when | Result |
| --- | --- | --- |
| Verify installation | You want a fresh health result | Read-only managed-file check |
| Repair installation | Managed files are missing or damaged | Reinstalls only the affected payload files |
| Restore original files | A managed installation must be rolled back | Restores the recorded pre-install backups and removes files this project created |
| Restore pristine CS2 | Every recognized enhanced-plugin file must go | Removes recognized plugin files, keeps unknown third-party files, then asks for Steam file verification |
| Export diagnostics | A problem is reproducible or unclear | Creates a ZIP and opens its folder |

Your saved knife, glove, and gun presets use a preserve-config policy: repair and restore never overwrite them, and a managed restore copies them into
`.csbip/presets` first. Your own `cfg`, `autoexec`, binds, and any third-party file the Panel cannot attribute stay in place.

## Troubleshooting

**Every directory and file state is red** — the Panel has not found a valid `game/csgo` directory. Select the folder that directly contains `gameinfo.gi` and
refresh.

**The environment is mixed or unknown** — export diagnostics before deleting or overwriting anything, then use **Restore pristine CS2**, run Steam file
verification, and start a clean installation.

**Buttons are disabled or installation looks stuck** — the selected CS2 is probably still running or another transaction holds the lock. Close CS2 completely,
wait for `cs2.exe` to disappear, keep the Panel open, and retry after the status refreshes.

**A managed file is reported as modified** — run **Verify installation** first, and only use **Repair installation** when a managed payload file really is
missing or damaged. Cosmetic presets are not corruption.

**Cosmetics do not appear** — the match must have been started from the Panel; a CS2 launched directly from Steam is intentionally unmodified. Confirm the
current CT or T presets are enabled, then verify and repair before using any recovery action.

**CS2 freezes or crashes** — reopen the Panel and use **Export diagnostics** right away, and include the map, game type, team, and exact reproduction steps.
A hard kill of `cs2.exe` leaves the launch transaction open on purpose; the next Panel action recovers it and the game self-heals the search path on load.

## What is deliberately not included

Enhanced bot AI and difficulty presets, bot aiming or buying systems, grenade systems, bot profiles and team injection, bot randomizers and disguises, ray
tracing, match coordination, ratings, telemetry, statistics, demos, team lineups, the in-game overlay surfaces, and the upstream online update channel. The
packaging gate asserts that none of these components reach a release archive.

## Legacy naming

The product is Local Cosmetics, while the Panel executable is still named `cs2-bot-improver-plus-panel.exe`, the window brand still reads **Local Arena**, and
state lives in `.csbip`. Those identifiers are kept on purpose for now so existing installations, backups, and presets remain compatible.

## Upstream source and attribution

- [numakkiyu/Local-Arena](https://github.com/numakkiyu/Local-Arena) — main technical base for the Panel and the player-cosmetics plugin, AGPL-3.0
- [ed0ard/CS2-Bot-Improver](https://github.com/ed0ard/CS2-Bot-Improver) — reference upstream for CS2 and CounterStrikeSharp compatibility work and an
  attribution target; its enhanced-bot runtime is not shipped here
- [Metamod:Source](https://github.com/alliedmodders/metamod-source) and [CounterStrikeSharp](https://github.com/roflmuffin/CounterStrikeSharp) — pinned runtime
  dependencies, verified by SHA-256 during packaging
- Cosmetic data: [Nereziel/cs2-WeaponPaints](https://github.com/Nereziel/cs2-WeaponPaints) (GPL-3.0),
  [ByMykel/CSGO-API](https://github.com/ByMykel/CSGO-API) (MIT),
  [SteamTracking/GameTracking-CS2](https://github.com/SteamTracking/GameTracking-CS2) (no published license, factual schema reference only)

Pinned versions, hashes, and the full not-carried-over list live in `docs/UPSTREAM.md`; the same information is rendered inside the Panel under
**Settings → About**.

Local Cosmetics is not affiliated with, endorsed by, or supported by the upstream projects. Report issues in this repository only.

## License

[AGPL-3.0](LICENSE) — the applicable upstream copyright, provenance, and attribution notices are preserved.
