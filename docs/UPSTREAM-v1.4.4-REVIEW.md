# Upstream v1.4.4 compatibility review

Review date: 2026-09-23

Local Arena source baseline: `ed0ard/CS2-Bot-Improver` `v1.4.3` / `d1d83982db88fbdb686b2bf13aa8c6f9d65a4604`
Reviewed upstream target: `v1.4.4` / `7491e175f83e612dbb1c742c2241d454ed4c15ad`

## Release changes

The `v1.4.4` release was published on 2026-09-04 and is 80 commits ahead of the pinned source. Its release notes include signature/offset changes, a BotAI stability update, performance work, bot behavior changes, new BotVision support, roster/profile updates, and Linux support.

- **BotAI:** changes the game-state offset by platform (`0x5100` on Linux; the existing Windows value remains `0x5128`). Linux cave patch pairs now resolve sites before writing and calculate cross-function `rel32` displacements at runtime. `WindowsPatchDefinitions` is unchanged; the updated cave signatures are Linux-specific.
- **BotHider:** the managed plugin moves from module version `0.3.3` to `0.4.0`, adding managed-bot vote acceptance and identity-mode controls. Its new gamedata entries support those behaviors and Linux. This is not a drop-in refresh of the currently pinned native runtime.
- **BotController:** its managed wrapper raises the native ABI expectation from 14 to 17 and adds user-command injection plus extended replay command/movement data. Replacing only the native DLL or only the managed sources would mismatch the current ABI 14 pair.
- **BotState:** moves from module version `1.8.2` to `1.9.4` and contains substantial fake-defuse, visibility, and flash behavior changes. The isolated Deathmatch elimination guard is useful, but current `BotState.cs` also calls `IBotControllerApi.InjectUsercmd`, which the Local Arena ABI 14 interface does not define. A targeted build confirmed `CS1061`; integrating this source safely requires the related BotController ABI work.
- **BotRandomizer and NadeSystem:** both have large rewrites that combine performance work with new bot/cosmetic/grenade behavior. They overlap Local Arena's current modules and need a separate behavior-level review before selective porting.
- **Other changes:** adds BotVision and changes bot roster/profile data. These are feature/data updates rather than a Windows compatibility fix for the current package.
- **CounterStrikeSharp API references:** the release does not use one uniform API pin. Changed project files move from `1.0.365`/`1.0.368`/`1.0.371` to a mix of `1.0.371` and `1.0.373`.

## Integration decision

No v1.4.4 plugin implementation or release payload was copied into `main`. The current v1.4.3 package base stays in place so the shipped BotController native DLL remains paired with the ABI 14 managed wrapper. The Deathmatch guard was not left as an unbuilt source-only patch. BotAI's changed offsets and patch definitions are Linux-specific, while the current Windows BotHider definitions do not gain a compatible post-update signature from this release.

The build-script change in this task is independent of the upstream source review. It preserves the existing Local Arena build list and package inputs.

## 2026-09-23 CS2 compatibility evidence

The CS2 update is build `1.41.8.2` / `2000913` and says it updates engine code to the latest Source 2 version ([Steam announcement](https://steamcommunity.com/games/CSGO/announcements/detail/674006995886407686)). It postdates upstream v1.4.4.

- CounterStrikeSharp's latest tagged release at review time is `v1.0.374` (2026-09-07), whose schema notes name `1.41.7.7`. Its open [PR #1432](https://github.com/roflmuffin/CounterStrikeSharp/pull/1432) updates Linux gamedata for `1.41.8.2` and explicitly says Windows was untouched. This does not establish that the Local Arena Windows runtime is compatible or incompatible.
- [BotHider issue #35](https://github.com/XBribo/CS2-Bot-Hider/issues/35) reports on a Windows dedicated server that names, agents, weapon skins, and SteamIDs stopped working after the update; the attached hook report has several unresolved functions. The issue does not identify the exact BotHider package version. Latest release `v0.4.4` (2026-09-06) predates the update and does not claim a fix.
- CounterStrikeSharp's [Metamod submodule bump PR #1428](https://github.com/roflmuffin/CounterStrikeSharp/pull/1428) references Metamod source commit `fa6f80e` from 2026-09-16, but was closed as no longer needed and is not a tested Windows runtime release combination for this CS2 update.
- RayTrace `v1.0.16` remains the latest tagged release found; no post-update Windows compatibility evidence was found for it or for the pinned BotHider `v0.3.3`.

Therefore the runtime pins remain CounterStrikeSharp `1.0.371`, Metamod `2.0.0-git1406`, RayTrace `1.0.16`, and BotHider `0.3.3`. They are unchanged because no stable, evidenced Windows-compatible replacement set was available at review time. Their actual CS2 behavior remains subject to the targeted Windows checks in [`MANUAL-ACCEPTANCE.md`](MANUAL-ACCEPTANCE.md).
