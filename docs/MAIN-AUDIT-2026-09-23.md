# Personal main audit — 2026-09-23

Baseline: `Whatnamed/Local-Arena` remote main and local main both
`e21c7db140ff16a6e4018636b117db9e83887d0d`; initially clean.
Only `E:\CS2MOD\main` was used. No experimental implementation or build output
was consulted. Full Bot / Match / Stats / original UI remain in scope.

## Panel hang: confirmed live cause

PID 30736 was running main's staged `LocalArena.exe`. HWND 988620 belonged to
UI TID 33412 and was hung. HWND 203708, class `Ghost`, belonged to Windows
PID 1876 and displayed `Local Arena (未响应)`. The single-instance and Tao event
windows on the same UI thread were also hung. Associated WebView2 processes
were still alive; no running CS2 was found during capture.

The dump and matching PDB resolve a reentrant UI-thread stack:
`Tao public_window_callback -> set_skip_taskbar -> explorerframe -> SendMessageW
-> public_window_callback -> parking_lot::RawMutex::lock_slow -> WaitOnAddress`.
Disassembly confirms the outer call retains the same window-state mutex while
the nested call waits for it. The installed Tao 0.35.3 `TaskbarCreated` handler
has that exact lock scope. This is not an off-screen-window/focus failure.

Upstream fix: https://github.com/tauri-apps/tao/pull/1264,
commit `f7f8173dc85287b2a18aceb9c47533097b8c123f`. Only that functional change
is backported to a local Tao 0.35.3 dependency; unrelated upstream window/input
changes and dependency version upgrades are excluded.

Evidence is retained locally in `temp/panel-hang-20260923/`: dump, original
exe/PDB, HWND/PID/TID inventory, all thread stacks and last Panel log. The hung
Panel was stopped only after capture. These potentially private artifacts are
ignored by Git. The original staging `.csbip` installation backups are retained.

The snapshot command already ran on `spawn_blocking`; frontend polling already
prevented overlap and paused while hidden. They are not the cause shown in this
dump. Snapshot recovery writes were removed: observation must not race a mode
writer or roll back installation state as CS2 exits. Explicit install/repair/
restore/mode operations retain their recovery paths. Match preparation is also
off the UI thread.

`scripts/test-panel-taskbar.ps1` uses a fake installation and isolated state,
starts only Panel, sends 12 registered taskbar messages and probes `WM_NULL`.
Both the archived old executable and fixed executable remained responsive in
this simplified test. It is a smoke test, not a reproduction of Shell's actual
nested callback, nor proof that the CS2-exit scenario passed.

## Knife replacement and retakes

Confirmed defects: successful replacement destroyed the old entity without
inventory detachment; failed detachment/equip had no real rollback; callbacks
kept raw pointers across frames, and cancellation could retain orphaned knives.
These are plausible causes of client stale-handle/slot failures. No CS2 client
dump was available to prove which defect caused the reported client error.

Replacement now keeps serial-aware handles for player, Pawn and weapons;
creates and prepares a base knife; requests slot3; verifies active identity and
inventory membership; detaches old via `RemovePlayerItem`; and only destroys an
entity after both MyWeapons and ActiveWeapon no longer reference it. Native
detach failure prevents destruction. Equip retries are bounded.

After a detached-old failure, recovery creates a new base knife from the saved
original definition/preset, verifies it through the same pipeline, then retires
the failed candidate and detached original. The last owned candidate is retained
until recovery creation succeeds. Recovery failure is logged and never reported
as successful rollback. If the engine rejects all creation/equip attempts,
recovery cannot be guaranteed; this remains an explicit in-game acceptance case.
No new native signature or inventory-vector writes were introduced.

The GiveNamedItem phase resolver only covers calls through that hook. Native
retakes are not implemented in this repository, so universal coverage cannot be
asserted from source. A knife-only OnEntitySpawned listener now resolves serial
identity and ownership with bounded delayed attempts, then schedules the existing
generation-safe Knife phase. Plugin-created replacements are excluded. There is
no new Tick/Frame inventory scan. In-place resets without entity recreation
still require runtime evidence. Existing gun pickup semantics are preserved.

Installed logs corroborate `enabled=false` in one game launch and a later
`default knife: the fresh knife could not be equipped`. They also show an
unrelated OfflineMatchTelemetry duplicate-key-0 exception; it was not silently
attributed to the knife crash or expanded into a Stats rewrite.

## Mode and configuration ownership

The current upstream README states Preview = cosmetics with normal bots,
Enhanced bots = full bot systems plus cosmetics:
https://github.com/numakkiyu/Local-Arena#choose-the-correct-mode

Previously Bots restored historical booleans (often false); Match bypassed
cosmetic coordination. Runtime enabled is now mode-derived: Online false,
Preview/Bots true. Stale legacy snapshots are cleared, per-team presets retained.
Match coordinates guidelines and cosmetics, persists Bots on successful launch,
and restores prior config/preset bytes on preparation failure.

Restore previously reapplied a pre-installer JSON snapshot, overwriting fields
just restored from the user's original. Restoration now reads the post-installer
file and owns only the guideline property. Malformed JSON fails closed. Generated
core files with subsequent user data are preserved. Explicit user changes to the
property are not overwritten. Pristine restore does not resurrect a removed
runtime config. New package manifests mark core.json as preserve-config, so
install/repair do not replace unrelated user fields in the first place.

## Picker media and search

The old Steam Akamai economy endpoint failed to connect on this host; identical
image identifiers work on Steam Fastly. This is direct endpoint evidence, not a
claim that every prior blank image shared one cause. Gloves/music now use 192
bundled PNG thumbnails (12,787,717 bytes); source URLs, sizes and hashes are recorded.
The build verifies every local file. Other image catalogs remain remote with
Fastly endpoint normalization and visible fallback; no all-weapon offline claim.
Chinese glove names remain 91/91 and bilingual music names 101/101. Glove search
tests exercise Chinese/English names, models, PaintKit and defindex for every row.

## Verification boundary

Rust unit/file fixtures include all nine mode transitions, legacy false flags,
installer + core-owner roundtrips for old/new manifest policies, malformed input
and modified generated files. Plugin tests cover repeated detach/destroy ordering
and failed detach/active-slot retention, alongside the existing generation,
phase-selection and preset tests. Native CS2 entity/animation behavior is manual.

Build/package outputs stay under main. Package staging uses `stage-build` and
refuses to remove any staging tree containing `.csbip`; the user's old `stage`
run and backups survive. No GitHub Release/tag is created. See
`MANUAL-ACCEPTANCE.md` for unverified game scenarios.

## Delivery results

- Full Windows build passed (`temp/audit-delivery-build.log`): frontend checks/
  TypeScript/Vite, all plugin builds, MatchCore and PlayerKnifeCustomizer tests.
- Rust: 128 passed, 0 failed, 1 ignored. Existing unused updater-code warnings
  remain; they were not expanded into unrelated cleanup.
- Workspace and package layout verification passed; no Bot/Match/Stats removal.
- Final executable passed the 12-message native taskbar smoke test in an isolated
  fake installation. CS2 was never started.
- ZIP audit: 719 entries; required runtime and license files present; no `.csbip`,
  dump, update signature, `latest.json` or split archives. Panel and knife DLL
  hashes match this worktree's current builds. core.json uses preserve-config.
- Vendor comparison: only the intended Windows event-loop source differs from
  the cached Tao 0.35.3 source (plus the local provenance note). Cargo.lock has
  only the source/checksum removal for that path dependency; no version churn.
- Artifact: `artifacts/main-personal/audit-20260923/LocalArena-main-personal-v1.4.3.3-windows.zip`
  (103,072,499 bytes).
- SHA256: `7c7334a8bc9b71be1271c0dd248248a8c4e158ee77d630aba14c84a363b46d40`.
- Source changes are local and uncommitted. Branch/HEAD remain `main` /
  `e21c7db140ff16a6e4018636b117db9e83887d0d`; no push, Release or tag was made.
  The current request authorized review and implementation, not remote publication.
