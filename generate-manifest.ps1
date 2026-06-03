# Scaffolds / refreshes manifest.json from the images on disk.
#
# This is a CONVENIENCE TOOL for manual or offline edits. In normal operation
# the agent maintains manifest.json via the GitHub Contents API (see
# AGENT_MANIFEST_GUIDE.md). This script cannot know artist/song/album metadata,
# so for any NEW image it writes blank metadata fields for you to fill in. It
# PRESERVES metadata for images already present in manifest.json (matched by path).
#
#   powershell -ExecutionPolicy Bypass -File .\generate-manifest.ps1

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$site = Join-Path $root 'docs'
$starterDir = Join-Path $site 'images/starter-images'
$coverDir   = Join-Path $site 'images/album-art'
$manifestPath = Join-Path $site 'manifest.json'

$imageExt = @('.png', '.jpg', '.jpeg', '.gif', '.webp', '.avif')

# Startup images shown on load.
$starters = Get-ChildItem -Path $starterDir -File |
    Where-Object { $imageExt -contains $_.Extension.ToLower() } |
    Sort-Object Name |
    ForEach-Object { "images/starter-images/$($_.Name)" }

# Load existing metadata (if any) so we don't lose artist/song/album.
$existing = @{}
if (Test-Path $manifestPath) {
    try {
        $prev = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($img in $prev.images) { $existing[$img.path] = $img }
    } catch {
        Write-Warning "Could not parse existing manifest.json; starting fresh."
    }
}

# Build the images array from the album-art folder, preserving known metadata.
$images = Get-ChildItem -Path $coverDir -File |
    Where-Object { $imageExt -contains $_.Extension.ToLower() } |
    Sort-Object Name |
    ForEach-Object {
        $path = "images/album-art/$($_.Name)"
        if ($existing.ContainsKey($path)) {
            $existing[$path]
        } else {
            $slug = ($_.BaseName.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
            [ordered]@{
                id           = $slug
                filename     = $_.Name
                path         = $path
                artist       = ""
                song         = ""
                album        = ""
                generated_at = ""
            }
        }
    }

$manifest = [ordered]@{
    version      = 1
    gallery_name = if ($prev) { $prev.gallery_name } else { "Album Gallery" }
    updated_at   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    starters     = @($starters)
    images       = @($images)
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding utf8

$blank = @($images | Where-Object { -not $_.artist }).Count
Write-Host "Wrote $manifestPath"
Write-Host "  starters: $($starters.Count)"
Write-Host "  images:   $($images.Count)  (with $blank missing metadata to fill in)"
