# install.ps1 - put WowPad on top of a benilla checkout on Windows; the same steps as install.sh.
#
#   Double-click "Install WowPad (Windows).bat", or:
#   powershell -ExecutionPolicy Bypass -File install.ps1 [C:\path\to\benilla]
#   ... -NoBuild       install or update, skip the build
#   ... -PatchesOnly   only bring the engine patches in (for update scripts)
#   ... -Remove        take WowPad's engine patches back out and delete the crate
#
# "-ExecutionPolicy Bypass" lets this one script run without changing any Windows setting.
# Safe to run again after every benilla update: it copies this folder to crates\benilla-wowpad,
# then applies the engine patches in patches\ in their numbered order, like a load order. A patch
# already in is skipped; one that no longer fits stops the run and names the files, and nothing
# after it is touched. Extra cargo features: $env:WOWPAD_FEATURES="feat1,feat2" first.

param(
    [string]$Path = "",
    [switch]$NoBuild,
    [switch]$PatchesOnly,
    [switch]$Remove
)

$ErrorActionPreference = "Stop"
$Src = Split-Path -Parent $MyInvocation.MyCommand.Path

function Stop-Install($msg) {
    Write-Host ""
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    Write-Host "Nothing after this step was changed."
    exit 1
}
function Say($msg) { Write-Host "==> $msg" }

function Is-Benilla($dir) {
    return $dir -and (Test-Path (Join-Path $dir "Cargo.toml")) -and
        (Test-Path (Join-Path (Join-Path $dir "crates") "benilla-app"))
}

# No folder given (a double-click): the benilla folder this one sits in (crates\benilla-wowpad),
# the current folder, a single benilla folder next to this one, else ask with a folder picker.
if (-not $Path) {
    $up2 = Split-Path (Split-Path $Src)
    $here = (Get-Location).Path
    $siblings = @(Get-ChildItem -Directory (Split-Path $Src) -ErrorAction SilentlyContinue |
        Where-Object { Is-Benilla $_.FullName })
    if (Is-Benilla $up2) { $Path = $up2 }
    elseif ((Is-Benilla $here) -and ($here -ne $Src)) { $Path = $here }
    elseif ($siblings.Count -eq 1) { $Path = $siblings[0].FullName }
    else {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $pick = New-Object System.Windows.Forms.FolderBrowserDialog
            $pick.Description = "Pick your benilla folder (the one with Cargo.toml and crates in it)"
            if ($pick.ShowDialog() -eq "OK") { $Path = $pick.SelectedPath }
        } catch { }
        if (-not $Path) { Stop-Install "no benilla folder picked. Run again and pick it, or pass its path." }
    }
    Write-Host "benilla folder: $Path"
}
if (-not (Test-Path $Path)) { Stop-Install "no such folder: $Path" }
$Root = (Resolve-Path $Path).Path
if (-not (Is-Benilla $Root)) {
    Stop-Install "$Root is not a benilla checkout (no crates\benilla-app). Pick the benilla folder itself."
}
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Stop-Install "Git is not installed (https://git-scm.com)" }
# Git for Windows carries GNU patch, used for patches whose surrounding lines a fork changed.
$patchExe = Join-Path (Split-Path (Split-Path $git.Source)) "usr\bin\patch.exe"
if (-not (Test-Path $patchExe)) {
    $patchCmd = Get-Command patch -CommandType Application -ErrorAction SilentlyContinue
    $patchExe = if ($patchCmd) { $patchCmd[0].Source } else { $null }
}
$Dest = Join-Path (Join-Path $Root "crates") "benilla-wowpad"
# WowPad already there as this very folder (cloned or linked into crates\): use it as it is.
function Real-Path($p) {
    $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    if ($item.LinkType -and $item.Target) { return (Resolve-Path ($item.Target | Select-Object -First 1)).Path }
    return $item.FullName
}
if ((Real-Path $Dest) -eq (Real-Path $Src)) { $Dest = $Src }

# Run git (or patch) in the benilla folder; returns $true on success. Output is hidden unless asked.
function Run($exe, [string[]]$argv, [switch]$Show) {
    Push-Location $Root
    try {
        $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        $out = & $exe @argv 2>&1
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $old
        if ($Show) { $out | ForEach-Object { Write-Host "    $_" } }
        return $ok
    } finally { Pop-Location }
}
$IsRepo = Run git @("rev-parse", "--is-inside-work-tree")

function Patch-Files($p) {
    Get-Content $p | Where-Object { $_ -like "+++ b/*" } | ForEach-Object { $_.Substring(6) }
}

# Whether a patch is already in: it reverses cleanly, or (after benilla moved the lines around it)
# every substantial line it adds is already in its file.
function Already-In($p) {
    if (Run git @("apply", "--reverse", "--check", "--ignore-whitespace", $p)) { return $true }
    $file = $null; $found = $false
    foreach ($line in Get-Content $p) {
        if ($line -like "+++ b/*") { $file = Join-Path $Root $line.Substring(6); continue }
        if ($line -like "+++ *") { $file = $null; continue }
        if ($line.StartsWith("+") -and $file) {
            $t = $line.Substring(1).Trim()
            if ($t.Length -lt 12) { continue }
            if (-not (Test-Path $file)) { return $false }
            if (-not (Select-String -Path $file -SimpleMatch -Quiet -Pattern $t)) { return $false }
            $found = $true
        }
    }
    return $found
}

function Try-Patch($p) {
    $name = [IO.Path]::GetFileNameWithoutExtension($p)
    if (Run git @("apply", "--check", $p)) {
        if (-not (Run git @("apply", $p) -Show)) { Stop-Install "patch $name failed to apply" }
        Write-Host "  ${name}: applied"; return $true
    }
    # Benilla moved on since the patch was made (or Git wrote its files with Windows line ends):
    # a three-way merge places it by content. On a conflict the files go back as they were.
    if ($IsRepo) {
        $files = @(Patch-Files $p)
        $saved = [IO.Path]::GetTempFileName()
        Run git (@("diff", "--binary", "--output=$saved", "HEAD", "--") + $files) | Out-Null
        $merged = Run git @("apply", "-3", $p)
        $conflicts = & git -C $Root diff --name-only --diff-filter=U
        if ($merged -and -not $conflicts) {
            Remove-Item $saved; Write-Host "  ${name}: applied (merged)"; return $true
        }
        Run git (@("checkout", "-q", "HEAD", "--") + $files) | Out-Null
        if ((Get-Item $saved).Length -gt 0) { Run git @("apply", $saved) | Out-Null }
        Remove-Item $saved
    }
    if (Run git @("apply", "--check", "--ignore-whitespace", $p)) {
        if (-not (Run git @("apply", "--ignore-whitespace", $p) -Show)) { Stop-Install "patch $name failed to apply" }
        Write-Host "  ${name}: applied"; return $true
    }
    # A fork that changed the lines next to WowPad's: place each hunk by its nearest context.
    if ($patchExe -and (Run $patchExe @("--dry-run", "-p1", "-N", "-F3", "-l", "-s", "-i", $p))) {
        if (-not (Run $patchExe @("-p1", "-N", "-F3", "-l", "-s", "--no-backup-if-mismatch", "-i", $p) -Show)) {
            Stop-Install "patch $name failed to apply"
        }
        Write-Host "  ${name}: applied (placed by nearby lines: build to check it)"; return $true
    }
    return $false
}

# A patch, in the version for the newest benilla, else (an older benilla) the one before it, kept in
# patches\legacy. An older version this checkout already carries is taken out first, since the
# newer one is written for the code without it.
function Apply-Patch($p) {
    $name = [IO.Path]::GetFileNameWithoutExtension($p)
    $old = Join-Path (Join-Path (Split-Path $p) "legacy") "$name.patch"
    if ((Test-Path $old) -and -not (Run git @("apply", "--reverse", "--check", "--ignore-whitespace", $p)) -and
        (Run git @("apply", "--reverse", "--check", "--ignore-whitespace", $old))) {
        if (Run git @("apply", "--reverse", "--ignore-whitespace", $old)) { Write-Host "  ${name}: older version taken out" }
    }
    if (Already-In $p) { Write-Host "  ${name}: already in"; return }
    if (Try-Patch $p) { return }
    if (Test-Path $old) {
        Write-Host "  ${name}: does not fit this benilla; trying the older version"
        if (Try-Patch $old) { return }
    }
    Patch-Files $p | ForEach-Object { Write-Host "    touches: $_" }
    Stop-Install "patch $name does not fit this benilla version. Update WowPad (git pull in $Src) and run again; if it still fails, the patch needs refreshing for this benilla"
}

function Is-WowPadCrate($dir) {
    $toml = Join-Path $dir "Cargo.toml"
    return (Test-Path $toml) -and [bool](Select-String -Path $toml -SimpleMatch -Quiet -Pattern 'name = "benilla-wowpad"')
}

$patches = Get-ChildItem (Join-Path $Src "patches") -Filter "*.patch" |
    Where-Object { $_.Name -match '^\d' } | Sort-Object Name

if ($Remove) {
    Say "Taking WowPad's engine patches out of $Root"
    foreach ($p in ($patches | Sort-Object Name -Descending)) {
        if (Run git @("apply", "--reverse", "--check", "--ignore-whitespace", $p.FullName)) {
            Run git @("apply", "--reverse", "--ignore-whitespace", $p.FullName) | Out-Null
            Write-Host "  $($p.BaseName): removed"
        } elseif ((Test-Path (Join-Path $p.DirectoryName "legacy\$($p.Name)")) -and
            (Run git @("apply", "--reverse", "--check", "--ignore-whitespace", (Join-Path $p.DirectoryName "legacy\$($p.Name)")))) {
            Run git @("apply", "--reverse", "--ignore-whitespace", (Join-Path $p.DirectoryName "legacy\$($p.Name)")) | Out-Null
            Write-Host "  $($p.BaseName): removed (older version)"
        } elseif ($patchExe -and (Run $patchExe @("--dry-run", "-R", "-p1", "-F3", "-l", "-s", "-i", $p.FullName))) {
            Run $patchExe @("-R", "-p1", "-F3", "-l", "-s", "--no-backup-if-mismatch", "-i", $p.FullName) | Out-Null
            Write-Host "  $($p.BaseName): removed (placed by nearby lines)"
        } else {
            Write-Host "  $($p.BaseName): not in cleanly, left alone (git checkout the files it touches to undo)"
        }
    }
    if (($Dest -ne $Src) -and (Is-WowPadCrate $Dest)) {
        Remove-Item -Recurse -Force $Dest
        Write-Host "  crates\benilla-wowpad: deleted"
    }
    exit 0
}

if (-not $PatchesOnly) {
    Say "WowPad crate"
    if ($Dest -eq $Src) {
        Write-Host "  already in place ($Dest)"
    } else {
        if ((Test-Path $Dest) -and -not (Is-WowPadCrate $Dest)) {
            Stop-Install "$Dest exists and is not WowPad; move it away first"
        }
        if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
        New-Item -ItemType Directory -Force $Dest | Out-Null
        Get-ChildItem -Force $Src | Where-Object { $_.Name -notin @(".git", "target") } |
            Copy-Item -Destination $Dest -Recurse -Force
        Write-Host "  copied to crates\benilla-wowpad"
    }
}

Say "Engine patches (in order)"
foreach ($p in $patches) { Apply-Patch $p.FullName }

if ($NoBuild -or $PatchesOnly) { Write-Host ""; Write-Host "Done (no build)."; exit 0 }

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Stop-Install "cargo is not installed (https://rustup.rs), so WowPad can't be built"
}
$features = @()
if ($env:WOWPAD_FEATURES) { $features += $env:WOWPAD_FEATURES -split "," }
# Build what the checkout's own game builds by default: every feature the benilla launcher turns on
# by default (a fork's extras included) that reaches benilla-app goes on here too.
$launcher = Join-Path (Join-Path (Join-Path $Root "crates") "benilla") "Cargo.toml"
if (Test-Path $launcher) {
    $toml = Get-Content $launcher
    $def = $toml | Where-Object { $_ -match '^default\s*=\s*\[(.*)\]' } | Select-Object -First 1
    if ($def -and ($def -match '\[(.*)\]')) {
        foreach ($f in (($Matches[1] -replace '[" ]', '') -split ',')) {
            if (-not $f -or $f -eq "dev") { continue }
            $line = $toml | Where-Object { $_ -match "^$([regex]::Escape($f))\s*=" } | Select-Object -First 1
            if ($line) {
                foreach ($m in [regex]::Matches($line, '"(benilla-app/[A-Za-z0-9_-]+)"')) {
                    $app = $m.Groups[1].Value
                    if ($features -notcontains $app) { $features += $app }
                }
            }
        }
    }
}
$cargoArgs = @("build", "--release", "-p", "benilla-wowpad")
if ($features.Count -gt 0) { $cargoArgs += @("--features", ($features -join ",")) }
Say "Building (cargo $($cargoArgs -join ' '))"
Push-Location $Root
& cargo @cargoArgs
$ok = ($LASTEXITCODE -eq 0)
Pop-Location
if (-not $ok) { Stop-Install "the build failed (the errors are above)" }

Write-Host ""
Write-Host "Done. Start the game with:"
Write-Host "  cd `"$Root`""
Write-Host '  $env:WOW_HOST="your.server"; .\target\release\benilla-wowpad.exe'
Write-Host ""
Write-Host "Run this script again after updating benilla or WowPad."
