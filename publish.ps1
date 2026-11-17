#requires -Version 5.1
<#
Publishes the prepared AffixLens v3.0.0 release asset to StabbyMcStaber/AffixLens.
Requires GitHub CLI (gh) and GitHub authorization with repository write access.
Does not modify or push source; the source is already committed to GitHub.
#>
[CmdletBinding()]
param(
    [string]$Tag = 'v3.0.0',
    [switch]$Prerelease
)

$ErrorActionPreference = 'Stop'
$Repo = 'StabbyMcStaber/AffixLens'
$Asset = Join-Path $PSScriptRoot 'AffixLens-v3.0.0.zip'
$Notes = Join-Path $PSScriptRoot 'RELEASE_NOTES.md'
$PinnedCommitFile = Join-Path $PSScriptRoot 'SOURCE_COMMIT.txt'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI not found. Install it with: winget install --id GitHub.cli --exact'
}
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI is not logged in. Run: gh auth login'
}

if (-not (Test-Path -LiteralPath $Notes -PathType Leaf)) {
    throw "Release notes not found: $Notes"
}
if (-not (Test-Path -LiteralPath $Asset -PathType Leaf)) {
    $Addon = Join-Path $PSScriptRoot 'AffixLens'
    if (-not (Test-Path -LiteralPath (Join-Path $Addon 'AffixLens.toc') -PathType Leaf)) {
        throw "Neither the release ZIP nor a complete AffixLens folder exists in $PSScriptRoot"
    }
    Compress-Archive -Path $Addon -DestinationPath $Asset -CompressionLevel Optimal -Force
}

# Publishing kit has the exact SHA of the already-uploaded source revision.
# When running from a checkout without a pin file, target the current main head.
if (Test-Path -LiteralPath $PinnedCommitFile -PathType Leaf) {
    $TargetCommit = (Get-Content -LiteralPath $PinnedCommitFile -Raw).Trim()
} else {
    $TargetCommit = (& gh api "repos/$Repo/commits/main" --jq '.sha')
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the repository main branch.' }
}
if ($TargetCommit -notmatch '^[0-9a-fA-F]{40}$') {
    throw "Invalid target commit SHA: '$TargetCommit'"
}
& gh api "repos/$Repo/commits/$TargetCommit" --jq '.sha' *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Cannot access commit $TargetCommit in $Repo"
}

& gh release view $Tag --repo $Repo *> $null
if ($LASTEXITCODE -eq 0) {
    throw "Release '$Tag' already exists. Not publishing a duplicate."
}

Write-Host "Publishing $Tag to $Repo" -ForegroundColor Cyan
Write-Host "Source commit: $TargetCommit"
Write-Host "Asset: $Asset"
$Arguments = @('release', 'create', $Tag, $Asset, '--repo', $Repo,
    '--title', 'AffixLens v3.0.0 — Ebonhold V2', '--notes-file', $Notes,
    '--target', $TargetCommit)
if ($Prerelease) { $Arguments += '--prerelease' }
& gh @Arguments
if ($LASTEXITCODE -ne 0) { throw "GitHub release creation failed (exit code $LASTEXITCODE)." }
$Url = & gh release view $Tag --repo $Repo --json url --jq '.url'
if ($LASTEXITCODE -ne 0) { throw 'Release was created but its URL could not be retrieved.' }
Write-Host "Release published: $Url" -ForegroundColor Green
