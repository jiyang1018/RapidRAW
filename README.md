# RapidRAW — external control fork

This is [RapidRAW](https://github.com/CyberTimon/RapidRAW) (upstream, by Timon Käch) plus
one addition: a local **external control API** so hardware controllers can drive the editor.
Everything else — features, docs, downloads for daily use — is upstream's; read the
[upstream README](https://github.com/CyberTimon/RapidRAW#readme).

The fork exists for the
**[RapidRAW plugin for Logi Options+ / MX Creative Console](https://github.com/jiyang1018/rapidraw-logi-plugin)**,
which turns the console's dials into live develop sliders. You need this build of RapidRAW
for that plugin to work.

## What is added

Branch `external-control`, on top of upstream v1.6.3:

* A TCP server on `127.0.0.1:47820` (loopback only, newline-delimited JSON). Clients can
  set, nudge and reset every develop slider live, fire the editor's named actions
  (undo/redo, next/previous image, rating, colour labels, zoom, panel toggles, …) and
  receive a throttled state feed for dial displays. Controller edits go through the same
  path as a slider drag: low-res preview while the dial turns, full render and auto-save
  when it stops, coalesced undo steps.
* Settings `enableExternalControl` (default `true`) and `externalControlPort` (default
  `47820`), plus the `RAPIDRAW_CONTROL_PORT` environment override. No settings UI yet.
* Nothing else changes: rendering, export, file management and defaults are upstream's,
  and no new dependencies.

Docs: [`docs/EXTERNAL_CONTROL_API.md`](docs/EXTERNAL_CONTROL_API.md) (protocol),
[`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md), [`docs/HANDOFF.md`](docs/HANDOFF.md)
(where the code lives, how to extend it).

## Get it

Builds are on the [Releases](https://github.com/jiyang1018/RapidRAW/releases) page,
versioned `<upstream version>-ctl.<n>` (e.g. `1.6.3-ctl.1`). They install in place of
upstream RapidRAW (same app id and settings), so switching back is just installing
upstream again. The app log (Settings → Data → View Application Logs) says
`External control: listening on 127.0.0.1:47820` when the API is up.

## Build it

Same toolchain as upstream (Rust ≥ 1.98, Node ≥ 22). Windows:

```
.\tools\rebuild.ps1            # release build + NSIS installer
.\tools\rebuild.ps1 -Mode dev  # hot-reload dev build
```

macOS / Linux: `bash tools/rebuild.sh` (same modes). Both scripts check the toolchain
and print where the outputs land.

## License

AGPL-3.0, as upstream. The changes in this fork are offered to upstream under the same
license.
