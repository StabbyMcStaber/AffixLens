$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'Install GitHub CLI: winget install --id GitHub.cli --exact' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Install Git: winget install --id Git.Git --exact' }
gh auth status
if ($LASTEXITCODE -ne 0) { gh auth login --web --git-protocol https; if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication failed.' } }
Set-Location $PSScriptRoot
if (-not (Test-Path .git)) { git init -b main }
git add .
git commit -m 'Release AffixLens v2.0.0'
if ($LASTEXITCODE -ne 0) { throw 'Git commit failed; check git config user.name and user.email.' }
gh repo view StabbyMcStaber/AffixLens *> $null
if ($LASTEXITCODE -ne 0) { gh repo create StabbyMcStaber/AffixLens --public --source . --remote origin --push --description 'Project Ebonhold equipment affix labels and learned affix collection' }
else {
    if (-not (git remote get-url origin 2>$null)) { git remote add origin https://github.com/StabbyMcStaber/AffixLens.git }
    git push -u origin main
}
if ($LASTEXITCODE -ne 0) { throw 'Publishing source failed.' }
$releaseFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'AffixLens-v2.0.0.zip'
if (-not (Test-Path $releaseFile)) { throw "Missing release ZIP: $releaseFile" }
gh release create v2.0.0 $releaseFile --repo StabbyMcStaber/AffixLens --title 'AffixLens v2.0.0' --notes-file CHANGELOG.md
if ($LASTEXITCODE -ne 0) { throw 'Release creation failed.' }
Write-Host 'Published: https://github.com/StabbyMcStaber/AffixLens/releases/tag/v2.0.0'
