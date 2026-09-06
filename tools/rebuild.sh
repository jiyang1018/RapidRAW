#!/usr/bin/env bash
# Rebuild the RapidRAW external-control fork on macOS (or Linux).
# Counterpart of tools/rebuild.ps1.
#
#     bash tools/rebuild.sh                # release build: .app + .dmg
#     bash tools/rebuild.sh --dev          # tauri dev: vite hot reload + debug cargo build
#     bash tools/rebuild.sh --check        # cargo check + lint on the fork's files, no binary
#     bash tools/rebuild.sh --bundles app  # app only (or: dmg, "app,dmg")
#     bash tools/rebuild.sh --clean        # cargo clean -p RapidRAW first (deps stay cached)
#     bash tools/rebuild.sh --run          # launch the built app afterwards
#
# Prerequisites per upstream: Rust >= 1.98 (rustup), Node >= 22, Xcode command-line tools.

set -u

MODE=build
BUNDLES=dmg
CLEAN=0
RUN=0
SKIP_NPM=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dev) MODE=dev ;;
        --check) MODE=check ;;
        --bundles) BUNDLES="$2"; shift ;;
        --clean) CLEAN=1 ;;
        --run) RUN=1 ;;
        --skip-npm) SKIP_NPM=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

MIN_RUST=1.98.0
MIN_NODE=22.0.0
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TAURI="$REPO/src-tauri"
START=$(date +%s)

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }
fail() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }
# returns 0 when $1 >= $2 (dotted versions)
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]; }

cd "$REPO" || exit 1
log "RapidRAW fork at $REPO"

# --- toolchain ----------------------------------------------------------------
command -v rustc >/dev/null 2>&1 || fail "rustc not found. Install from https://rustup.rs and open a new terminal."
RUST_VER="$(rustc --version | sed -E 's/^rustc ([0-9.]+).*/\1/')"
ver_ge "$RUST_VER" "$MIN_RUST" || fail "rustc $RUST_VER is older than the $MIN_RUST this crate requires. Run: rustup update"
log "rustc $RUST_VER"

command -v node >/dev/null 2>&1 || fail "node not found. Install Node $MIN_NODE or newer."
NODE_VER="$(node --version | sed 's/^v//')"
ver_ge "$NODE_VER" "$MIN_NODE" || fail "node $NODE_VER is older than $MIN_NODE."
log "node $NODE_VER"
command -v npm >/dev/null 2>&1 || fail "npm not found."

# --- npm deps (only when the lockfile moved) ------------------------------------
if [ "$SKIP_NPM" = 0 ]; then
    if [ ! -f node_modules/.package-lock.json ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then
        log "==> npm ci"
        npm ci --no-audit --no-fund || fail "npm ci failed"
    else
        log "node_modules up to date"
    fi
fi

# --- stop a running instance so the bundle can be replaced -----------------------
if [ "$MODE" != check ] && pgrep -x RapidRAW >/dev/null 2>&1; then
    log "Stopping running RapidRAW"
    pkill -x RapidRAW; sleep 1
fi

if [ "$CLEAN" = 1 ]; then
    log "==> cargo clean -p RapidRAW"
    (cd "$TAURI" && cargo clean -p RapidRAW) || fail "cargo clean failed"
fi

case "$MODE" in
    check)
        FORK_FILES="src/utils/externalControl.ts src/hooks/useExternalControl.ts src/hooks/useKeyboardShortcuts.ts src/App.tsx src/components/ui/AppProperties.tsx"
        log "==> prettier --check (fork files)"; npx prettier --check $FORK_FILES || fail "prettier"
        log "==> eslint (fork files)";           npx eslint $FORK_FILES || fail "eslint"
        log "==> cargo check";                   (cd "$TAURI" && cargo check) || fail "cargo check"
        log "Note: 'npm run typecheck' fails upstream (74 pre-existing errors); not run here."
        ;;
    dev)
        log "Starting tauri dev (Ctrl+C to stop). First run compiles everything; later runs are incremental."
        npm run start
        ;;
    build)
        if [ "$BUNDLES" = none ]; then
            log "==> npx tauri build --no-bundle"; npx tauri build --no-bundle || fail "tauri build"
        else
            log "==> npx tauri build --bundles $BUNDLES"; npx tauri build --bundles "$BUNDLES" || fail "tauri build"
        fi
        APP="$(ls -d "$TAURI"/target/release/bundle/macos/*.app 2>/dev/null | head -n 1)"
        BIN="$TAURI/target/release/RapidRAW"
        [ -f "$BIN" ] && log "binary:    $BIN"
        [ -n "$APP" ] && log "app:       $APP"
        for f in "$TAURI"/target/release/bundle/dmg/*.dmg; do [ -f "$f" ] && log "installer: $f"; done
        if [ "$RUN" = 1 ]; then
            if [ -n "$APP" ]; then log "Launching $(basename "$APP")"; open "$APP"
            elif [ -f "$BIN" ]; then log "Launching binary"; "$BIN" & fi
        fi
        ;;
esac

log "Done in $(( $(date +%s) - START ))s"
