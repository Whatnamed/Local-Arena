# Player Cosmetics

## Supported Presets

- Knife type and paint kit
- Glove type and paint kit
- Gun paint kits for catalogued purchasable weapons
- Wear and pattern seed
- Name tag
- StatTrak enablement and initial/current count where supported
- Souvenir state where supported
- Music kit

The Panel filters choices by weapon defindex and catalog compatibility. Doppler and Gamma Doppler variants remain
separate paint-kit entries, so phase-specific variants are not collapsed into a generic label.

## Runtime Model

The Panel writes JSON under the installed `PlayerKnifeCustomizer` plugin directory. The assembly/folder name is kept
for copy-over upgrade compatibility; the module is displayed as `PlayerCosmetics` in CounterStrikeSharp.

The plugin applies presets at bounded game events:

- human player spawn;
- `GiveNamedItem` completion for purchases and grants;
- item pickup according to the original Local Arena semantics;
- dropped knife entity creation;
- round MVP for the configured music kit.

For a picked-up Bot / ground weapon, a preset for the current team and weapon defindex may be applied. If no matching
preset exists, the entity is left unchanged. This project does not require a separate foreign-weapon provenance
subsystem. There is no periodic held-weapon listener and no always-on-top in-game overlay.

## Language Independence

Configuration stores defindexes, paint kits, floats, integers, booleans, and name-tag text. Localized names are only
used by the Panel search and display layer. Switching Steam accounts or Panel languages does not invalidate a preset;
the same local practice installation applies it to eligible human players.

## Mode Compatibility

Local Arena's existing Local / Preview / Bots / Online mode management remains the source of truth for launch and
runtime behavior. Cosmetic configuration is kept across mode changes, and the application does not use the official
upstream release updater to overwrite this personal fork.

Do not load unsigned server modifications in a VAC-secured session. Actual mode, model, animation, and online behavior
must be checked through `docs/MANUAL-ACCEPTANCE.md` rather than inferred from Panel text alone.
