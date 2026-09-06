# Release notes — RapidRAW external control fork

Versions track upstream RapidRAW with a `-ctl.N` suffix for this fork's changes.

## 1.6.3-ctl.1 — 2026-09-05

Base: upstream `ec50408e` (v1.6.3).

For the Logi MX Creative Console plugin that uses this API, see
https://github.com/jiyang1018/rapidraw-logi-plugin.

Installs in place of upstream RapidRAW 1.6.3 (same app id and settings); installing upstream
again switches back.

### Added

* **External control server** (`127.0.0.1:47820`, newline-delimited JSON). Hardware
  controllers can set, nudge and reset every develop slider live, fire the named editor
  actions (undo/redo, next/previous image, rating, color labels, zoom, panel toggles, …)
  and receive a throttled state feed for dial displays. Protocol: `docs/EXTERNAL_CONTROL_API.md`.
* Settings `enableExternalControl` (default `true`) and `externalControlPort` (default
  `47820`), plus the `RAPIDRAW_CONTROL_PORT` environment override. No settings UI yet.
* Tauri commands `external_control_publish` and `external_control_status`.
* `tools/rebuild.ps1` / `tools/rebuild.sh` — Windows and macOS build/dev/check scripts with toolchain checks.

### Behaviour notes

* Controller edits go through the same path as slider drags: coalesced undo steps, live
  low-res preview while a dial turns, full render and auto-save ~200 ms after it stops,
  multi-select auto-sync honoured.
* Loopback only; non-loopback peers are refused. No authentication.
* A port clash is logged and otherwise ignored — the app starts normally.

### Not changed

Rendering, export, file management, upstream defaults. Zero new dependencies.
