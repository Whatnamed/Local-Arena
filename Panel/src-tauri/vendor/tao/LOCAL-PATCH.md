# Local backport

Source: crates.io `tao` 0.35.3 (the version previously in Cargo.lock).
Original Apache-2.0 license and copyright notices are retained.

Only functional change: release `window_state` before `set_skip_taskbar` in
the Windows `TaskbarCreated` handler. Backported from upstream PR
https://github.com/tauri-apps/tao/pull/1264
(f7f8173dc85287b2a18aceb9c47533097b8c123f).

The Shell can synchronously send another window message inside AddTab/DeleteTab.
Holding the non-reentrant mutex deadlocks that window's message thread.
Confirmed in the personal main Panel hang dump on 2026-09-23.

This local dependency avoids importing the unrelated window/input changes in
newer Tao versions. See scripts/test-panel-taskbar.ps1 for the native message probe.
