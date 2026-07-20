#!/usr/bin/env pwsh
#
# provision-protection.ps1 — assert the suite's branch-protection floor idempotently.
#
# What this does, in plain terms:
#   The `apply` and `update` verbs call this to guarantee a target repo branch
#   carries the suite's server-side safety floor, so the milestone-driver gates
#   hold even when a local hook is bypassed or absent. It asserts, via the GitHub
#   API, that on the target branch: direct pushes are blocked, a pull request is
#   required before merge, and the CI status checks #11 emits ('unit-tests' and
#   'preflight') must pass. Re-asserting the same protection is a safe no-op, so
#   `apply` and `update` may run it repeatedly. It NEVER weakens or removes
#   protection it did not author — it GETs the existing protection first and
#   merges the floor in per field, taking the STRONGER value, so a re-apply onto
#   an already-hardened repo only asserts the floor or reconciles drift UP to it.
#   A stronger-than-floor setting (an extra required approval, a push-restriction
#   allowlist, strict-up-to-date) is preserved, never reconciled DOWN. That holds
#   for BOTH floors: the integration floor below is create-only or reconcile-UP —
#   never a downgrade — so it REFUSES rather than clear an existing
#   `enforce_admins: true`, and there is deliberately no -Force / downgrade path.
#
# Two floors — `-Floor release` (default) and `-Floor integration`:
#   The two protected targets need different admin-override semantics, so the
#   floor is a parameter, not a second script (issue #93 decision b).
#     release     — target `.protectedBranch`, enforce_admins=TRUE. Release-grade:
#                   admins cannot bypass, the key hardening signal. This is the
#                   DEFAULT and the pre-#93 behavior, byte-for-byte.
#     integration — target `.integrationBranch`, enforce_admins=FALSE. The driver
#                   opens a PR into this branch per issue and auto-merges on green;
#                   enforce_admins=true there DEADLOCKS it (a transient or broken
#                   required check wedges the branch and no admin can override, so
#                   nothing — not even a baseline PR — can land). The gate is still
#                   real: PR required + required status checks; admins may override
#                   for baselines and transient CI breaks (issue #93 Observed).
#   The integration floor is OPT-IN: it runs only when the target repo's
#   .milestone-config/driver.json carries `integrationProtection: "floor"`. Absent
#   or `"none"` (the default) prints a not-opted-in line and exits 0 having changed
#   nothing — a repo that does not opt in sees zero behavioral change.
#
# Why server-side, not only the hooks:
#   milestone-driver's no-push / no-pr-to-protected hooks are LOCAL gates; GitHub
#   branch protection is the authoritative server-side backstop behind them. A
#   bypassed or missing local hook still hits this floor. (Issue #12 Design;
#   milestone-driver hooks/no-push.sh, hooks/no-pr-to-protected.sh.)
#
# What it asserts (the suite's canonical lockdown floor — "feeder-style").
# Each field is a FLOOR: the merge keeps whichever of existing / floor is stronger,
# so on a fresh repo the result is exactly this floor, and on an already-hardened
# repo a stronger setting survives untouched:
#   - required_pull_request_reviews present with required_approving_review_count =
#       MAX(existing, 0). The floor REQUIRES a PR before merge but imposes no
#       human-approval gate (floor 0); an existing 2-approval rule is NOT lowered
#       (a review requirement is optional and is not imposed; BRIEF.md:50).
#   - required_status_checks.contexts = UNION(existing contexts, the #11 CI job
#       names 'unit-tests'/'preflight') — the floor contexts are added, any
#       existing extra contexts are kept. strict = (existing.strict OR false) =
#       existing is preserved (the floor never turns OFF require-up-to-date).
#   - enforce_admins = the FLOOR'S value: true for `-Floor release` (existing
#       cannot exceed true — admins cannot bypass, the key hardening signal);
#       false for `-Floor integration` (admins may override, so a transient CI
#       break never deadlocks the branch the driver merges into). The integration
#       floor is create-only / reconcile-UP: it never clears an existing
#       enforce_admins:true — it refuses (see "Refuse" below).
#   - allow_force_pushes=false, allow_deletions=false (floor; false is the
#       strongest value, so an existing false is preserved).
#   - restrictions = the existing push-restriction allowlist, PRESERVED (the floor
#       adds none; if an allowlist exists it is kept, never nulled). On a fresh
#       repo with no allowlist this is null.
#
# The required status-check contexts are SOURCED, never guessed:
#   the contexts are the stable job names #11 registers. They are read from the
#   emitted .github/workflows/ci.yml when present; absent that file, the canonical
#   contract names ('unit-tests' / 'preflight') are used — the exact strings #11's
#   emit-ci-workflow.ps1 hard-codes (emit-ci-workflow.sh:84-85,214-224) and shares
#   with #12 as a contract. If neither source yields any context, this fails with
#   a clear message rather than registering an empty or guessed context.
#
# The protection target is SOURCED, never chosen:
#   `-Floor release` reads `protectedBranch`; `-Floor integration` reads
#   `integrationBranch` — both from the target repo's .milestone-config/driver.json
#   (written by issue #8). An absent file or empty key is a clear precondition
#   failure, never a guessed name. (Issue #12 Design; sibling shape at
#   scripts/provision-branches.ps1:96-121.)
#
# The integration floor's opt-in is SOURCED too:
#   `integrationProtection` in the same driver.json, an enum of "none" | "floor"
#   defaulting to "none" (this repo's SPEC.md §6.1). Absent or "none" => the run
#   is a reported no-op (exit 0, nothing changed). "floor" => assert. Any other
#   value is a precondition failure naming the enum, never a guessed intent. This
#   self-gate is deliberately redundant with `apply` skipping the invocation:
#   two independent gates, neither of which can protect a branch the user did not
#   opt into.
#
# Refuse (integration floor only — the never-weaken invariant, exit 1):
#   If the integration target ALREADY carries `enforce_admins: true` (a human
#   previously applied the release floor there), this changes NOTHING and exits 1
#   with a 🔴 message naming the deadlock and printing the exact
#   `gh api -X DELETE repos/<slug>/branches/<target>/protection/enforce_admins`
#   command to clear it. Clearing existing protection is the one destructive act,
#   and a human performs it knowingly — this script has NO -Force, no
#   -AllowDowngrade, and no other downgrade path (issue #93 decision c). The
#   check runs BEFORE the merge, so a -DryRun preview surfaces the deadlock too.
#
# Preconditions:
#   `gh` installed and authenticated, `jq` installed, run inside a
#   GitHub-connected working directory, with a token that holds REPO-ADMIN on the
#   target repo. Branch protection is a repository-administration write, so this
#   probes admin permission BEFORE any write and hard-stops with a clear,
#   actionable message on insufficient scope (the GitHub API returns 403 without
#   it) — never a silent failure (BRIEF.md:82). It also requires the protected
#   branch to already exist (#10); an absent branch is a named precondition
#   failure, not a write against a non-existent ref. Companion: provision-protection.sh.
#
# Preview (`plan`): pass -DryRun to print the EXACT protection PUT body it would
#   send (the resolved contexts and every setting) without writing anything to the
#   remote — the preview-then-execute split the `plan` verb records (BRIEF.md
#   §"The surface"). The dry-run still runs the read-only preconditions so the
#   preview reflects what an `apply` would actually do.
#
# Run it:  ./scripts/provision-protection.ps1 [-Repo /path/to/target] [-DryRun] `
#            [-Floor release|integration]
# Exit 0 = protection asserted / already correct (or previewed) — or the
#          integration floor was not opted in (reported no-op, nothing changed).
# Exit 1 = precondition unmet / config missing / unknown -Floor or
#          integrationProtection value / repo-admin scope absent / branch or CI
#          contexts missing / integration floor REFUSED on an enforce_admins:true
#          branch (nothing changed).
# Exit 2 = GitHub API failure mid-step (reports the failing endpoint; nothing weakened).

[CmdletBinding()]
param(
    [string]$Repo = '.',
    [switch]$DryRun,
    # The floor defaults to `release` — the pre-#93 behavior, byte-for-byte.
    [string]$Floor = 'release'
)

$ErrorActionPreference = 'Stop'

# Fail <msg> — precondition / config / missing-prerequisite failure: nothing changed.
function Fail([string]$message) {
    [Console]::Error.WriteLine("milestone-bootstrapper: $message")
    exit 1
}

# ApiFail <msg> — a GitHub API operation failed mid-step. Reports the failing
# endpoint; never weakens or removes protection to recover. Exit 2 so the
# orchestrator can surface it distinctly from a precondition failure.
function ApiFail([string]$message) {
    [Console]::Error.WriteLine("milestone-bootstrapper: 🔴 $message")
    exit 2
}

# --- Validate the floor enum (reject-unknown; mirrors the -Stack precedent at
# scripts/write-driver-config.ps1:308-333) --------------------------------------
if ($Floor -ne 'release' -and $Floor -ne 'integration') {
    Fail "-Floor must be one of release|integration (got: $Floor). No protection changed."
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
    Fail "GitHub CLI is not authenticated. Run 'gh auth login' (with a token that holds repo-admin on the target repo), then re-run."
}

gh repo view *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "the working directory is not connected to a GitHub repository (or the repo is unreachable). Run this inside a repo with a GitHub remote, then re-run."
}

# --- Read the target branch (and the integration opt-in) from driver.json ------
# The target is sourced, never chosen: an absent file or empty key is a
# precondition failure, never a guessed name (Issue #12 Design).

$configFile = Join-Path (Join-Path ($Repo.TrimEnd('/','\')) '.milestone-config') 'driver.json'

# WHICH key the caller must have defined is floor-dependent: `release` reads
# protectedBranch, `integration` reads integrationBranch. Naming the wrong one
# sends the user to define a key this run never reads. Resolved HERE — before the
# file is opened — so the not-found message can name the right one. `-Floor
# release` substitutes `protectedBranch`, so that rendering stays byte-identical
# to pre-#93.
$targetKey = if ($Floor -eq 'release') { 'protectedBranch' } else { 'integrationBranch' }

if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
    Fail "config not found: $configFile. Run the config writer (issue #8) first so $targetKey is defined; no protection changed."
}

jq -e . $configFile *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "config is not valid JSON: $configFile. Fix it, then re-run; no protection changed."
}

# $targetBranch / $targetLabel / $enforceAdmins / $adminsNote /
# $noopAdminsSuffix are the only floor-dependent values; every downstream site
# reads them, so `-Floor release` resolves them to exactly the pre-#93 constants
# and renders byte-identically.
#
# $noopAdminsSuffix exists because the write path states the admins posture
# ($adminsNote) but the already-at-floor no-op path did not — so an idempotent
# integration re-run never repeated that admins may override. It is EMPTY under
# `release` on purpose: appending the note there would change that path's
# long-standing output, and the release rendering is byte-frozen.
if ($Floor -eq 'release') {
    $targetBranch = (jq -r '.protectedBranch // empty' $configFile)
    if ([string]::IsNullOrEmpty($targetBranch)) {
        Fail "key 'protectedBranch' is missing or empty in $configFile. Branch protection cannot be asserted without it; no protection changed."
    }
    $targetLabel = 'protected'
    $enforceAdmins = 'true'
    $adminsNote = 'enforce_admins on'
    $noopAdminsSuffix = ''
} else {
    # Opt-in gate FIRST: absent / "none" is the default and a reported no-op, so a
    # repo that never opted in cannot have its integration branch protected here.
    $integrationProtection = (jq -r '.integrationProtection // empty' $configFile)
    if ([string]::IsNullOrEmpty($integrationProtection) -or $integrationProtection -eq 'none') {
        Write-Output "milestone-bootstrapper: integration protection is not opted in ('integrationProtection' absent or `"none`" in $configFile) — nothing changed."
        exit 0
    }
    if ($integrationProtection -ne 'floor') {
        Fail "key 'integrationProtection' must be one of none|floor in $configFile (got: $integrationProtection). No protection changed."
    }
    $targetBranch = (jq -r '.integrationBranch // empty' $configFile)
    if ([string]::IsNullOrEmpty($targetBranch)) {
        Fail "key 'integrationBranch' is missing or empty in $configFile. Integration-branch protection cannot be asserted without it; no protection changed."
    }
    $targetLabel = 'integration'
    $enforceAdmins = 'false'
    $adminsNote = 'enforce_admins off (admins may override — integration floor)'
    $noopAdminsSuffix = "; $adminsNote"
}

# --- Resolve the required status-check contexts (#11's CI job names) ----------
# Sourced, never guessed. Prefer the emitted ci.yml's job names; absent that file,
# fall back to the contract names #11 hard-codes. Either way the contexts are the
# stable strings #11/#12 share — never an empty or invented context.
#
# ci.yml is emitted by emit-ci-workflow, which ALWAYS writes both the 'unit-tests'
# and 'preflight' jobs (a missing command becomes a [TBD] step that fails loudly;
# the job name — and thus the context — never drifts). So the job keys under
# `jobs:` are the authoritative contexts when the file exists.
$canonicalContexts = @('unit-tests', 'preflight')
$ciWorkflow = Join-Path (Join-Path (Join-Path ($Repo.TrimEnd('/','\')) '.github') 'workflows') 'ci.yml'

$contexts = @()
if (Test-Path -LiteralPath $ciWorkflow -PathType Leaf) {
    # Read the keys directly under the top-level `jobs:` mapping. The emitter writes
    # each job as a 2-space-indented `<name>:` line inside the `jobs:` block; parse
    # exactly that shape and stop at the next top-level key.
    $inJobs = $false
    foreach ($line in (Get-Content -LiteralPath $ciWorkflow)) {
        if ($line -match '^jobs:\s*$') { $inJobs = $true; continue }
        if ($inJobs -and $line -match '^\S') { $inJobs = $false }
        if ($inJobs -and ($line -match '^  ([A-Za-z0-9_.-]+):\s*$')) {
            $contexts += $Matches[1]
        }
    }
    if ($contexts.Count -eq 0) {
        Fail "🔴 found $ciWorkflow but could not read any CI job name from its 'jobs:' block. The required status-check context is the #11 CI job name; re-emit the CI workflow (issue #11) and re-run rather than guessing a context. No protection changed."
    }
} else {
    # No emitted workflow yet: use the contract names #11/#12 share verbatim.
    $contexts = $canonicalContexts
}

# --- Resolve owner/repo once (all protection ops are keyed on it) -------------
$slug = (gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($slug)) {
    ApiFail "could not resolve the GitHub repository (owner/name). Nothing changed."
}

# --- repo-admin precondition (clear message, never silent) -------------------
# Branch protection is a repository-administration write; without repo-admin the
# protection API returns 403. Probe the authenticated user's permission with a
# READ-only call BEFORE any write and hard-stop on insufficient scope (BRIEF.md:82).
$admin = (gh api "repos/$slug" --jq '.permissions.admin' 2>$null)
if ($LASTEXITCODE -ne 0) { $admin = '' }
if ($admin -ne 'true') {
    Fail "🔴 branch protection requires repo-admin on '$slug', but the authenticated token does not hold it (the protection API returns 403 without it). Re-authenticate with an admin token — e.g. 'gh auth login' as a repo admin, or 'gh auth refresh -h github.com -s admin:org,repo' — then re-run. No protection was written."
}

# --- Missing-prerequisite edge: the target branch must already exist (#10) -----
gh api "repos/$slug/branches/$targetBranch" *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "🔴 the $targetLabel branch '$targetBranch' does not exist on '$slug' yet. Provision the branch model first (issue #10 / provision-branches), then re-run — protection is not asserted against a non-existent branch. No protection changed."
}

# --- Read current protection FIRST (the merge reads from it; absence is fine) -
# A non-weakening floor cannot be a context-free declarative PUT: a full-object
# PUT of the floor alone would reconcile a STRONGER pre-existing setting DOWN
# (restrictions:null would wipe an allowlist, 0 approvals would lower a 2-approval
# rule, strict:false would turn off require-up-to-date). So we GET the existing
# protection and merge the floor INTO it, per field, taking the stronger value.
# A 404 here means "no protection yet" — a normal first-apply state, not an error;
# $current is then 'null' and the merge collapses to exactly the floor. This GET
# is read-only, so -DryRun runs it too and its preview reflects the true merge.
#
# gh writes multi-line JSON, which PowerShell captures as a string array; join it
# back to one string so jq receives a single document (jq is whitespace-
# insensitive, so this yields byte-identical output to the bash twin).
$current = (gh api "repos/$slug/branches/$targetBranch/protection" 2>$null) -join "`n"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($current)) { $current = 'null' }

# --- REFUSE: the integration floor never weakens an existing enforce_admins ----
# The integration floor's enforce_admins is FALSE, so asserting it onto a branch
# that already carries enforce_admins:true would reconcile a stronger pre-existing
# setting DOWN — precisely what the never-weaken invariant (header) forbids. The
# floor is therefore create-only or reconcile-UP: on this one state it changes
# NOTHING and exits 1, printing the exact command for the human to clear it
# knowingly. There is deliberately no -Force / -AllowDowngrade path (issue #93
# decision c). Placed BEFORE the merge — and so before the -DryRun print — so a
# `plan` preview surfaces the deadlock instead of previewing an impossible write.
if ($Floor -eq 'integration' -and $current -ne 'null') {
    $currentAdmins = (($current | jq -r '.enforce_admins.enabled // false') -join "`n")
    if ($currentAdmins -eq 'true') {
        [Console]::Error.WriteLine("milestone-bootstrapper: 🔴 refusing to apply the integration floor to '$targetBranch' on '$slug': that branch already carries enforce_admins:true (the release-grade floor). Leaving it in place DEADLOCKS the integration branch — admins cannot override a failing, pending, or broken required check, so the driver's PRs and any baseline PR can never land. Nothing was changed: this script never weakens protection it did not author, and it has no -Force path.")
        [Console]::Error.WriteLine("milestone-bootstrapper: clearing it is the one destructive act, so a human performs it knowingly. To clear it, run:")
        [Console]::Error.WriteLine("  gh api -X DELETE repos/$slug/branches/$targetBranch/protection/enforce_admins")
        [Console]::Error.WriteLine("milestone-bootstrapper: then re-run this script to assert the integration floor.")
        [Console]::Error.WriteLine("milestone-bootstrapper: Or, to leave that protection in place, set integrationProtection: `"none`" in driver.json and this floor will not be asserted.")
        exit 1
    }
}

# --- Build the EXACT protection PUT body by MERGING existing-with-floor -------
# Four fields are REQUIRED by the API (each may be null): required_status_checks,
# enforce_admins, required_pull_request_reviews, restrictions. The PUT uses bare
# booleans (the GET response wraps them as {"enabled": ...}); the merge reads the
# wrapped GET shape and emits this flat plan shape. Per field, STRONGER wins:
#   - required_status_checks.contexts = UNION(existing, <#11 job names>)  (add the
#       floor contexts, keep existing extras); strict = existing OR false (preserve
#       an existing require-up-to-date, never turn it off).
#   - required_pull_request_reviews.required_approving_review_count = MAX(existing,
#       0)  (PR required; never lower an existing approval requirement).
#   - enforce_admins = $enforceAdmins, the FLOOR'S value (release true /
#       integration false) · allow_force_pushes=false · allow_deletions=false
#       (false is strongest; an existing false is preserved).
#   - restrictions = the existing allowlist mapped back to the PUT shape (user
#       logins / team slugs / app slugs), PRESERVED; null only when none exists.
# This jq program is shared byte-for-byte with provision-protection.sh, so both
# emit an identical PUT body from identical inputs. $contextsJson is joined to one
# line so it is a single --argjson argument.
$contextsJson = (($contexts | jq -R . | jq -s .) -join "`n")
$mergeFilter = '. as $cur | {
  required_status_checks: {
    strict: (($cur.required_status_checks.strict) // false),
    contexts: ((($cur.required_status_checks.contexts) // []) + $contexts | unique)
  },
  enforce_admins: $enforceAdmins,
  required_pull_request_reviews: {
    required_approving_review_count: ([ (($cur.required_pull_request_reviews.required_approving_review_count) // 0), 0 ] | max)
  },
  restrictions: (
    if ($cur.restrictions) == null then null
    else {
      users: [ ($cur.restrictions.users // [])[] | .login ],
      teams: [ ($cur.restrictions.teams // [])[] | .slug ],
      apps:  [ ($cur.restrictions.apps  // [])[] | .slug ]
    }
    end
  ),
  allow_force_pushes: false,
  allow_deletions: false
}'
$putBody = (($current | jq --argjson contexts $contextsJson --argjson enforceAdmins $enforceAdmins $mergeFilter) -join "`n")

# Normalize the existing protection into the same flat PUT shape (no floor added,
# no UNION/MAX) so an exact match against the merged target means "already at or
# above the floor" — a true no-op. The two filters differ ONLY in that the merge
# unions the floor contexts and floors the approval count; when the existing
# state already meets the floor, that addition is empty and the shapes are equal.
# enforce_admins is emitted as the FLOOR'S value here (structurally hardcoded, not
# read from $cur, exactly as before) — substituting the same $enforceAdmins keeps
# release semantics byte-identical while making the integration comparison
# meaningful: the only enforce_admins state that reaches this line at the
# integration floor is `false`, since `true` already refused above.
$normalizeFilter = '. as $cur | {
  required_status_checks: {
    strict: (($cur.required_status_checks.strict) // false),
    contexts: ((($cur.required_status_checks.contexts) // []) | unique)
  },
  enforce_admins: $enforceAdmins,
  required_pull_request_reviews: {
    required_approving_review_count: (($cur.required_pull_request_reviews.required_approving_review_count) // 0)
  },
  restrictions: (
    if ($cur.restrictions) == null then null
    else {
      users: [ ($cur.restrictions.users // [])[] | .login ],
      teams: [ ($cur.restrictions.teams // [])[] | .slug ],
      apps:  [ ($cur.restrictions.apps  // [])[] | .slug ]
    }
    end
  ),
  allow_force_pushes: false,
  allow_deletions: false
}'

# The contexts the merged PUT actually carries (UNION result), for display.
$contextsDisplay = (($putBody | jq -r '.required_status_checks.contexts | join(", ")') -join "`n")

# --- Preview (-DryRun): print the exact MERGED PUT body; write nothing --------
if ($DryRun) {
    Write-Output "milestone-bootstrapper: branch-protection plan for $slug branch '$targetBranch' (preview — nothing written):"
    Write-Output "  required status checks: $contextsDisplay"
    Write-Output "  PUT repos/$slug/branches/$targetBranch/protection with body:"
    Write-Output $putBody
    exit 0
}

# --- No-op when already at-or-above the floor; else reconcile UP --------------
# Compare the existing state (normalized) to the merged target. Equal means the
# merge added nothing — the repo is already at or above the floor, so writing
# would be a pointless re-PUT. (On a fresh repo $current is 'null', so the
# normalized existing differs from the floor target and we proceed to write.)
#
# BUG-1 NOTE: both jq outputs are captured as string ARRAYS by PowerShell; a bare
# ($a -eq $b) on arrays does COLLECTION FILTERING, not boolean equality, and never
# detects the no-op. Force a scalar string compare (join the lines, then
# [string]::Equals) so this matches the bash twin's [ "$NORM" = "$PUT" ] exactly.
$normCurrent = (($current | jq --argjson enforceAdmins $enforceAdmins $normalizeFilter) -join "`n")
if ([string]::Equals($normCurrent, $putBody)) {
    Write-Output "milestone-bootstrapper: branch protection already meets the suite floor on $slug branch '$targetBranch' (no change)."
    Write-Output "milestone-bootstrapper: required status checks: $contextsDisplay$noopAdminsSuffix."
    exit 0
}

# --- Assert / reconcile the protection (merged PUT — never weakens) -----------
# The PUT is existing-merged-with-floor: a re-apply onto an at-or-above-floor repo
# is a no-op (handled above), and a reconcile pulls only the BELOW-floor fields UP
# while preserving every stronger pre-existing rule (extra contexts, extra
# approvals, an allowlist, strict-up-to-date).
if ($current -ne 'null') {
    Write-Output "milestone-bootstrapper: branch protection on '$targetBranch' is below the suite floor — reconciling UP (stronger existing settings are preserved)."
}

# Invoke-ProtectionPut — issues the PUT asserted above; callable more than
# once (the retry below re-invokes it verbatim against the same, already-
# computed $putBody). Returns $true on success.
function Invoke-ProtectionPut {
    $putBody | gh api -X PUT "repos/$slug/branches/$targetBranch/protection" --input - *> $null
    return ($LASTEXITCODE -eq 0)
}

# Test-ProtectionReadBack — the pre-existing acceptance check (same pattern): GETs
# current protection and confirms all three floors (PR required, enforce_admins,
# status-check contexts present). enforce_admins is asserted EQUAL TO THE FLOOR'S
# value ($enforceAdmins) rather than hardcoded 'true', so release still verifies
# `true` and integration verifies the `false` it just wrote — an assertion that
# would otherwise fail on every integration run. Sets $script:prRequired/
# $script:adminsEnforced/$script:hasContexts for the caller's message; returns
# $false on a failed GET or a floor not holding.
function Test-ProtectionReadBack {
    $verify = (gh api "repos/$slug/branches/$targetBranch/protection" 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($verify)) { return $false }
    $script:prRequired = ($verify | jq -r 'if .required_pull_request_reviews == null then "no" else "yes" end')
    $script:adminsEnforced = ($verify | jq -r '.enforce_admins.enabled // false')
    $script:hasContexts = ($verify | jq -r '(.required_status_checks.contexts // []) | length')
    return (($script:prRequired -eq 'yes') -and ($script:adminsEnforced -eq $enforceAdmins) -and ([int]$script:hasContexts -ne 0))
}

if (-not (Invoke-ProtectionPut)) {
    ApiFail "failed to assert branch protection on '$slug' branch '$targetBranch' (PUT repos/$slug/branches/$targetBranch/protection). No protection was weakened or removed. Re-run after resolving the error (a 403 here means the token lacks repo-admin)."
}

# --- Read back and verify the floor landed, with one bounded retry (issue #109) -
# GitHub's API can accept the PUT above (exit 0) without the floor durably
# sticking (eventual consistency) — this is the existing acceptance check
# (Test-ProtectionReadBack, unchanged), now wrapped with exactly ONE retry
# (re-PUT once, re-verify) before falling into the halt below — never a second
# retry (`.project/design-philosophy.md#Error & failure philosophy`).
$prRequired = 'unknown'; $adminsEnforced = 'unknown'; $hasContexts = 'unknown'
if (-not (Test-ProtectionReadBack)) {
    Write-Output "milestone-bootstrapper: branch-protection read-back drift on '$targetBranch' — retrying once (re-PUT, re-verify)."
    if (-not (Invoke-ProtectionPut)) {
        ApiFail "retry failed: could not re-assert branch protection on '$slug' branch '$targetBranch' (PUT repos/$slug/branches/$targetBranch/protection). No protection was weakened or removed. Re-run after resolving the error."
    }
    if (-not (Test-ProtectionReadBack)) {
        ApiFail "asserted protection but the read-back still does not show all three floors after one retry (PR required=$prRequired, enforce_admins=$adminsEnforced, status-check contexts=$hasContexts) on '$targetBranch'. Re-run to confirm."
    }
}

Write-Output "milestone-bootstrapper: branch protection asserted on $slug branch '$targetBranch'."
Write-Output "milestone-bootstrapper: direct pushes blocked, PR required (0 approvals), required status checks: $contextsDisplay; $adminsNote."
exit 0
