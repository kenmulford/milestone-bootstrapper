#!/usr/bin/env pwsh
#
# provision-branches.ps1 — provision the suite's branch model idempotently.
#
# What this does, in plain terms:
#   The `apply` and `update` verbs call this to guarantee the target repo's two
#   suite branches exist and the default-branch policy points at the protected
#   branch, so milestone-feeder and milestone-driver run with no further branch
#   setup. It creates the protected branch if missing, branches the integration
#   branch off it if missing, and sets the repo's default branch to the protected
#   branch if that policy is not already in place. It NEVER deletes a branch,
#   force-pushes, or resets an existing branch — a re-run on an already-correct
#   repo changes nothing (idempotent, adopt-or-init).
#
# Branch names are SOURCED, never chosen:
#   `integrationBranch` and `protectedBranch` are read from the target repo's
#   `.milestone-config/driver.json` (written by issue #8). The bootstrapper does
#   not invent or default these names — an absent file or empty key is a clear
#   precondition failure, never a guessed name. (Issue #10 Design; sibling shape
#   at milestone-driver/milestone-driver.json:1-2.)
#
# Order (BRIEF.md §"Sequencing hints" — "branch model" before protection/CI;
#   integration is branched FROM protected):
#   1. protected branch  (the base/root)
#   2. integration branch (created from protected when fresh)
#   3. default-branch policy -> protected
#
# Scope of this step (Issue #10 Design): ensure the two branches exist and set
#   the default-branch policy. It does NOT configure branch-protection rules
#   (no-direct-push / required PR / required status check) — that is a separate,
#   later step (issue #11) that depends on this one. BRIEF.md §"Job 2" lists
#   "Branch model" and "Branch protection" as two distinct bullets.
#
# Preconditions:
#   `gh` installed and authenticated, run inside a GitHub-connected working
#   directory, with a token that can create branches and change the default
#   branch (repo-admin). If a precondition is unmet, this names it and exits
#   non-zero before touching anything — never a silent failure (BRIEF.md
#   §"Constraints" line 82). Cross-platform companion: provision-branches.sh.
#
# Preview (`plan`): pass -DryRun to print the intended branch-model actions
#   (which branches it would create, the default-branch policy it would set)
#   without writing anything to the remote — the preview-then-execute split the
#   `plan` verb records into its provisioning plan (BRIEF.md §"The surface").
#
# Run it:  ./scripts/provision-branches.ps1 [-Repo /path/to/target] [-DryRun]
# Exit 0 = branches present and default-branch policy correct (or previewed).
# Exit 1 = precondition unmet / config missing / empty repo (nothing changed).
# Exit 2 = GitHub API failure mid-step (reports what was / was not done).

[CmdletBinding()]
param(
    [string]$Repo = '.',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# fail <msg> — precondition / config / empty-repo failure: nothing changed.
function Fail([string]$message) {
    [Console]::Error.WriteLine("milestone-bootstrapper: $message")
    exit 1
}

# ApiFail <msg> — a GitHub API operation failed mid-step. Reports what was and
# was not done; never deletes or force-pushes to recover. Exit 2 so the
# orchestrator can surface it distinctly from a precondition failure.
function ApiFail([string]$message) {
    [Console]::Error.WriteLine("milestone-bootstrapper: 🔴 $message")
    exit 2
}

# --- Preconditions (surface the unmet one by name; change nothing) -----------
# `gh` reports failure via a non-zero exit code, not a thrown exception, so each
# check inspects $LASTEXITCODE. A missing `gh` raises a command-not-found error,
# caught and reported as the installation precondition.

try { gh --version *> $null } catch {
    Fail "GitHub CLI ('gh') is not installed or not on PATH. Install it from https://cli.github.com, then re-run."
}

if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Fail "'jq' is required but not found on PATH. Install jq, then re-run."
}

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "GitHub CLI is not authenticated. Run 'gh auth login' (with a token that can create branches and set the default branch), then re-run."
}

gh repo view *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "the working directory is not connected to a GitHub repository (or the repo is unreachable). Run this inside a repo with a GitHub remote, then re-run."
}

# --- Read the branch names from the target repo's driver.json ----------------
# Names are sourced, never chosen: an absent file or empty key is a precondition
# failure, never a guessed name (Issue #10 Design).

$configFile = Join-Path (Join-Path ($Repo.TrimEnd('/','\')) '.milestone-config') 'driver.json'

if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
    Fail "config not found: $configFile. Run the config writer (issue #8) first so integrationBranch / protectedBranch are defined; no branch created, no policy changed."
}

jq -e . $configFile *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "config is not valid JSON: $configFile. Fix it, then re-run; no branch created, no policy changed."
}

# jq '// empty' collapses an absent key, JSON null, AND an empty string to the
# same "missing" signal — so each is reported by name with the file path.
$protectedBranch   = (jq -r '.protectedBranch // empty'   $configFile)
$integrationBranch = (jq -r '.integrationBranch // empty' $configFile)

if ([string]::IsNullOrEmpty($protectedBranch)) {
    Fail "key 'protectedBranch' is missing or empty in $configFile. The branch model cannot be provisioned without it; no branch created, no policy changed."
}
if ([string]::IsNullOrEmpty($integrationBranch)) {
    Fail "key 'integrationBranch' is missing or empty in $configFile. The branch model cannot be provisioned without it; no branch created, no policy changed."
}

# --- Resolve owner/repo once (all branch + ref ops are keyed on it) -----------
$slug = (gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($slug)) {
    ApiFail "could not resolve the GitHub repository (owner/name). Nothing changed."
}

# Branch-Exists <name> — $true if the branch exists on the remote, else $false.
# The branches endpoint returns the branch object (exit 0) or HTTP 404 (exit 1).
function Test-Branch([string]$name) {
    gh api "repos/$slug/branches/$name" *> $null
    return ($LASTEXITCODE -eq 0)
}

# Get-BaseSha — the commit SHA to branch the protected branch FROM when it is
# missing. Prefers the protected branch ref itself (no-op when it exists), then
# the repo's reported default branch. Returns '' for an empty repo (no commit/ref
# yet) — the caller turns '' into the empty-repo precondition message.
function Get-BaseSha {
    $sha = (gh api "repos/$slug/git/ref/heads/$protectedBranch" --jq '.object.sha' 2>$null)
    if ($LASTEXITCODE -ne 0) { $sha = '' }
    if ([string]::IsNullOrEmpty($sha)) {
        $defaultBranch = (gh api "repos/$slug" --jq '.default_branch' 2>$null)
        if ($LASTEXITCODE -ne 0) { $defaultBranch = '' }
        if (-not [string]::IsNullOrEmpty($defaultBranch)) {
            $sha = (gh api "repos/$slug/git/ref/heads/$defaultBranch" --jq '.object.sha' 2>$null)
            if ($LASTEXITCODE -ne 0) { $sha = '' }
        }
    }
    if ($null -eq $sha) { return '' }
    return $sha
}

# New-Branch <name> <sha> — create a ref non-destructively. The git/refs POST
# only ever CREATES (it 422s if the ref already exists); it can never overwrite
# or force-update, so there is no destructive path here. Returns $true on success.
function New-Branch([string]$name, [string]$sha) {
    gh api "repos/$slug/git/refs" -f "ref=refs/heads/$name" -f "sha=$sha" *> $null
    return ($LASTEXITCODE -eq 0)
}

# --- Inspect current state (adopt-or-init: act only on what is missing) -------
# Wrapped as a function (not a one-shot block) so the read-back retry below can
# re-inspect actual remote state before its one re-attempt (issue #109).
function Update-State {
    $script:currentDefault = (gh api "repos/$slug" --jq '.default_branch' 2>$null)
    if ($LASTEXITCODE -ne 0) { $script:currentDefault = '' }

    $script:protectedPresent   = Test-Branch $protectedBranch
    $script:integrationPresent = Test-Branch $integrationBranch

    # The default-branch placeholder of an empty repo (e.g. "main") is NOT a
    # real ref, so treat the policy as "already correct" only when the
    # protected branch actually exists. Otherwise we'd report a no-op while no
    # branch exists.
    $script:defaultCorrect = ($script:currentDefault -eq $protectedBranch) -and $script:protectedPresent
}

Update-State

# --- Plan the actions (shared by -DryRun preview and the executor) -----------
$planProtected = if ($protectedPresent) { 'exists (adopt)' } else { 'CREATE from base commit' }
$planIntegration = if ($integrationPresent) { 'exists (adopt)' } else { "CREATE from $protectedBranch" }
$planDefault = if ($defaultCorrect) {
    "already $protectedBranch (no-op)"
} else {
    $cur = if ([string]::IsNullOrEmpty($currentDefault)) { '<none>' } else { $currentDefault }
    "SET to $protectedBranch (currently: $cur)"
}

function Write-Plan {
    Write-Output ("  protected   ({0}): {1}" -f $protectedBranch, $planProtected)
    Write-Output ("  integration ({0}): {1}" -f $integrationBranch, $planIntegration)
    Write-Output ("  default-branch policy: {0}" -f $planDefault)
}

if ($DryRun) {
    Write-Output "milestone-bootstrapper: branch-model plan for $slug (preview — nothing written):"
    Write-Plan
    # Empty-repo preview: surface that a base commit is required, but write nothing.
    if ((-not $protectedPresent) -and [string]::IsNullOrEmpty((Get-BaseSha))) {
        [Console]::Error.WriteLine("milestone-bootstrapper: 🔴 note: the repository has no commit yet; an initial commit/ref is required before the protected branch can be created.")
    }
    exit 0
}

# --- Execute (idempotent; create only what is missing) -----------------------
# $changed is initialized once, OUTSIDE the function, and only ever set to
# $true (never reset to $false) — a second call from the read-back retry below
# must not erase the fact that the first pass already wrote something.
$changed = $false

function Invoke-BranchModel {
    # 1. Protected branch — the base/root. Created from a base commit when missing.
    if (-not $script:protectedPresent) {
        $sha = Get-BaseSha
        if ([string]::IsNullOrEmpty($sha)) {
            Fail "🔴 cannot create the protected branch '$protectedBranch': the repository has no commit yet. Make an initial commit (e.g. 'git commit --allow-empty' then push), then re-run. Nothing changed."
        }
        if (-not (New-Branch $protectedBranch $sha)) {
            ApiFail "failed to create the protected branch '$protectedBranch'. Nothing was deleted or force-pushed; no further step ran. Re-run after resolving the error."
        }
        Write-Output "milestone-bootstrapper: created protected branch '$protectedBranch'."
        $script:protectedPresent = $true
        $script:changed = $true
    }

    # 2. Integration branch — branched FROM the (now-present) protected branch.
    if (-not $script:integrationPresent) {
        $sha = (gh api "repos/$slug/git/ref/heads/$protectedBranch" --jq '.object.sha' 2>$null)
        if ($LASTEXITCODE -ne 0) { $sha = '' }
        if ([string]::IsNullOrEmpty($sha)) {
            ApiFail "cannot branch '$integrationBranch' from '$protectedBranch': the protected branch ref could not be resolved. The protected branch was left in place; no force-push, no deletion. Re-run after resolving the error."
        }
        if (-not (New-Branch $integrationBranch $sha)) {
            ApiFail "failed to create the integration branch '$integrationBranch' from '$protectedBranch'. The protected branch was left in place; no force-push, no deletion. Re-run after resolving the error."
        }
        Write-Output "milestone-bootstrapper: created integration branch '$integrationBranch' from '$protectedBranch'."
        $script:integrationPresent = $true
        $script:changed = $true
    }

    # 3. Default-branch policy — set to protected only when it does not already match.
    if (-not $script:defaultCorrect) {
        gh repo edit $slug --default-branch $protectedBranch *> $null
        if ($LASTEXITCODE -ne 0) {
            ApiFail "failed to set the default branch to '$protectedBranch'. Branches already created were left in place; no force-push, no deletion. Re-run after resolving the error."
        }
        Write-Output "milestone-bootstrapper: set default branch to '$protectedBranch'."
        $script:changed = $true
    }
}

Invoke-BranchModel

# --- Read-back verify + one bounded retry (issue #109) -----------------------
# GitHub's API can accept a branch/ref write (exit 0) that doesn't durably
# stick (eventual consistency) — only run this when this pass actually wrote
# something ($changed); an all-already-correct run made no write this pass, so
# there is nothing new to verify (mirrors provision-protection.ps1's existing
# no-op-skips-read-back shape). Re-checks the exact three facts just asserted:
# both branches exist and the default branch is the protected branch. On any
# mismatch, refresh state and retry the write exactly ONCE before halting —
# never a second retry (`.project/design-philosophy.md#Error & failure
# philosophy`).
function Test-BranchModel {  # returns an array of diverged-check descriptions (empty if all match)
    $diverged = @()
    gh api "repos/$slug/branches/$protectedBranch" *> $null
    if ($LASTEXITCODE -ne 0) { $diverged += "protected branch '$protectedBranch' not found on read-back" }
    gh api "repos/$slug/branches/$integrationBranch" *> $null
    if ($LASTEXITCODE -ne 0) { $diverged += "integration branch '$integrationBranch' not found on read-back" }
    $rbDefault = (gh api "repos/$slug" --jq '.default_branch' 2>$null)
    if ($LASTEXITCODE -ne 0) { $rbDefault = '' }
    if ($rbDefault -ne $protectedBranch) {
        $shown = if ([string]::IsNullOrEmpty($rbDefault)) { '<none>' } else { $rbDefault }
        $diverged += "default branch is '$shown', expected '$protectedBranch' on read-back"
    }
    return $diverged
}

if ($changed) {
    $diverged = @(Test-BranchModel)
    if ($diverged.Count -gt 0) {
        Write-Output "milestone-bootstrapper: branch-model read-back drift for ${slug} — retrying once:"
        foreach ($d in $diverged) { Write-Output "milestone-bootstrapper:   $d" }
        Update-State
        Invoke-BranchModel
        $diverged = @(Test-BranchModel)
        if ($diverged.Count -gt 0) {
            ApiFail "branch-model read-back still diverges after one retry for ${slug}: $($diverged -join '; '). What was already created was left in place; re-run after resolving the drift."
        }
    }
}

if (-not $changed) {
    Write-Output "milestone-bootstrapper: branch model already correct for $slug (no change)."
} else {
    Write-Output "milestone-bootstrapper: branch model provisioned for $slug."
}
exit 0
