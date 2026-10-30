<#
.SYNOPSIS
    One-shot iOS build for Windows: trigger the GitHub Actions workflow and pull the IPA down.

.DESCRIPTION
    Windows cannot compile iOS apps locally, so the actual build runs on a GitHub
    macOS runner. This script hides the web UI: it triggers the workflow, waits
    for it, and drops the finished .ipa into ./dist.

    Requires the GitHub CLI:  winget install --id GitHub.cli
    Then authenticate once:  gh auth login

.EXAMPLE
    .\Scripts\build.ps1
    .\Scripts\build.ps1 -AutoCommit
#>

[CmdletBinding()]
param(
    [string]$WorkflowFile = "build-ipa.yml",
    [string]$ArtifactName = "PickupCode-ipa",
    [string]$OutputDir = "dist",
    [switch]$AutoCommit
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host "!! $msg" -ForegroundColor Yellow }
function Write-Ok([string]$msg)   { Write-Host "OK  $msg" -ForegroundColor Green }

# ---------------------------------------------------------------- prerequisites

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Warn "GitHub CLI (gh) is not installed."
    Write-Host ""
    Write-Host "  1. Install it:   winget install --id GitHub.cli"
    Write-Host "  2. Log in once:  gh auth login"
    Write-Host "  3. Re-run this script."
    exit 1
}

if (-not (Test-Path ".git")) {
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if (-not $repoRoot) {
        Write-Warn "This is not a git repository. Run 'git init' first."
        exit 1
    }
    Set-Location $repoRoot
}

$remoteUrl = git remote get-url origin 2>$null
if (-not $remoteUrl) {
    Write-Warn "No 'origin' remote, so there is nowhere to build."
    Write-Host ""
    Write-Host "  1. Create an empty repo on github.com"
    Write-Host "  2. git remote add origin https://github.com/<you>/<repo>.git"
    Write-Host "  3. git push -u origin main"
    exit 1
}

# ---------------------------------------------------------------- push local work

$dirty = git status --porcelain
if ($dirty) {
    Write-Warn "You have uncommitted changes. The CI builds from GitHub, not from your disk."
    $shouldCommit = $AutoCommit
    if (-not $shouldCommit) {
        $answer = Read-Host "Commit and push them now? [y/N]"
        $shouldCommit = ($answer -match '^[Yy]')
    }
    if ($shouldCommit) {
        Write-Step "Committing and pushing local changes"
        git add -A
        git commit -m "build: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        git push
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "git push failed. Fix it, then re-run."
            exit 1
        }
    } else {
        Write-Warn "Continuing without pushing. The build will use the last pushed commit."
    }
}

$branch = git branch --show-current
if (-not $branch) { $branch = "main" }

# ---------------------------------------------------------------- trigger

Write-Step "Triggering workflow '$WorkflowFile' on branch '$branch'"
gh workflow run $WorkflowFile --ref $branch
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Failed to trigger the workflow."
    Write-Host "Make sure the workflow file exists on this branch and the repo is reachable."
    exit 1
}

# GitHub needs a moment before the run shows up in the list
Start-Sleep -Seconds 6

$runId = $null
for ($attempt = 0; $attempt -lt 12; $attempt++) {
    $json = gh run list --workflow $WorkflowFile --branch $branch --limit 1 --json databaseId,status 2>$null
    if ($json) {
        $runs = $json | ConvertFrom-Json
        if ($runs -and @($runs).Count -gt 0) {
            $runId = $runs[0].databaseId
            break
        }
    }
    Start-Sleep -Seconds 3
}

if (-not $runId) {
    Write-Warn "Could not locate the triggered run."
    Write-Host "Check the Actions tab on GitHub, then download the artifact manually."
    exit 1
}

Write-Step "Watching run $runId (this takes a few minutes)"
gh run watch $runId --exit-status --interval 20
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Build failed."
    Write-Host ""
    Write-Host "  See the failing step:  gh run view $runId --log-failed"
    exit 1
}

# ---------------------------------------------------------------- download

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Write-Step "Downloading artifact '$ArtifactName' into $OutputDir"
gh run download $runId --name $ArtifactName --dir $OutputDir --skip-already-downloaded

$zipped = Join-Path $OutputDir "$ArtifactName.zip"
if (Test-Path $zipped) {
    Expand-Archive -Path $zipped -DestinationPath $OutputDir -Force
    Remove-Item $zipped -Force
}

$ipa = Get-ChildItem -Path $OutputDir -Filter *.ipa -Recurse | Select-Object -First 1
if (-not $ipa) {
    Write-Warn "No .ipa found in $OutputDir."
    exit 1
}

Write-Ok "IPA ready: $($ipa.FullName)"
Write-Host ""
Write-Host "Next: transfer it to your iPhone (AirDrop / iCloud Drive),"
Write-Host "then open it with TrollStore to install."
exit 0
