# ============================================================================
#  TCG WORLD - ADDRESSABLES STARTUP CRASH PATCHER
#  By Rain
#
#  Fixes stuck loading screen:
#    NullReferenceException in AddressablesManager.CheckAndDownloadContent
#    - AddressablesImpl.GetHashCode(IResourceLocation) during DownloadDependenciesAsync
#
#  What it does (Apply):
#    Keeps the remote catalog HASH so the client won't re-download the broken CDN bin,
#    but replaces the catalog BIN with the built-in StreamingAssets copy (known good).
#
#  Run with:
#    powershell -ExecutionPolicy Bypass -File .\TCG_Addressables_Patcher.ps1
#    Or double-click TCG_Addressables_Patcher.bat
#    Best experience: Windows Terminal
#
#  No admin required. Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#  No external modules.
# ============================================================================

# Set $true only if you later add admin-only steps (not needed for this patch).
$RequireAdmin = $false

#region SELF_ELEVATION
if ($RequireAdmin) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $args | Out-Null
        exit
    }
}
#endregion

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# UTF-8 so RAINZY shade logo (░▒▓█) renders correctly in Windows Terminal / modern consoles
try {
    chcp 65001 | Out-Null
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch { }

# ---------------------------------------------------------------------------
# Paths / constants
# ---------------------------------------------------------------------------
# Prefer launcher-provided root (single-file .exe) so backups persist next to the EXE,
# not under %TEMP% which the launcher may delete on exit.
if ($env:TCG_ADDR_PATCHER_ROOT -and (Test-Path -LiteralPath $env:TCG_ADDR_PATCHER_ROOT)) {
    $ScriptRoot = $env:TCG_ADDR_PATCHER_ROOT
} elseif ($PSScriptRoot) {
    $ScriptRoot = $PSScriptRoot
} else {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$BackupRoot   = Join-Path $ScriptRoot 'backups'
$MarkerName   = '.tcg_addr_patch_applied'
$ToolVersion  = '1.0'
$Author       = 'Rain'

$CacheRel     = 'TCG World\TCG World PC Build\com.unity.addressables'
$CacheDir     = Join-Path $env:USERPROFILE (Join-Path 'AppData\LocalLow' $CacheRel)
$ProcessNames = @('TCG World PC Build', 'TCGWorld Launcher')

# Common install roots to auto-detect StreamingAssets\aa\catalog.bin
$InstallSearchRoots = @(
    (Join-Path $env:USERPROFILE 'Documents\Launcher\Apps'),
    (Join-Path $env:USERPROFILE 'Documents\TCG World'),
    'C:\Program Files\TCG World',
    'C:\Program Files (x86)\TCG World',
    'D:\TCG',
    'C:\TCG'
)

#region UI_HELPERS
# Fixed-width frame UI (ASCII only) so borders never drift in WT / conhost / PS 5.1.
# Inner content width is constant; every row is padded to exactly that width.

$script:Ui = @{
    Indent = '  '
    Width  = 66   # characters between the | borders
    B      = 'Cyan'
    G      = 'Green'
    Y      = 'Yellow'
    M      = 'Magenta'
    W      = 'White'
    D      = 'DarkGray'
}

function Clear-ScreenSafe {
    try { Clear-Host } catch { [Console]::Clear() }
}

function Set-ConsoleTheme {
    try {
        $Host.UI.RawUI.WindowTitle = "TCG Addressables Patcher - by $Author"
    } catch { }
    try {
        # Best-effort dark terminal look (ignored if host disallows it)
        $Host.UI.RawUI.BackgroundColor = 'Black'
        $Host.UI.RawUI.ForegroundColor = 'Gray'
    } catch { }
}

function Fit-Width([string]$Text, [int]$Width) {
    if ($null -eq $Text) { $Text = '' }
    if ($Text.Length -gt $Width) { return $Text.Substring(0, $Width) }
    return $Text.PadRight($Width)
}

function Center-Text([string]$Text, [int]$Width) {
    if ($null -eq $Text) { $Text = '' }
    if ($Text.Length -ge $Width) { return $Text.Substring(0, $Width) }
    $left = [int][Math]::Floor(($Width - $Text.Length) / 2)
    return ((' ' * $left) + $Text).PadRight($Width)
}

function Write-Color([string]$Text, [string]$Color = 'Green') {
    Write-Host $Text -ForegroundColor $Color
}

function Write-Muted([string]$Text) {
    Write-Host $Text -ForegroundColor DarkGray
}

function Write-Ok([string]$Text)   { Write-Host "  [ OK ]  $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "  [ .. ]  $Text" -ForegroundColor Cyan }
function Write-Warn([string]$Text) { Write-Host "  [ !! ]  $Text" -ForegroundColor Yellow }
function Write-Err([string]$Text)  { Write-Host "  [FAIL]  $Text" -ForegroundColor Red }

function Write-FrameTop([string]$Color = 'Cyan') {
    $w = $script:Ui.Width
    Write-Host ($script:Ui.Indent + '+' + ('=' * ($w + 2)) + '+') -ForegroundColor $Color
}

function Write-FrameBot([string]$Color = 'Cyan') {
    Write-FrameTop $Color
}

function Write-FrameSep([string]$Color = 'Cyan') {
    $w = $script:Ui.Width
    Write-Host ($script:Ui.Indent + '+' + ('-' * ($w + 2)) + '+') -ForegroundColor $Color
}

function Write-FrameEmpty([string]$Color = 'Cyan') {
    Write-FrameRow -Text '' -Color $Color -BorderColor $Color
}

function Write-FrameRow {
    param(
        [string]$Text = '',
        [string]$Color = 'Green',
        [string]$BorderColor = 'Cyan',
        [ValidateSet('Left', 'Center')]$Align = 'Left'
    )
    $w = $script:Ui.Width
    $inner = if ($Align -eq 'Center') { Center-Text $Text $w } else { Fit-Width $Text $w }
    Write-Host ($script:Ui.Indent + '| ') -NoNewline -ForegroundColor $BorderColor
    Write-Host $inner -NoNewline -ForegroundColor $Color
    Write-Host ' |' -ForegroundColor $BorderColor
}

function Write-FrameRowParts {
    <#
      Writes a framed row from ordered parts: @( @{T='text'; C='Green'}, ... )
      Parts are concatenated then padded to exact inner width.
    #>
    param(
        [Parameter(Mandatory = $true)]$Parts,
        [string]$BorderColor = 'Cyan'
    )
    $w = $script:Ui.Width
    $plain = -join ($Parts | ForEach-Object { [string]$_.T })
    if ($plain.Length -gt $w) {
        # Truncate last part if needed
        $Parts = @($Parts | ForEach-Object { $_ })
    }
    $pad = [Math]::Max(0, $w - $plain.Length)

    Write-Host ($script:Ui.Indent + '| ') -NoNewline -ForegroundColor $BorderColor
    $printed = 0
    foreach ($p in $Parts) {
        $t = [string]$p.T
        if (($printed + $t.Length) -gt $w) {
            $t = $t.Substring(0, [Math]::Max(0, $w - $printed))
        }
        if ($t.Length -gt 0) {
            Write-Host $t -NoNewline -ForegroundColor $p.C
            $printed += $t.Length
        }
        if ($printed -ge $w) { break }
    }
    if ($pad -gt 0 -and $printed -lt $w) {
        Write-Host (' ' * ($w - $printed)) -NoNewline
    }
    Write-Host ' |' -ForegroundColor $BorderColor
}

function Write-MenuOption {
    param(
        [string]$Key,
        [string]$Label,
        [string]$KeyColor = 'White',
        [string]$LabelColor = 'Green'
    )
    Write-FrameRowParts -Parts @(
        @{ T = '  ['; C = 'DarkGray' },
        @{ T = $Key;              C = $KeyColor },
        @{ T = ']  ';             C = 'DarkGray' },
        @{ T = $Label;            C = $LabelColor }
    )
}

function Write-SectionBanner([string]$Title, [string]$Color = 'Green') {
    Write-Host ''
    Write-FrameTop $Color
    Write-FrameRow -Text $Title -Color $Color -BorderColor $Color -Align Center
    Write-FrameBot $Color
    Write-Host ''
}

function Pause-Menu {
    Write-Host ''
    Write-Host '  --------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  Press any key to return to menu...' -ForegroundColor DarkGray
    try {
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } catch {
        Read-Host '  (Press Enter)'
    }
}

function Confirm-Action([string]$Prompt) {
    Write-Host ''
    Write-Host '  +------------------------------------------------+' -ForegroundColor Yellow
    Write-Host '  |  ' -NoNewline -ForegroundColor Yellow
    Write-Host (Fit-Width $Prompt 44) -NoNewline -ForegroundColor White
    Write-Host '  |' -ForegroundColor Yellow
    Write-Host '  +------------------------------------------------+' -ForegroundColor Yellow
    Write-Host '  Confirm [Y/N]: ' -ForegroundColor Yellow -NoNewline
    $r = Read-Host
    return ($r -match '^[Yy]')
}

function Get-RainzyLogoLines {
    # Prefer external ascii-rainzy.txt (HTML export) next to the script; else embed.
    $searchDirs = @($ScriptRoot)
    if ($PSScriptRoot -and ($PSScriptRoot -ne $ScriptRoot)) { $searchDirs += $PSScriptRoot }
    $candidates = foreach ($d in $searchDirs) {
        Join-Path $d 'ascii-rainzy.txt'
        Join-Path $d 'ascii-rainzy.html'
    }
    foreach ($path in $candidates) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            # Strip HTML wrapper / tags from typical ascii-art generators
            $raw = $raw -replace '(?is)<span[^>]*>', ''
            $raw = $raw -replace '(?is)</span>', ''
            $raw = $raw -replace '(?i)<br\s*/?>', "`n"
            $raw = $raw -replace '&nbsp;', ' '
            $raw = $raw -replace '&amp;', '&'
            $raw = $raw -replace '&lt;', '<'
            $raw = $raw -replace '&gt;', '>'
            $lines = $raw -split "`r?`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -match '\S' }
            if ($lines -and $lines.Count -gt 0) { return @($lines) }
        } catch { }
    }

    # Embedded fallback (RAINZY shade logo from ascii-rainzy.txt)
    return @(
        '░░░░░░   ░░░░░  ░░ ░░░    ░░ ░░░░░░░ ░░    ░░',
        '▒▒   ▒▒ ▒▒   ▒▒ ▒▒ ▒▒▒▒   ▒▒    ▒▒▒   ▒▒  ▒▒',
        '▒▒▒▒▒▒  ▒▒▒▒▒▒▒ ▒▒ ▒▒ ▒▒  ▒▒   ▒▒▒     ▒▒▒▒',
        '▓▓   ▓▓ ▓▓   ▓▓ ▓▓ ▓▓  ▓▓ ▓▓  ▓▓▓       ▓▓',
        '██   ██ ██   ██ ██ ██   ████ ███████    ██'
    )
}

function Show-LogoBlock {
    # RAINZY logo (ascii-rainzy.txt) - fixed-width framed rows.
    $logo = Get-RainzyLogoLines

    Write-FrameEmpty
    foreach ($line in $logo) {
        Write-FrameRow -Text $line -Color Green -Align Center
    }
    Write-FrameEmpty
}

function Show-Header {
    Clear-ScreenSafe
    Set-ConsoleTheme
    Write-Host ''

    # Outer hero frame
    Write-FrameTop 'Cyan'
    Show-LogoBlock

    # Centered subtitle (build plain string first, then color by index ranges)
    $subPlain = "ADDRESSABLES CRASH PATCHER  v$ToolVersion"
    $subLine  = Center-Text $subPlain $script:Ui.Width
    $verToken = "v$ToolVersion"
    $verAt = $subLine.IndexOf($verToken)
    if ($verAt -ge 0) {
        Write-Host ($script:Ui.Indent + '| ') -NoNewline -ForegroundColor Cyan
        if ($verAt -gt 0) {
            Write-Host $subLine.Substring(0, $verAt) -NoNewline -ForegroundColor White
        }
        Write-Host $verToken -NoNewline -ForegroundColor Yellow
        $after = $verAt + $verToken.Length
        if ($after -lt $subLine.Length) {
            Write-Host $subLine.Substring($after) -NoNewline -ForegroundColor White
        }
        Write-Host ' |' -ForegroundColor Cyan
    } else {
        Write-FrameRow -Text $subPlain -Color White -Align Center
    }

    $byPlain = "by $Author  |  TCG World PC (Staging/Prod)"
    $byLine  = Center-Text $byPlain $script:Ui.Width
    $nameAt  = $byLine.IndexOf($Author)
    Write-Host ($script:Ui.Indent + '| ') -NoNewline -ForegroundColor Cyan
    if ($nameAt -gt 0) {
        Write-Host $byLine.Substring(0, $nameAt) -NoNewline -ForegroundColor DarkGray
    }
    Write-Host $Author -NoNewline -ForegroundColor Magenta
    $afterName = $nameAt + $Author.Length
    if ($afterName -lt $byLine.Length) {
        Write-Host $byLine.Substring($afterName) -NoNewline -ForegroundColor DarkGray
    }
    Write-Host ' |' -ForegroundColor Cyan

    Write-FrameEmpty
    Write-FrameBot 'Cyan'

    Write-Host ''
    Write-Host '  Fixes NullReferenceException in AddressablesManager at startup.' -ForegroundColor DarkGray
    Write-Host '  Spoofs built-in catalog.bin while keeping remote catalog hash.' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-StatusLine {
    $patched = Test-PatchApplied
    Write-Host '  ' -NoNewline
    Write-Host ' STATUS ' -NoNewline -ForegroundColor Black -BackgroundColor DarkCyan
    Write-Host '  ' -NoNewline
    if ($patched) {
        Write-Host ' PATCH APPLIED ' -ForegroundColor Black -BackgroundColor Green
    } else {
        Write-Host ' NOT PATCHED ' -NoNewline -ForegroundColor Black -BackgroundColor Yellow
        Write-Host '  stock / restored' -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Show-Menu {
    Show-Header
    Show-StatusLine

    # Compact menu panel (narrower visual weight, still fixed-width via shared helpers)
    $oldW = $script:Ui.Width
    $script:Ui.Width = 40

    Write-FrameTop 'Cyan'
    Write-FrameRow -Text 'MAIN MENU' -Color Cyan -Align Center
    Write-FrameSep 'Cyan'
    Write-MenuOption -Key '1' -Label 'Apply Patch'          -KeyColor 'Green'  -LabelColor 'Green'
    Write-MenuOption -Key '2' -Label 'Undo / Revert Patch'  -KeyColor 'Yellow' -LabelColor 'Yellow'
    Write-MenuOption -Key '3' -Label 'Exit'                 -KeyColor 'White'  -LabelColor 'Gray'
    Write-FrameBot 'Cyan'

    $script:Ui.Width = $oldW

    Write-Host ''
    Write-Host '  > ' -NoNewline -ForegroundColor Cyan
    Write-Host 'Select option [1-3]: ' -NoNewline -ForegroundColor White
}
#endregion

#region PATH_RESOLUTION
function Test-GameRunning {
    foreach ($n in $ProcessNames) {
        $p = Get-Process -Name $n -ErrorAction SilentlyContinue
        if ($p) { return $true }
    }
    return $false
}

function Find-BuiltinCatalog {
    # 1) Marker / previous resolution
    $hintFile = Join-Path $BackupRoot 'last_builtin_path.txt'
    if (Test-Path $hintFile) {
        $hint = (Get-Content $hintFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($hint -and (Test-Path $hint)) { return $hint }
    }

    # 2) Player.log install path (if available)
    $log = Join-Path $env:USERPROFILE 'AppData\LocalLow\TCG World\TCG World PC Build\Player.log'
    if (Test-Path $log) {
        $line = Select-String -Path $log -Pattern 'Loading player data from (.+?)[\\/]data\.unity3d' -ErrorAction SilentlyContinue |
            Select-Object -Last 1
        if ($line) {
            $dataDir = $line.Matches[0].Groups[1].Value
            $cand = Join-Path $dataDir 'StreamingAssets\aa\catalog.bin'
            if (Test-Path $cand) { return $cand }
        }
    }

    # 3) Search known roots (shallow-ish)
    foreach ($root in $InstallSearchRoots) {
        if (-not (Test-Path $root)) { continue }
        try {
            $found = Get-ChildItem -Path $root -Filter 'catalog.bin' -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'StreamingAssets[\\/]aa[\\/]catalog\.bin$' } |
                Select-Object -First 1
            if ($found) { return $found.FullName }
        } catch { }
    }

    return $null
}

function Get-ActiveCatalogPair {
    <#
      Returns hashtable: Version, Bin, Hash, BackupBin, BackupHash
      Prefers highest 0.x.y version present that is not a backup.
    #>
    if (-not (Test-Path $CacheDir)) {
        throw "Addressables cache not found:`n  $CacheDir`nLaunch the game once so Unity creates the cache folder."
    }

    $bins = Get-ChildItem -Path $CacheDir -Filter 'catalog_*.bin' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.broken_bak$|\.bak$' -and $_.Name -match '^catalog_(\d+\.\d+\.\d+)\.bin$' }

    if (-not $bins) {
        throw "No catalog_*.bin found in:`n  $CacheDir"
    }

    $best = $bins | Sort-Object {
        if ($_.Name -match 'catalog_(\d+)\.(\d+)\.(\d+)\.bin') {
            [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
        } else { [version]'0.0.0' }
    } -Descending | Select-Object -First 1

    $null = $best.Name -match 'catalog_(\d+\.\d+\.\d+)\.bin'
    $ver = $Matches[1]
    $bin  = $best.FullName
    $hash = Join-Path $CacheDir "catalog_$ver.hash"

    return @{
        Version    = $ver
        Bin        = $bin
        Hash       = $hash
        BackupBin  = Join-Path $CacheDir "catalog_$ver.bin.broken_bak"
        BackupHash = Join-Path $CacheDir "catalog_$ver.hash.broken_bak"
        Marker     = Join-Path $CacheDir $MarkerName
    }
}

function Test-PatchApplied {
    try {
        $pair = Get-ActiveCatalogPair
        if (Test-Path $pair.Marker) { return $true }
        # Also detect our in-place .broken_bak without marker
        if ((Test-Path $pair.BackupBin) -and (Test-Path $pair.Bin)) {
            $a = (Get-FileHash $pair.Bin -Algorithm MD5).Hash
            $b = (Get-FileHash $pair.BackupBin -Algorithm MD5).Hash
            if ($a -ne $b) { return $true }
        }
    } catch { }
    return $false
}

function Ensure-BackupFolder {
    if (-not (Test-Path $BackupRoot)) {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    }
}

function New-TimestampedBackup([string]$SourcePath) {
    Ensure-BackupFolder
    if (-not (Test-Path $SourcePath)) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $name  = '{0}_{1}' -f $stamp, [IO.Path]::GetFileName($SourcePath)
    $dest  = Join-Path $BackupRoot $name
    Copy-Item -LiteralPath $SourcePath -Destination $dest -Force
    return $dest
}
#endregion

#region APPLY_PATCH
function Apply-Patch {
    Show-Header
    Write-SectionBanner 'APPLY PATCH' 'Green'

    if (-not (Confirm-Action 'Apply Addressables catalog patch?')) {
        Write-Warn 'Cancelled by user.'
        Pause-Menu
        return
    }

    Write-Host ''

    try {
        if (Test-GameRunning) {
            throw "TCG World (or launcher) is still running. Close the game completely, then try again."
        }
        Write-Ok 'Game process not running.'

        if (Test-PatchApplied) {
            Write-Warn 'Patch already appears applied. Re-applying will refresh from built-in catalog.'
            if (-not (Confirm-Action 'Continue anyway?')) {
                Write-Warn 'Cancelled.'
                Pause-Menu
                return
            }
        }

        $pair = Get-ActiveCatalogPair
        Write-Info "Cache:  $CacheDir"
        Write-Info "Catalog version detected: $($pair.Version)"

        $builtin = Find-BuiltinCatalog
        if (-not $builtin) {
            Write-Warn 'Could not auto-find StreamingAssets\aa\catalog.bin'
            Write-Host '  Paste full path to catalog.bin: ' -ForegroundColor Yellow -NoNewline
            $builtin = (Read-Host).Trim().Trim('"')
            if (-not (Test-Path $builtin)) {
                throw "Built-in catalog not found: $builtin"
            }
        }
        Write-Ok "Built-in catalog: $builtin"

        Ensure-BackupFolder
        $builtinHint = Join-Path $BackupRoot 'last_builtin_path.txt'
        Set-Content -Path $builtinHint -Value $builtin -Encoding UTF8

        # Timestamped backups (script folder) + in-place .broken_bak (same as manual fix)
        Write-Info 'Creating backups...'
        $tb1 = New-TimestampedBackup $pair.Bin
        $tb2 = $null
        if (Test-Path $pair.Hash) { $tb2 = New-TimestampedBackup $pair.Hash }
        Copy-Item -LiteralPath $pair.Bin -Destination $pair.BackupBin -Force
        if (Test-Path $pair.Hash) {
            Copy-Item -LiteralPath $pair.Hash -Destination $pair.BackupHash -Force
        }
        Write-Ok "In-place backup: $($pair.BackupBin)"
        if ($tb1) { Write-Ok "Script backup:  $tb1" }
        if ($tb2) { Write-Ok "Script backup:  $tb2" }

        # Keep HASH (remote), replace BIN (built-in) - prevents CDN re-download of bad catalog
        $hashBefore = $null
        if (Test-Path $pair.Hash) {
            $hashBefore = (Get-Content -LiteralPath $pair.Hash -Raw).Trim()
        }

        Copy-Item -LiteralPath $builtin -Destination $pair.Bin -Force

        # Remove stale older catalog versions (e.g. 0.2.5 leftovers) that can confuse troubleshooting
        Get-ChildItem -Path $CacheDir -Filter 'catalog_*.bin' -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^catalog_(\d+\.\d+\.\d+)\.bin$' -and
                $Matches[1] -ne $pair.Version -and
                $_.Name -notmatch 'broken_bak'
            } | ForEach-Object {
                $staleVer = $Matches[1]
                Write-Info "Removing stale catalog_$staleVer.*"
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                $staleHash = Join-Path $CacheDir "catalog_$staleVer.hash"
                if (Test-Path $staleHash) { Remove-Item -LiteralPath $staleHash -Force -ErrorAction SilentlyContinue }
            }

        # Marker for status detection
        $markerBody = @"
TCG Addressables Patch - by $Author
Applied: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Version: $($pair.Version)
Builtin: $builtin
RemoteHashKept: $hashBefore
ActiveBinMD5: $((Get-FileHash -LiteralPath $pair.Bin -Algorithm MD5).Hash)
BackupBin: $($pair.BackupBin)
"@
        Set-Content -LiteralPath $pair.Marker -Value $markerBody -Encoding UTF8

        $activeMd5 = (Get-FileHash -LiteralPath $pair.Bin -Algorithm MD5).Hash
        $builtMd5  = (Get-FileHash -LiteralPath $builtin -Algorithm MD5).Hash
        $bakMd5    = (Get-FileHash -LiteralPath $pair.BackupBin -Algorithm MD5).Hash

        Write-Host ''
        if ($activeMd5 -eq $builtMd5 -and $activeMd5 -ne $bakMd5) {
            Write-Ok 'PATCH APPLIED SUCCESSFULLY'
        } elseif ($activeMd5 -eq $builtMd5) {
            Write-Ok 'PATCH APPLIED (bin matches built-in; backup identical - may have been patched already)'
        } else {
            throw "Post-check failed: active bin MD5 does not match built-in catalog."
        }

        Write-Host ''
        Write-Info "Active bin MD5 : $activeMd5"
        Write-Info "Backup  bin MD5: $bakMd5"
        if ($hashBefore) {
            Write-Info "Hash left as   : $hashBefore  (remote - intentional)"
        }
        Write-Host ''
        Write-Color '  Next: launch TCG World. You should pass the stuck screen and may download content.' 'Cyan'
        Write-Muted '  A multi-GB content download after this is normal if caches mismatch.'
    }
    catch {
        Write-Host ''
        Write-Err $_.Exception.Message
        Write-Warn 'No partial in-place swap was intended after failure; check backups folder if unsure.'
    }

    Pause-Menu
}
#endregion

#region UNDO_PATCH
function Undo-Patch {
    Show-Header
    Write-SectionBanner 'UNDO / REVERT PATCH' 'Yellow'

    if (-not (Confirm-Action 'Restore original remote catalog from backup?')) {
        Write-Warn 'Cancelled by user.'
        Pause-Menu
        return
    }

    Write-Host ''

    try {
        if (Test-GameRunning) {
            throw "TCG World (or launcher) is still running. Close the game completely, then try again."
        }
        Write-Ok 'Game process not running.'

        $pair = Get-ActiveCatalogPair
        Write-Info "Cache: $CacheDir"
        Write-Info "Catalog version: $($pair.Version)"

        if (-not (Test-Path $pair.BackupBin)) {
            # Fall back to newest timestamped backup in script backups folder
            Ensure-BackupFolder
            $pattern = "catalog_$($pair.Version).bin"
            $fallback = Get-ChildItem -Path $BackupRoot -Filter "*_$pattern" -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($fallback) {
                Write-Warn "No .broken_bak in cache; using script backup: $($fallback.Name)"
                Copy-Item -LiteralPath $fallback.FullName -Destination $pair.Bin -Force
            } else {
                throw "No backup found to restore.`nExpected: $($pair.BackupBin)`nOr timestamped file in: $BackupRoot"
            }
        } else {
            # Snapshot current (patched) state before restore
            $null = New-TimestampedBackup $pair.Bin
            Copy-Item -LiteralPath $pair.BackupBin -Destination $pair.Bin -Force
            Write-Ok "Restored bin from: $($pair.BackupBin)"
        }

        if (Test-Path $pair.BackupHash) {
            Copy-Item -LiteralPath $pair.BackupHash -Destination $pair.Hash -Force
            Write-Ok "Restored hash from: $($pair.BackupHash)"
        }

        if (Test-Path $pair.Marker) {
            Remove-Item -LiteralPath $pair.Marker -Force
            Write-Ok 'Removed patch marker.'
        }

        Write-Host ''
        Write-Ok 'PATCH REVERTED - original remote catalog restored.'
        Write-Warn 'If CDN catalog is still broken, the loading-screen crash may return.'
    }
    catch {
        Write-Host ''
        Write-Err $_.Exception.Message
    }

    Pause-Menu
}
#endregion

#region MAIN
try {
    if (-not (Test-Path $BackupRoot)) {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    }

    while ($true) {
        Show-Menu
        $choice = Read-Host
        switch ($choice.Trim()) {
            '1' { Apply-Patch }
            '2' { Undo-Patch }
            '3' {
                Clear-ScreenSafe
                Write-Host ''
                Write-FrameTop 'Magenta'
                Write-FrameRow -Text 'Thanks for using TCG Addressables Patcher' -Color Magenta -BorderColor Magenta -Align Center
                Write-FrameRowParts -BorderColor Magenta -Parts @(
                    @{ T = '              by '; C = 'DarkGray' },
                    @{ T = $Author; C = 'Magenta' },
                    @{ T = '  -  stay safe out there.'; C = 'DarkGray' }
                )
                Write-FrameBot 'Magenta'
                Write-Host ''
                exit 0
            }
            default {
                Write-Warn 'Invalid option. Choose 1, 2, or 3.'
                Start-Sleep -Seconds 1
            }
        }
    }
}
catch {
    Write-Err $_.Exception.Message
    Write-Host 'Press Enter to exit...' -ForegroundColor DarkGray
    $null = Read-Host
    exit 1
}
#endregion
