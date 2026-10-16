# Packs a release zip: artifacts\blak-shaders-<version>-win-x64.zip, holding the files laid out like the BO3 folder
# (where sync.sh puts them) plus blak-shaders.json (components.json with the version and every file's path, size and
# SHA-256). Run compile_check.sh first.
#   .\release.ps1 [-AllowDirty]
param([switch]$AllowDirty)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not $AllowDirty -and (git status --porcelain)) { throw "Uncommitted changes; commit them or pass -AllowDirty." }
$version = (Get-Content VERSION -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION isn't X.Y.Z: $version" }
$manifest = Get-Content components.json -Raw | ConvertFrom-Json

# Stage the install layout, as sync.sh does.
$stage = Join-Path ([System.IO.Path]::GetTempPath()) "blak-shaders-$version"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
function Put($from, $to) {
    Get-ChildItem $from -Recurse -File | ForEach-Object {
        $dest = Join-Path $stage (Join-Path $to $_.FullName.Substring((Resolve-Path $from).Path.Length + 1))
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        Copy-Item $_.FullName $dest
    }
}
foreach ($set in "shaders_stable", "shaders_stable_toolsgfx") {
    Put "deps\$set" "share\raw\$set"
    Put "shaders" "share\raw\$set"
}
foreach ($set in "techsetdefs_stable", "techsetdefs_stable_toolsgfx") { Put "techsets" "share\raw\$set" }
$staged = Get-ChildItem $stage -Recurse -File | ForEach-Object { $_.FullName.Substring($stage.Length + 1).Replace('\', '/') }

# Every staged file belongs to exactly one component, and every pattern matches something.
$owner = @{}
foreach ($c in $manifest.components) {
    $files = @()
    foreach ($f in $c.files) {
        $hits = $staged | Where-Object { $_ -like $f.glob }
        if (-not $hits) { throw "$($c.id): $($f.glob) matches nothing" }
        foreach ($h in $hits) {
            if ($owner[$h]) { throw "$h belongs to both $($owner[$h]) and $($c.id)" }
            $owner[$h] = $c.id
            $full = Join-Path $stage $h
            $files += [pscustomobject]@{
                path = $h
                size = (Get-Item $full).Length
                sha256 = (Get-FileHash $full -Algorithm SHA256).Hash.ToLower()
            }
        }
    }
    $c.files = $files
}
$orphans = $staged | Where-Object { -not $owner[$_] }
if ($orphans) { throw "no component owns: $($orphans -join ', ')" }

$manifest | Add-Member -NotePropertyName version -NotePropertyValue $version -Force
$manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $stage "blak-shaders.json") -Encoding UTF8
New-Item -ItemType Directory -Force artifacts | Out-Null
$zip = "artifacts\blak-shaders-$version-win-x64.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
Remove-Item $stage -Recurse -Force
foreach ($c in $manifest.components) { Write-Host ("{0,-20} {1} files" -f $c.id, $c.files.Count) }
Write-Host "$zip ($((Get-Item $zip).Length) bytes, SHA-256 $((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()))"
