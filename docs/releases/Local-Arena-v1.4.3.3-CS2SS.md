# Local Arena 1.4.3.3 - CS2SS integration

Local Arena 1.4.3.3 integrates the CS2SS telemetry and statistics work from
PR #20. The contribution was merged with a normal merge commit so the original
commit authorship remains visible in the repository history.

## Contribution history

The following commits remain unchanged and attributed to Magichear:

- `5f65469` - CS2SS telemetry integration and global match history panel
- `79fc40b` - corrected the plugin deployment path
- `22efbde` - handled in-progress, abandoned, and empty-player matches
- `3b6796d` - added the deathmatch global statistics dashboard
- `eb07b25` - merged the deathmatch feature branch
- `4f3ab77` - added missing deathmatch test schema columns

Maintainer compatibility and release changes are recorded separately after the
merge. This preserves the contributor's authorship while keeping release policy,
packaging, and project-specific fixes under the maintainer's identity.

## Local Arena adaptations

- Version surfaces target display version `1.4.3.3` and package version
  `1.4.3+3`.
- OfflineMatchTelemetry is built by the canonical project build and packaged
  from its eight-file staged deployment allowlist.
- SteamID64 configuration is validated in both the Panel and Rust backend and
  is written atomically.
- Deathmatch database failures return structured errors instead of panicking or
  silently dropping rows.
- Statistics views use the project localization system and provide explicit
  competitive, deathmatch, loading, error, and empty states.
- Statistics controls, tables, and setup UI support the Panel's narrow window
  sizes without changing the existing application navigation.

## Release boundary

This branch prepares the source for Local Arena 1.4.3.3. Packaging, tagging,
pushing, and publishing remain separate release operations.
