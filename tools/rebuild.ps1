<#
.SYNOPSIS
  Rebuild the RapidRAW external-control fork on Windows.

.DESCRIPTION
  One entry point for the three things you actually do:

    .\tools\rebuild.ps1               # release build, NSIS installer + portable exe
    .\tools\rebuild.ps1 -Mode dev     # tauri dev: vite hot reload + debug cargo build
    .\tools\rebuild.ps1 -Mode check   # cargo check + eslint/prettier on the fork's files, no binary

  Checks the toolchain (Rust >= 1.98, Node >= 22), installs npm deps only when the lockfile
  changed, stops a running RapidRAW so the linker can overwrite the exe, and prints where the
  outputs landed. Every Rust change needs a real rebuild; frontend-only changes hot reload
  under -Mode dev.

.PARAMETER Mode
  build (default) | dev | check

.PARAMETER Bundles
  Tauri bundle targets for -Mode build. Default "nsis". Use "none" for just the exe.
  "msi" is not available while the version carries the -ctl.N suffix (WiX wants a plain
  major.minor.patch).

.PARAMETER Clean
  Remove the app crate's own build artifacts first (cargo clean -p RapidRAW). Dependencies
  stay cached, so this costs a minute or two, not the full 20+ minute first build.

.PARAMETER Run
  Launch the freshly built exe when -Mode build finishes.

.PARAMETER SkipNpm
  Never touch node_modules, even if package-lock.json is newer.

.EXAMPLE
  .\tools\rebuild.ps1 -Run
  .\tools\rebuild.ps1 -Mode build -Bundles none -Clean
#>
[CmdletBinding()]
param(
    [ValidateSet('build', 'dev', 'check')]
    [string]$Mode = 'build',
    [string]$Bundles = 'nsis',
    [switch]$Clean,
    [switch]$Run,
    [switch]$SkipNpm
)

$ErrorActionPreference = 'Stop'
$MinRust = [version]'1.98.0'
$MinNode = [version]'22.0.0'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$TauriDir = Join-Path $RepoRoot 'src-tauri'
$ExeName = 'RapidRAW.exe'
$Started = Get-Date

function Log([string]$msg) {
    $t = (Get-Date).ToString('HH:mm:ss')
    Write-Host "[$t] $msg"
}

function Fail([string]$msg) {
    Write-Host ""
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

function Invoke-Step([string]$label, [scriptblock]$body) {
    Log "==> $label"
    & $body
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        Fail "$label failed (exit code $LASTEXITCODE)"
    }
}

function Get-ToolVersion([string]$cmd, [string[]]$argList, [string]$pattern) {
    $exe = Get-Command $cmd -ErrorAction SilentlyContinue
    if (-not $exe) { return $null }
    $out = & $cmd @argList 2>&1 | Out-String
    if ($out -match $pattern) { return [version]$Matches[1] }
    return $null
}

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------
Set-Location $RepoRoot
Log "RapidRAW fork at $RepoRoot"

$rustVer = Get-ToolVersion 'rustc' @('--version') 'rustc (\d+\.\d+\.\d+)'
if (-not $rustVer) { Fail "rustc not found. Install from https://rustup.rs and reopen the shell." }
if ($rustVer -lt $MinRust) {
    Fail "rustc $rustVer is older than the $MinRust this crate requires (rust-version in Cargo.toml). Run: rustup update"
}
Log "rustc $rustVer"

$nodeVer = Get-ToolVersion 'node' @('--version') 'v(\d+\.\d+\.\d+)'
if (-not $nodeVer) { Fail "node not found. Install Node $MinNode or newer." }
if ($nodeVer -lt $MinNode) { Fail "node $nodeVer is older than $MinNode." }
Log "node $nodeVer"

if (-not (Get-Command 'npm' -ErrorAction SilentlyContinue)) { Fail "npm not found." }

# ---------------------------------------------------------------------------
# npm dependencies (only when the lockfile moved)
# ---------------------------------------------------------------------------
if (-not $SkipNpm) {
    $lock = Join-Path $RepoRoot 'package-lock.json'
    $stamp = Join-Path $RepoRoot 'node_modules\.package-lock.json'
    $needInstall = -not (Test-Path $stamp)
    if (-not $needInstall -and (Test-Path $lock)) {
        $needInstall = (Get-Item $lock).LastWriteTimeUtc -gt (Get-Item $stamp).LastWriteTimeUtc
    }
    if ($needInstall) {
        Invoke-Step 'npm ci' { npm ci --no-audit --no-fund }
    } else {
        Log "node_modules up to date"
    }
}

# ---------------------------------------------------------------------------
# Stop a running instance so the linker can replace the exe
# ---------------------------------------------------------------------------
if ($Mode -ne 'check') {
    $running = Get-Process -Name 'RapidRAW' -ErrorAction SilentlyContinue
    if ($running) {
        Log "Stopping running RapidRAW (pid $($running.Id -join ', '))"
        $running | Stop-Process -Force
        Start-Sleep -Milliseconds 800
    }
}

if ($Clean) {
    Push-Location $TauriDir
    try { Invoke-Step 'cargo clean -p RapidRAW' { cargo clean -p RapidRAW } }
    finally { Pop-Location }
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
switch ($Mode) {
    'check' {
        $forkFiles = @(
            'src/utils/externalControl.ts',
            'src/hooks/useExternalControl.ts',
            'src/hooks/useKeyboardShortcuts.ts',
            'src/App.tsx',
            'src/components/ui/AppProperties.tsx'
        )
        Invoke-Step 'prettier --check (fork files)' { npx prettier --check @forkFiles }
        Invoke-Step 'eslint (fork files)' { npx eslint @forkFiles }
        Push-Location $TauriDir
        try { Invoke-Step 'cargo check' { cargo check } }
        finally { Pop-Location }
        Log "Note: 'npm run typecheck' fails upstream (74 pre-existing errors); not run here."
    }
    'dev' {
        Log "Starting tauri dev (Ctrl+C to stop). First run compiles everything; later runs are incremental."
        npm run start
    }
    'build' {
        $tauriArgs = @('tauri', 'build')
        if ($Bundles -eq 'none') {
            $tauriArgs += '--no-bundle'
        } elseif ($Bundles) {
            $tauriArgs += '--bundles'
            $tauriArgs += $Bundles
        }
        Invoke-Step "npx $($tauriArgs -join ' ')" { npx @tauriArgs }

        $exe = Join-Path $TauriDir "target\release\$ExeName"
        Write-Host ""
        if (Test-Path $exe) {
            $size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
            Log "exe:       $exe ($size MB)"
        } else {
            Fail "Build reported success but $exe is missing."
        }
        $bundleDir = Join-Path $TauriDir 'target\release\bundle'
        if (Test-Path $bundleDir) {
            Get-ChildItem $bundleDir -Recurse -Include *.exe, *.msi |
                Where-Object { $_.FullName -ne $exe } |
                ForEach-Object { Log "installer: $($_.FullName)" }
        }

        if ($Run) {
            Log "Launching $ExeName"
            Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
        }
    }
}

$elapsed = (Get-Date) - $Started
Log ("Done in {0:mm\:ss}" -f $elapsed)
