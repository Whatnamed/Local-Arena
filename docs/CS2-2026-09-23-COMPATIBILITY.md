# CS2 2026-09-23 Windows runtime compatibility

This patch targets the installed CS2 build with Steam appmanifest build ID `25472966`.
It changes only the native compatibility layer. Game behavior remains subject to
[`MANUAL-ACCEPTANCE.md`](MANUAL-ACCEPTANCE.md).

## Native sources and ownership

| Binding | Source | Local use |
| --- | --- | --- |
| `CAttributeList::SetOrAddAttributeValueByName` | [Inventory Simulator 3.1.2 / `982a859c`](https://github.com/ianlucas/cs2-css-inventory-simulator/blob/982a859cb34e5c3af839adb6c1ab0ad5b82a890f/gamedata/inventory-simulator.json) | Human and Bot econ attributes; both use its `nint, string, float -> int` binding. |
| `CEconItemView::CEconItemView` | Same Inventory Simulator gamedata and [native declaration](https://github.com/ianlucas/cs2-css-inventory-simulator/blob/982a859cb34e5c3af839adb6c1ab0ad5b82a890f/source/InventorySimulator/Natives/Natives.CEconItemView.cs) | BotRandomizer's existing persistent item-view allocation and `GiveNamedItem` hook. Its Windows signature did not change. |
| `CCSPlayer_ItemServices::SetWearables` | Same Inventory Simulator gamedata and [native declaration](https://github.com/ianlucas/cs2-css-inventory-simulator/blob/982a859cb34e5c3af839adb6c1ab0ad5b82a890f/source/InventorySimulator/Natives/Natives.CCSPlayer_ItemServices.cs) | Initialize the existing direct glove path before writing `m_EconGloves`; unavailable gloves do not disable guns or agents. |
| `CBaseModelEntity::SetModel` | [source2toolkit `3644f362` gamedata](https://github.com/SlynxCZ/source2toolkit/blob/3644f362b03f1f2219eb990cb5959b3ee1958362/configs/addons/source2toolkit/gamedata/gamedata.json) | Human and Bot direct custom agent models. The CounterStrikeSharp 1.0.371 and current-main signatures have a stale Windows tail. The function prototype remains `void(entity, model path)`. |
| BotHider's existing `UTIL_Remove`, quota, team join, human team restriction and entity packing hooks; `m_Clients` offset | [BotHider `main@941e642b` gamedata](https://github.com/XBribo/CS2-Bot-Hider/blob/941e642b35f649b4cf08005c2049e57519cfaefa/configs/addons/BotHider/gamedata.json) | Windows entries actually read by the pinned v0.3.3 binary. The current package keeps its v0.3.3 native and managed protocol. |

`CosmeticNativeSignatures.cs` links into both cosmetic plugins. Each binding resolves
independently and reports its own unavailable capability. `SetModelFromClass` and
`SetModelFromLoadout` in Inventory Simulator refresh models from an intercepted
inventory loadout. Local Arena applies selected model paths directly, so those
inventory operations are not copied. Inventory Simulator's `CEconItemView::operator=`,
schema lookup, and inventory update functions are also not called by Local Arena.

BotHider's current `main` native code and managed plugin are not a drop-in upgrade
for Local Arena's v0.3.3 managed plugin: its identity-mode command differs from
the v0.3.3 disguise command. The v0.3.3 source only installs the five hook targets
listed above, plus uses the `m_Clients` offset; therefore the package overlays only
those current Windows gamedata values. It retains v0.3.3's other offsets and managed
shared-memory layout. The package script verifies the v0.3.3 DLL SHA-256 from
`scripts/dependencies.json`, then overlays and verifies the repository gamedata.

## Static Windows evidence

`python scripts/verify-cs2-signatures.py <CS2 game directory>` scans installed
`server.dll` and `engine2.dll` without launching CS2. For local Steam build ID
`25472966`, all five BotHider hook patterns and all four cosmetic patterns matched
exactly once. The old CounterStrikeSharp `SetModel` pattern matched zero times.
Signature matches prove address uniqueness in that file version; they cannot prove
hook behavior, model visibility, ownership, or inventory replication in a running game.

CounterStrikeSharp stays at `v1.0.371`, Bot Improver at `v1.4.3`, and BotHider at
`v0.3.3`. No BotController ABI, CSS, or Bot Improver migration is part of this patch.
