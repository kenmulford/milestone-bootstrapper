#!/usr/bin/env pwsh
#
# write-driver-config.ps1 — write the target repo's `.milestone-config/driver.json`
# config slice (the driver profile the mechanical gates and skills read).
#
# What this does, in plain terms:
#   The bootstrapper's `apply` skill leaves the TARGET repo with a valid driver
#   profile so `milestone-driver` (and `milestone-feeder`, which reads shared
#   keys from it) run with no further setup (Job 2 "Configs", BRIEF.md:47).
#   `apply` is plan-driven and non-interactive — the approved plan file is the
#   contract (preview-then-execute; BRIEF.md:22-26,64) — so this is a
#   deterministic, reusable writer it calls. It deliberately does NOT invoke
#   `milestone-driver:setup`: that skill's only entry contract is an interactive,
#   tier-by-tier interview (milestone-driver/skills/setup/SKILL.md:50-57) with no
#   non-interactive value-injection entry point; invoking it from `apply` would
#   re-interview the user mid-run, violating the plan-is-the-contract model.
#   Composability and "never keep a second, drifting definition" (BRIEF.md:52,68)
#   are honored by REUSING setup's canonical PATH + KEY SCHEMA as the single
#   source of truth — not by invoking the interview. The PowerShell 7+ twin of
#   write-driver-config.sh (suite cross-platform convention).
#
# Authoritative schema (DRIFT GUARDRAIL — do not widen without updating both):
#   The driver key set, types, the canonical path, and the absent-means-default
#   discipline are defined by the canonical schema doc — the SINGLE source of
#   truth this writer mirrors (never re-defines):
#     milestone-driver/docs/profile-schema.md
#       - "Location"          -> <repo-root>/.milestone-config/driver.json
#                                (profile-schema.md:12-16)
#       - "Keys" table        -> key names + types (profile-schema.md:91-112)
#       - "Minimal example"   -> the 3 Core keys alone is a valid profile
#                                (profile-schema.md:134-142)
#       - "Design principle"  -> implementerAgent is default-filled and OMITTED;
#                                absent-means-default — omit, never null/empty
#                                (profile-schema.md:68, 87, 144)
#   This slice writes ONLY the keys the approved plan supplies (see Inputs). It
#   does NOT emit speculative keys (triageAgent, designReviewAgent, e2eTestCmd,
#   integrationGranularity, nonNegotiables, integrations.trello) — they are not
#   in this writer's plan-driven input set. If the driver schema gains or renames
#   a key this writer emits, update this script in lockstep.
#
# Inputs (RESOLVED values from the approved plan — this writer does NOT
# re-detect them; detection happened in `plan`):
#   -Repo <dir>               target repo root (default: current directory)
#   Core (required — all three or the writer refuses with exit 1):
#     -IntegrationBranch <str>  e.g. "develop"
#     -ProtectedBranch   <str>  e.g. "main"
#     -SourceGlobs       <json> JSON string[] e.g. '["src/**","tests/**"]'
#   Optional (OMITTED when not passed — never written as null/empty):
#     -DomainSkills      <json> JSON string[]  (#3 stack->domainSkills)
#     -UiSurfaceGlobs    <json> JSON string[]
#     -UnitTestCmd       <str>
#     -PreflightCmd      <str>
#     -E2eEnv            <json> JSON object
#     -Versioning <true|false>  #4 versioning policy. absent-means-versioned:
#                               `true` (or omitted) => OMIT the key;
#                               `false` => write `versioning: false` (the ONLY
#                               value ever written for this key).
#   Env fallbacks (params win): DRIVER_REPO, DRIVER_INTEGRATION_BRANCH,
#     DRIVER_PROTECTED_BRANCH, DRIVER_SOURCE_GLOBS, DRIVER_DOMAIN_SKILLS,
#     DRIVER_UI_SURFACE_GLOBS, DRIVER_UNIT_TEST_CMD, DRIVER_PREFLIGHT_CMD,
#     DRIVER_E2E_ENV, DRIVER_VERSIONING.
#
# Behavior:
#   - The minimal valid output is the three Core keys alone (schema:134-142).
#   - Keys the plan does not supply are OMITTED — never written as null/empty.
#     `implementerAgent` is OMITTED (default-filled; schema:68,144). `versioning`
#     is OMITTED when versioned, written `false` only for explicit version-free.
#   - Idempotent / non-destructive: identical existing content is left byte-
#     identical (true no-op); re-runs never duplicate. It never deletes a leftover
#     legacy root milestone-driver.json and never clobbers human edits beyond the
#     plan's scope (reconciling a changed plan is `update`'s job, not this one's).
#   - Errors (missing Core key, bad JSON, unwritable path) surface a clear
#     message on stderr and exit non-zero — never leaving a partial/invalid file.
#
# Run it:  ./scripts/write-driver-config.ps1 -Repo /path/to/target `
#            -IntegrationBranch develop -ProtectedBranch main `
#            -SourceGlobs '["src/**","tests/**"]' [optional params...]
# Exit 0 = file is present and correct. Exit 1 = bad input. Exit 2 = write/serialize failure.

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$IntegrationBranch,
    [string]$ProtectedBranch,
    [string]$SourceGlobs,
    [string]$DomainSkills,
    [string]$UiSurfaceGlobs,
    [string]$UnitTestCmd,
    [string]$PreflightCmd,
    [string]$E2eEnv,
    # Versioning accepts the strings "true"/"false" (or the boolean $true/$false);
    # typed as object so `-Versioning:$false` and `-Versioning false` both work.
    [object]$Versioning
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Inputs (params override env; env overrides unset) -------------------------
# A param is "supplied" when bound on the command line OR present (non-empty) in
# its env fallback. Track supplied-ness per optional key so an absent key is
# OMITTED — distinct from a passed empty value, which is a bad input (exit 1).
$bound = $PSBoundParameters

if (-not $bound.ContainsKey('Repo')) {
    $Repo = if ($env:DRIVER_REPO) { $env:DRIVER_REPO } else { '.' }
}

# Core keys: bound-param value wins, else env, else empty (validated below).
if (-not $bound.ContainsKey('IntegrationBranch')) {
    $IntegrationBranch = if ($env:DRIVER_INTEGRATION_BRANCH) { $env:DRIVER_INTEGRATION_BRANCH } else { '' }
}
if (-not $bound.ContainsKey('ProtectedBranch')) {
    $ProtectedBranch = if ($env:DRIVER_PROTECTED_BRANCH) { $env:DRIVER_PROTECTED_BRANCH } else { '' }
}
if (-not $bound.ContainsKey('SourceGlobs')) {
    $SourceGlobs = if ($env:DRIVER_SOURCE_GLOBS) { $env:DRIVER_SOURCE_GLOBS } else { '' }
}

# Optional keys: track supplied-ness so unset => OMIT, passed-empty => bad input.
$domainSkillsIn   = if ($bound.ContainsKey('DomainSkills'))   { @{ Supplied = $true; Value = $DomainSkills } }   elseif ($null -ne $env:DRIVER_DOMAIN_SKILLS   -and $env:DRIVER_DOMAIN_SKILLS   -ne '') { @{ Supplied = $true; Value = $env:DRIVER_DOMAIN_SKILLS } }   else { @{ Supplied = $false } }
$uiSurfaceGlobsIn = if ($bound.ContainsKey('UiSurfaceGlobs')) { @{ Supplied = $true; Value = $UiSurfaceGlobs } } elseif ($null -ne $env:DRIVER_UI_SURFACE_GLOBS -and $env:DRIVER_UI_SURFACE_GLOBS -ne '') { @{ Supplied = $true; Value = $env:DRIVER_UI_SURFACE_GLOBS } } else { @{ Supplied = $false } }
$unitTestCmdIn    = if ($bound.ContainsKey('UnitTestCmd'))    { @{ Supplied = $true; Value = $UnitTestCmd } }    elseif ($null -ne $env:DRIVER_UNIT_TEST_CMD   -and $env:DRIVER_UNIT_TEST_CMD   -ne '') { @{ Supplied = $true; Value = $env:DRIVER_UNIT_TEST_CMD } }    else { @{ Supplied = $false } }
$preflightCmdIn   = if ($bound.ContainsKey('PreflightCmd'))   { @{ Supplied = $true; Value = $PreflightCmd } }   elseif ($null -ne $env:DRIVER_PREFLIGHT_CMD   -and $env:DRIVER_PREFLIGHT_CMD   -ne '') { @{ Supplied = $true; Value = $env:DRIVER_PREFLIGHT_CMD } }   else { @{ Supplied = $false } }
$e2eEnvIn         = if ($bound.ContainsKey('E2eEnv'))         { @{ Supplied = $true; Value = $E2eEnv } }         elseif ($null -ne $env:DRIVER_E2E_ENV         -and $env:DRIVER_E2E_ENV         -ne '') { @{ Supplied = $true; Value = $env:DRIVER_E2E_ENV } }         else { @{ Supplied = $false } }
$versioningIn     = if ($bound.ContainsKey('Versioning'))     { @{ Supplied = $true; Value = $Versioning } }     elseif ($null -ne $env:DRIVER_VERSIONING     -and $env:DRIVER_VERSIONING     -ne '') { @{ Supplied = $true; Value = $env:DRIVER_VERSIONING } }     else { @{ Supplied = $false } }

# --- Validate the three Core keys (all-or-refuse; no partial profile) ----------
# Schema:91-95,134-142 — the three Core keys are required in the file.
$missing = @()
if ([string]::IsNullOrEmpty($IntegrationBranch)) { $missing += '-IntegrationBranch' }
if ([string]::IsNullOrEmpty($ProtectedBranch))   { $missing += '-ProtectedBranch' }
if ([string]::IsNullOrEmpty($SourceGlobs))       { $missing += '-SourceGlobs' }
if ($missing.Count -gt 0) {
    [Console]::Error.WriteLine("ERROR: missing required Core key(s): $($missing -join ', ').")
    [Console]::Error.WriteLine("       The three Core keys (integrationBranch, protectedBranch, sourceGlobs) are required; no file written.")
    exit 1
}

# --- Validate + parse JSON-shaped inputs before assembly -----------------------
# Each array key must parse as a JSON array; e2eEnv as a JSON object. ConvertFrom-
# Json with -AsHashtable gives a stable round-trip back through ConvertTo-Json.
function ConvertFrom-JsonArray {
    param([string]$FlagName, [string]$Raw)
    # ConvertFrom-Json UNWRAPS a single-element JSON array to its scalar element
    # (so ["x"] parses to the string "x", not an array), which makes a post-parse
    # [System.Array] type-test wrongly reject a valid 1-element array. Discriminate
    # on the raw JSON text instead: a JSON array's first non-whitespace char is '['.
    if ($Raw.TrimStart() -notmatch '^\[') {
        [Console]::Error.WriteLine("ERROR: $FlagName must be a JSON array (got: $Raw)."); exit 1
    }
    try { $parsed = $Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { [Console]::Error.WriteLine("ERROR: $FlagName must be a JSON array (got: $Raw)."); exit 1 }
    # Force back to an array so a 1-element value re-serializes as a JSON array,
    # not a bare scalar. @() normalizes the unwrap; ,$ preserves it on return.
    return ,@($parsed)
}
function ConvertFrom-JsonObject {
    param([string]$FlagName, [string]$Raw)
    # A JSON object's first non-whitespace char is '{'. Discriminate on the raw
    # text up front (parity with the array helper) for a clear, early rejection.
    if ($Raw.TrimStart() -notmatch '^\{') {
        [Console]::Error.WriteLine("ERROR: $FlagName must be a JSON object (got: $Raw)."); exit 1
    }
    try { $parsed = $Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
    catch { [Console]::Error.WriteLine("ERROR: $FlagName must be a JSON object (got: $Raw)."); exit 1 }
    if ($parsed -isnot [System.Collections.IDictionary]) {
        [Console]::Error.WriteLine("ERROR: $FlagName must be a JSON object (got: $Raw)."); exit 1
    }
    # Canonicalize key order so output is byte-identical to the bash twin on EVERY
    # PowerShell 7.x. `ConvertFrom-Json -AsHashtable` returns an UNORDERED
    # [hashtable] on PS 7.0-7.2 (only OrderedHashtable on 7.3+), while the bash
    # twin (jq) preserves input order; either way the two can disagree. Sorting
    # the keys in BOTH writers makes one canonical order the only possible output.
    # [StringComparer]::Ordinal is a case-sensitive codepoint (byte-wise) sort that
    # matches jq's `sort_by(.key)`; the culture-aware default Sort-Object could
    # reorder hyphens/case differently and break byte-parity with the bash twin.
    $sortedKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $parsed.Keys) { $sortedKeys.Add([string]$k) }
    $sortedKeys.Sort([System.StringComparer]::Ordinal)
    $ordered = [ordered]@{}
    foreach ($k in $sortedKeys) { $ordered[$k] = $parsed[$k] }
    return $ordered
}

$sourceGlobsVal = ConvertFrom-JsonArray '-SourceGlobs' $SourceGlobs
$domainSkillsVal   = if ($domainSkillsIn.Supplied)   { ConvertFrom-JsonArray  '-DomainSkills'    $domainSkillsIn.Value }   else { $null }
$uiSurfaceGlobsVal = if ($uiSurfaceGlobsIn.Supplied) { ConvertFrom-JsonArray  '-UiSurfaceGlobs'  $uiSurfaceGlobsIn.Value } else { $null }
$e2eEnvVal         = if ($e2eEnvIn.Supplied)         { ConvertFrom-JsonObject '-E2eEnv'          $e2eEnvIn.Value }        else { $null }

# --- Validate versioning (absent-means-versioned; only `false` is ever written) -
# Schema:105,118 — absent/true => versioned (omit). false => version-free (write).
$writeVersioningFalse = $false
if ($versioningIn.Supplied) {
    $v = $versioningIn.Value
    if ($v -is [bool]) {
        $writeVersioningFalse = ($v -eq $false)
    } elseif ($v -is [string] -and $v -eq 'false') {
        $writeVersioningFalse = $true
    } elseif ($v -is [string] -and $v -eq 'true') {
        $writeVersioningFalse = $false  # versioned => omit
    } else {
        [Console]::Error.WriteLine("ERROR: -Versioning must be `"true`" or `"false`" (got: $v).")
        exit 1
    }
}

# --- Assemble the object in canonical key order (Core first, then optional) -----
# An ordered hashtable preserves key order in the serialized JSON. Add only keys
# the plan supplied. implementerAgent is intentionally never added.
$obj = [ordered]@{}
$obj['integrationBranch'] = $IntegrationBranch
$obj['protectedBranch']   = $ProtectedBranch
$obj['sourceGlobs']       = $sourceGlobsVal
if ($uiSurfaceGlobsIn.Supplied) { $obj['uiSurfaceGlobs'] = $uiSurfaceGlobsVal }
if ($writeVersioningFalse)      { $obj['versioning'] = $false }
if ($unitTestCmdIn.Supplied)    { $obj['unitTestCmd'] = $unitTestCmdIn.Value }
if ($preflightCmdIn.Supplied)   { $obj['preflightCmd'] = $preflightCmdIn.Value }
if ($domainSkillsIn.Supplied)   { $obj['domainSkills'] = $domainSkillsVal }
if ($e2eEnvIn.Supplied)         { $obj['e2eEnv'] = $e2eEnvVal }

try {
    $NewContent = ($obj | ConvertTo-Json -Depth 10 -Compress:$false)
} catch {
    [Console]::Error.WriteLine("ERROR: failed to serialize driver.json: $($_.Exception.Message)")
    exit 2
}

# --- Resolve the destination path ----------------------------------------------
$ConfigDir  = Join-Path ($Repo.TrimEnd('/', '\')) '.milestone-config'
$ConfigFile = Join-Path $ConfigDir 'driver.json'

# Guard: if the config path is an existing DIRECTORY, a later Move-Item -Force
# would move the temp file INTO it (driver.json/<tmp>) and falsely report success
# — the real file would never be written. Refuse up front with a clear message.
# (Parity with the bash twin's directory guard.)
if (Test-Path -LiteralPath $ConfigFile -PathType Container) {
    [Console]::Error.WriteLine("ERROR: cannot write driver.json: $ConfigFile exists and is a directory.")
    exit 2
}

# --- Idempotent no-op: identical existing content is left byte-identical --------
if (Test-Path -LiteralPath $ConfigFile -PathType Leaf) {
    # Get-Content -Raw returns $null (not "") for a 0-byte file; coalesce to ""
    # so .TrimEnd never executes on a null-valued expression (StrictMode-safe).
    $existing = Get-Content -LiteralPath $ConfigFile -Raw
    if ($null -eq $existing) { $existing = '' }
    if ($existing.TrimEnd("`r", "`n") -eq $NewContent.TrimEnd("`r", "`n")) {
        Write-Output "$ConfigFile already up to date (no change)."
        exit 0
    }
}

# --- Write (create .milestone-config/ if absent) -------------------------------
# Initialize $tmp BEFORE the try so the catch can reference it safely under
# Set-StrictMode even if New-Item throws before $tmp is otherwise assigned.
$tmp = $null
try {
    if (-not (Test-Path -LiteralPath $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    # Atomic-ish write via a temp file so a failure never leaves a partial file.
    # utf8NoBOM keeps the JSON BOM-free and portable (PS 7+ default, set
    # explicitly to be unambiguous).
    $tmp = Join-Path $ConfigDir ('.driver.json.' + [System.IO.Path]::GetRandomFileName())
    Set-Content -LiteralPath $tmp -Value $NewContent -Encoding utf8NoBOM -NoNewline
    Add-Content -LiteralPath $tmp -Value "`n" -Encoding utf8NoBOM -NoNewline
    Move-Item -LiteralPath $tmp -Destination $ConfigFile -Force
} catch {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    [Console]::Error.WriteLine("ERROR: failed to write driver.json to: $ConfigDir ($($_.Exception.Message))")
    exit 2
}

Write-Output "$ConfigFile written."
Write-Output $NewContent
exit 0
