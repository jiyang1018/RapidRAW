# Handoff — RapidRAW external control fork

Fork of [CyberTimon/RapidRAW](https://github.com/CyberTimon/RapidRAW) at `ec50408e`
(v1.6.3, 2026-09-03) with one addition: a loopback control server so a hardware console can
drive the develop sliders live. Motivation and the wire protocol are in
[`EXTERNAL_CONTROL_API.md`](EXTERNAL_CONTROL_API.md); the version log is in
[`RELEASE_NOTES.md`](RELEASE_NOTES.md).

## Why this exists

Adobe Camera Raw has no controller API and never will (see the Logi MX Console project
notes); the only live route there is synthetic keystrokes, which Loupedeck shipped and then
abandoned. RapidRAW is open source, keeps all adjustment state in one place, and already
has a "slider is being dragged → fast preview → full render + save on release" pipeline.
Hooking a controller into that pipeline is a small, well-contained change — and an upstream
feature request got no response, so it is done here.

## What changed

| file                                       | change                                                                                                                                                               |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src-tauri/src/external_control.rs`        | **new.** Tokio TCP server on `127.0.0.1:<port>`, newline-delimited JSON. Inbound lines → `external-control-command` Tauri event. `external_control_publish` command broadcasts frontend messages to all clients; the last `state` is cached and replayed to new clients. `external_control_status` command for a future settings UI. |
| `src-tauri/src/lib.rs`                     | `mod external_control;` · `.manage(ExternalControlState)` · both commands registered · server started in `setup()` after the preview/analytics workers, gated by settings. |
| `src-tauri/src/app_settings.rs`            | `enable_external_control: Option<bool>` (default **true**), `external_control_port: Option<u16>` (default 47820). Both `#[serde(default)]`, so old settings files load unchanged. |
| `src/utils/externalControl.ts`             | **new.** Parameter table (id → path in `Adjustments`, range, step, default — ranges copied from the slider components), immutable path read/write helpers, and the action registry. |
| `src/hooks/useExternalControl.ts`          | **new.** Listens for commands, applies them through `useEditorActions().setAdjustments` (so history, auto-save, multi-select sync and live preview all work), manages tracking, and publishes throttled `state` snapshots. |
| `src/hooks/useKeyboardShortcuts.ts`        | 3 lines: registers its `actions` map with the registry so controller buttons reuse the shortcut handlers (including their `shouldFire` guards). |
| `src/App.tsx`                              | mounts `useExternalControl()` next to `useKeyboardShortcuts`.                                                                                                        |
| `src/components/ui/AppProperties.tsx`      | the two new optional settings on the `AppSettings` type.                                                                                                             |

No new dependencies. Nothing in the render, export or file pipelines is touched.

## Design decisions worth knowing

* **The frontend owns adjustment state, so the frontend interprets commands.** The Rust
  server is a dumb pipe. This keeps the controller on exactly the code path a mouse drag
  uses; there is no second "apply adjustments" implementation to drift.
* **Plain TCP + JSON lines, not WebSocket/HTTP.** Zero new crates, trivially consumable from
  C# (`TcpClient` + `StreamReader.ReadLine`), Python, `nc`. Push from app to controller is
  needed for dial feedback, which rules out plain request/response HTTP.
* **Loopback only, no auth.** The bind address is `127.0.0.1` and non-loopback peers are
  rejected even if that ever changes.
* **Automatic tracking.** Value changes flag `isSliderDragging`; 180 ms of silence releases
  it. Controllers that know about touch/release can use explicit `tracking` messages.
* **Parameter ranges live in the frontend table**, mirroring the sliders. If upstream adds or
  re-ranges a slider, update `CONTROL_PARAMS`. Clients should read `get_params` at connect
  rather than hard-code ranges.
* **Default on.** The server is harmless on loopback and the whole point of the fork is that
  it runs. `enableExternalControl: false` in `settings.json` turns it off; there is no settings
  UI toggle yet (adding one requires i18n strings in every locale — see "Not done").

## Building on Windows

Prerequisites, per upstream: Rust **1.98+** (`rustup update`), Node 22+, the Visual Studio
C++ build tools, and WebView2 (already on Windows 11). Then, in the repo root:

```
.\tools\rebuild.ps1               # release build -> exe + NSIS installer
.\tools\rebuild.ps1 -Mode dev     # tauri dev: vite + cargo, hot reload for the frontend
.\tools\rebuild.ps1 -Mode check   # cargo check + lint on the fork's files, no binary
.\tools\rebuild.ps1 -Run          # build, then launch it
```

`tools/rebuild.ps1` checks the toolchain versions, runs `npm ci` only when the lockfile
changed, stops a running RapidRAW so the linker can overwrite the exe, and prints the output
paths (`src-tauri/target/release/RapidRAW.exe`, installer under `.../release/bundle/`).
`-Clean` drops only the app crate's artifacts, `-Bundles none|nsis|nsis,msi` picks installers.
Under the hood it is just `npm ci` / `npm run start` / `npx tauri build --bundles nsis`.
First Rust build is long (wgpu, ort, rawler) and `build.rs` downloads `onnxruntime.dll` into
`src-tauri/resources` once; incremental builds are fine.

On macOS, `bash tools/rebuild.sh` is the same script (`--dev`, `--check`, `--bundles app`,
`--clean`, `--run`); it needs Rust >= 1.98, Node 22+ and the Xcode command-line tools, and
produces the `.app` and `.dmg` under `src-tauri/target/release/bundle/`. Not yet exercised
on a Mac.

**A rebuild is needed** for every Rust change (`src-tauri/**`). Frontend-only changes hot
reload under `npm run start`.

## Verifying

1. Start RapidRAW; the log (Settings → Data → *View Application Logs*, i.e. `app.log` in
   the app log directory) should contain `External control: listening on 127.0.0.1:47820`.
2. Open a folder and an image in the editor.
3. From PowerShell:
   ```
   $c = New-Object Net.Sockets.TcpClient('127.0.0.1', 47820); $s = $c.GetStream()
   $r = New-Object IO.StreamReader($s); $w = New-Object IO.StreamWriter($s); $w.AutoFlush = $true
   $r.ReadLine()                                          # hello
   $w.WriteLine('{"type":"adjust","param":"exposure","delta":0.5}')
   $w.WriteLine('{"type":"action","id":"rate_4"}')
   $r.ReadLine(); $r.ReadLine()                           # state, action-result
   ```
   The preview should brighten within a frame, the Basic panel's Exposure slider should
   show +0.50, the image should get four stars, and Ctrl+Z should undo the exposure change.
4. Spin a value continuously (a loop sending `step` every 20 ms) and confirm the preview
   stays responsive, then a full-quality render lands ~200 ms after the loop stops and the
   sidecar is written (`.rrdata` next to the file, or XMP if sync is enabled).

What was verified in this session, on Linux in a clean clone at the same commit:
`cargo check` of the Rust side and `tsc --noEmit` + eslint + prettier on the new TypeScript.
Upstream already fails `tsc --noEmit` with 74 errors in files this fork does not touch;
none are from the new code. The app was **not** run end-to-end here (no GPU, no display),
so step 3 above is the first live test.

## Wiring it into the MX Console plugin

The Logi Actions SDK side can follow the Lightroom `LrDevelopController` shape the project
docs already describe:

* One long-lived `TcpClient` to `127.0.0.1:47820`, reconnecting with backoff when RapidRAW
  is not running. The `ClientApplication` process name to bind to is `RapidRAW`.
* On connect: read `hello`, send `get_params`, build the dial/adjustment list from the reply
  (don't hard-code ranges). Keep the latest `state` to drive dial displays and to know
  whether an image is open.
* Dial tick → `{"type":"step","param":…,"ticks":±n}`; with a modifier held, add
  `"multiplier":10`. Press → `{"type":"reset","param":…}`.
* Buttons → `{"type":"action","id":…}`. Use `action-result: ignored` to flash the key.
* Keep messages small and never wait for a reply before sending the next tick; the app
  coalesces on its side.

## Not done / next steps

* **Settings UI toggle** for enable/port — requires adding strings to every locale in
  `src/i18n/locales` (upstream CI runs `i18n:check`). The backend and `external_control_status`
  command are ready for it.
* **Masks.** Only global adjustments are addressable. Mask-local sliders live under
  `adjustments.masks[i].adjustments`; adding `mask.<id>.<param>` ids to the table is
  straightforward once the UX for "which mask is active" is settled (`activeMaskContainerId`
  is in the editor store).
* **Curves / point curve** are not exposed (no sensible dial mapping).
* **Upstream PR.** The change is small and self-contained; if upstream wants it, the only
  likely asks are the settings toggle and defaulting to off.
