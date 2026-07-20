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
#   integrationGranularity, integrations.trello) — they are not
#   in this writer's plan-driven input set. If the driver schema gains or renames
#   a key this writer emits, update this script in lockstep.
#
#   GUARDRAIL EXEMPTION — projectDocs: `projectDocs` is an INTENTIONALLY-emitted
#   additive key that ships AHEAD of the sibling driver schema
#   (milestone-driver/docs/profile-schema.md) and its consumer. This is a
#   recorded, deliberate widening — not drift — per docs/efficiency-grounding-plan.md
#   "Dependencies & sequence" ("Safe to ship independently and first", line 52)
#   and the tracking issue bootstrapper #38. It mirrors write-feeder-config's
#   projectDocs (default ".project/", omit-when-default) so the pointer never
#   drifts between feeder.json and driver.json. The guardrail above still governs
#   EVERY OTHER key against schema parity; do NOT "un-widen" projectDocs back to
#   schema parity — that would re-introduce the drift this key exists to prevent.
#
#   GUARDRAIL EXEMPTION — stack / stackVersionFile (PERMANENT, by design): `stack`
#   and `stackVersionFile` are INTENTIONALLY-emitted additive keys that are
#   PERMANENTLY exempt from the sibling driver schema (milestone-driver/docs/
#   profile-schema.md) — NOT a temporary ship-ahead. The milestone-driver plugin
#   never consumes these keys; only THIS bootstrapper's emit-ci-workflow reads them
#   back. A schema documents what its plugin consumes, so these bootstrapper-owned
#   keys are canonically documented in this repo's SPEC §6.1 and deliberately kept
#   OUT of the driver's schema (profile-schema.md carries a one-line pointer to
#   SPEC §6.1 for file-completeness, with no per-key lockstep). The guardrail still
#   governs EVERY OTHER key against schema parity; do NOT "un-widen" these keys back
#   to schema parity — that would re-introduce the drift this exemption prevents.
#   Resolves #66 (schema convergence — decided: permanent exemption, not converge).
#
#   GUARDRAIL EXEMPTION — integrationProtection (PERMANENT, by design):
#   `integrationProtection` is an INTENTIONALLY-emitted additive key that is
#   PERMANENTLY exempt from the sibling driver schema (milestone-driver/docs/
#   profile-schema.md) — NOT a temporary ship-ahead. The milestone-driver plugin
#   never consumes this key; only THIS bootstrapper's provision-protection reads it
#   back, as the opt-in gate for the integration-branch floor. A schema documents
#   what its plugin consumes, so this bootstrapper-owned key is canonically
#   documented in this repo's SPEC §6.1 and deliberately kept OUT of the driver's
#   schema. The guardrail still governs EVERY OTHER key against schema parity; do
#   NOT "un-widen" this key back to schema parity — that would re-introduce the
#   drift this exemption prevents. (Issue #93 decision a.)
#
# Inputs (RESOLVED values from the approved plan — this writer does NOT
# re-detect them; detection happened in `plan`):
#   -Repo <dir>               target repo root (default: current directory)
#   Core (required — all three or the writer refuses with exit 1):
#     -IntegrationBranch <str>  e.g. "develop"
#     -ProtectedBranch   <str>  e.g. "main"
#     -SourceGlobs       <json> JSON string[] e.g. '["src/**","tests/**"]'
#   Optional (OMITTED when not passed — never written as null/empty):
#     -ProjectDocs       <str>  the resolved `.project/` path (default
#                               ".project/"; OMITTED from the file when equal to
#                               the bundled default — the omit test is against the
#                               BUNDLED default, mirroring write-feeder-config).
#     -DomainSkills      <json> JSON string[]  (#3 stack->domainSkills)
#     -NonNegotiables    <json> JSON string[]  hard constraints the implementer
#                               must honour (framework versions, platform targets).
#     -UiSurfaceGlobs    <json> JSON string[]
#     -UnitTestCmd       <str>
#     -PreflightCmd      <str>
#     -E2eEnv            <json> JSON object
#     -Versioning <true|false>  #4 versioning policy. absent-means-versioned:
#                               `true` (or omitted) => OMIT the key;
#                               `false` => write `versioning: false` (the ONLY
#                               value ever written for this key).
#     -Stack <enum>             the runtime family the emitter will scaffold setup
#                               for, one of
#                               node|python|dotnet|maui|rust|plugin|ruby|none.
#                               absent-means-default: `none` (or omitted) => OMIT
#                               the key; any other member => write it. An unknown
#                               value is a bad input (exit 1).
#     -StackVersionFile <str>   the detected version-file path (e.g. ".nvmrc",
#                               ".python-version", "global.json"). OMITTED when not
#                               passed — never written as null/empty.
#     -IntegrationProtection <enum>  whether the integration branch carries a
#                               protection floor, one of none|floor.
#                               absent-means-default: `none` (or omitted) => OMIT the
#                               key; `floor` => write it. An unknown value is a bad
#                               input (exit 1). Read back ONLY by this repo's
#                               provision-protection -Floor integration.
#   Env fallbacks (params win): DRIVER_REPO, DRIVER_INTEGRATION_BRANCH,
#     DRIVER_PROTECTED_BRANCH, DRIVER_SOURCE_GLOBS, DRIVER_PROJECT_DOCS,
#     DRIVER_DOMAIN_SKILLS, DRIVER_NON_NEGOTIABLES, DRIVER_UI_SURFACE_GLOBS,
#     DRIVER_UNIT_TEST_CMD, DRIVER_PREFLIGHT_CMD, DRIVER_E2E_ENV, DRIVER_VERSIONING,
#     DRIVER_STACK, DRIVER_STACK_VERSION_FILE, DRIVER_INTEGRATION_PROTECTION.
#
# Behavior:
#   - The minimal valid output is the three Core keys alone (schema:134-142).
#   - Keys the plan does not supply are OMITTED — never written as null/empty.
#     `implementerAgent` is OMITTED (default-filled; schema:68,144). `versioning`
#     is OMITTED when versioned, written `false` only for explicit version-free.
#     `projectDocs` is OMITTED when left at the bundled default ".project/" and
#     written only for a divergent value (omit-when-default, against the BUNDLED
#     default — mirroring write-feeder-config.ps1:94).
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
    [string]$ProjectDocs,
    [string]$DomainSkills,
    [string]$NonNegotiables,
    [string]$UiSurfaceGlobs,
    [string]$UnitTestCmd,
    [string]$PreflightCmd,
    [string]$E2eEnv,
    # Versioning accepts the strings "true"/"false" (or the boolean $true/$false);
    # typed as object so `-Versioning:$false` and `-Versioning false` both work.
    [object]$Versioning,
    [string]$Stack,
    [string]$StackVersionFile,
    [string]$IntegrationProtection
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Bundled default (mirror milestone-feeder/docs/profile-schema.md; the shared
# projectDocs pointer's default — see write-feeder-config.ps1:64) ----------------
$DefaultProjectDocs = '.project/'

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

# projectDocs resolves to its bundled default when unset (it has a real default,
# unlike the supplied-ness-tracked optional keys below); the omit-when-default test
# in the assembly drops it when still equal to the default. Mirror of the feeder
# twin's param->env->default resolution (write-feeder-config.ps1:71-72).
if (-not $bound.ContainsKey('ProjectDocs')) {
    $ProjectDocs = if ($env:DRIVER_PROJECT_DOCS) { $env:DRIVER_PROJECT_DOCS } else { $DefaultProjectDocs }
}

# Optional keys: track supplied-ness so unset => OMIT, passed-empty => bad input.
$domainSkillsIn   = if ($bound.ContainsKey('DomainSkills'))   { @{ Supplied = $true; Value = $DomainSkills } }   elseif ($null -ne $env:DRIVER_DOMAIN_SKILLS   -and $env:DRIVER_DOMAIN_SKILLS   -ne '') { @{ Supplied = $true; Value = $env:DRIVER_DOMAIN_SKILLS } }   else { @{ Supplied = $false } }
$nonNegotiablesIn = if ($bound.ContainsKey('NonNegotiables')) { @{ Supplied = $true; Value = $NonNegotiables } } elseif ($null -ne $env:DRIVER_NON_NEGOTIABLES -and $env:DRIVER_NON_NEGOTIABLES -ne '') { @{ Supplied = $true; Value = $env:DRIVER_NON_NEGOTIABLES } } else { @{ Supplied = $false } }
$uiSurfaceGlobsIn = if ($bound.ContainsKey('UiSurfaceGlobs')) { @{ Supplied = $true; Value = $UiSurfaceGlobs } } elseif ($null -ne $env:DRIVER_UI_SURFACE_GLOBS -and $env:DRIVER_UI_SURFACE_GLOBS -ne '') { @{ Supplied = $true; Value = $env:DRIVER_UI_SURFACE_GLOBS } } else { @{ Supplied = $false } }
$unitTestCmdIn    = if ($bound.ContainsKey('UnitTestCmd'))    { @{ Supplied = $true; Value = $UnitTestCmd } }    elseif ($null -ne $env:DRIVER_UNIT_TEST_CMD   -and $env:DRIVER_UNIT_TEST_CMD   -ne '') { @{ Supplied = $true; Value = $env:DRIVER_UNIT_TEST_CMD } }    else { @{ Supplied = $false } }
$preflightCmdIn   = if ($bound.ContainsKey('PreflightCmd'))   { @{ Supplied = $true; Value = $PreflightCmd } }   elseif ($null -ne $env:DRIVER_PREFLIGHT_CMD   -and $env:DRIVER_PREFLIGHT_CMD   -ne '') { @{ Supplied = $true; Value = $env:DRIVER_PREFLIGHT_CMD } }   else { @{ Supplied = $false } }
$e2eEnvIn         = if ($bound.ContainsKey('E2eEnv'))         { @{ Supplied = $true; Value = $E2eEnv } }         elseif ($null -ne $env:DRIVER_E2E_ENV         -and $env:DRIVER_E2E_ENV         -ne '') { @{ Supplied = $true; Value = $env:DRIVER_E2E_ENV } }         else { @{ Supplied = $false } }
$versioningIn     = if ($bound.ContainsKey('Versioning'))     { @{ Supplied = $true; Value = $Versioning } }     elseif ($null -ne $env:DRIVER_VERSIONING     -and $env:DRIVER_VERSIONING     -ne '') { @{ Supplied = $true; Value = $env:DRIVER_VERSIONING } }     else { @{ Supplied = $false } }
# stack: param wins, else env, else empty (omit-when-`none`/empty). An explicitly
# passed empty `-Stack ''` is a BAD INPUT (errors below) — mirroring the bash twin,
# where `--stack ''` is rejected by the `${2:?--stack needs a value}` parse guard.
# An empty ENV (`DRIVER_STACK=''`) is treated as unset — bash `${DRIVER_STACK:-}`
# does the same — so it omits without error. Track the explicit-empty-arg case so
# only that path errors, matching bash's arg-empty(error) / env-empty(omit) split.
$stackArgEmpty = $bound.ContainsKey('Stack') -and [string]::IsNullOrEmpty($Stack)
if (-not $bound.ContainsKey('Stack')) {
    $Stack = if ($env:DRIVER_STACK) { $env:DRIVER_STACK } else { '' }
}
# stackVersionFile tracks supplied-ness like the other optional string keys, so an
# unset value is OMITTED (distinct from a passed empty value, which is a bad input).
$stackVersionFileIn = if ($bound.ContainsKey('StackVersionFile')) { @{ Supplied = $true; Value = $StackVersionFile } } elseif ($null -ne $env:DRIVER_STACK_VERSION_FILE -and $env:DRIVER_STACK_VERSION_FILE -ne '') { @{ Supplied = $true; Value = $env:DRIVER_STACK_VERSION_FILE } } else { @{ Supplied = $false } }
# integrationProtection: param wins, else env, else empty (omit-when-`none`/empty).
# Same arg-empty(error) / env-empty(omit) split as -Stack above, mirroring the bash
# twin's `${2:?--integration-protection needs a value}` parse guard.
$integrationProtectionArgEmpty = $bound.ContainsKey('IntegrationProtection') -and [string]::IsNullOrEmpty($IntegrationProtection)
if (-not $bound.ContainsKey('IntegrationProtection')) {
    $IntegrationProtection = if ($env:DRIVER_INTEGRATION_PROTECTION) { $env:DRIVER_INTEGRATION_PROTECTION } else { '' }
}

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
$nonNegotiablesVal = if ($nonNegotiablesIn.Supplied) { ConvertFrom-JsonArray  '-NonNegotiables'  $nonNegotiablesIn.Value } else { $null }
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

# --- Validate stack (omit-when-default; `none`/unset => OMIT, else write) -------
# The enum is node|python|dotnet|maui|rust|plugin|ruby|none. `none` (and a
# genuinely unset value: no `-Stack` arg + empty/unset DRIVER_STACK) means "omit
# the key", so it is VALID input. An explicitly passed empty `-Stack ''` is a BAD
# INPUT, not `none` — it errors + exit 1 (parity with the bash twin's `${2:?}`
# arg-empty rejection and the -Versioning empty->error path above). Any non-member
# value is likewise rejected with a clear message naming the allowed set + exit 1.
# The descriptive->enum mapping (e.g. angular collapses to node) is issue #65's
# job — this writer only validates the resolved enum. `ruby` covers both Rails and
# plain Ruby (parity with `python` covering FastAPI/Django/Flask/unresolved as one
# enum member; issue #104).
$writeStack = $false
if ($stackArgEmpty) {
    [Console]::Error.WriteLine("ERROR: -Stack must be one of node|python|dotnet|maui|rust|plugin|ruby|none (got: ).")
    exit 1
}
if (-not [string]::IsNullOrEmpty($Stack)) {
    switch ($Stack) {
        { $_ -in 'node', 'python', 'dotnet', 'maui', 'rust', 'plugin', 'ruby' } { $writeStack = $true }
        'none' { $writeStack = $false }  # default => omit
        default {
            [Console]::Error.WriteLine("ERROR: -Stack must be one of node|python|dotnet|maui|rust|plugin|ruby|none (got: $Stack).")
            exit 1
        }
    }
}

# --- Validate integrationProtection (omit-when-default; `none`/unset => OMIT) ---
# The enum is none|floor, default `none` (SPEC §6.1). `none` (and a genuinely unset
# value) means "omit the key", so it is VALID input; `floor` is the only value ever
# written. An explicitly passed empty `-IntegrationProtection ''` is a BAD INPUT,
# not `none` — it errors + exit 1 (parity with the -Stack empty->error path above).
$writeIntegrationProtection = $false
if ($integrationProtectionArgEmpty) {
    [Console]::Error.WriteLine("ERROR: -IntegrationProtection must be one of none|floor (got: ).")
    exit 1
}
if (-not [string]::IsNullOrEmpty($IntegrationProtection)) {
    switch ($IntegrationProtection) {
        'floor' { $writeIntegrationProtection = $true }
        'none'  { $writeIntegrationProtection = $false }  # default => omit
        default {
            [Console]::Error.WriteLine("ERROR: -IntegrationProtection must be one of none|floor (got: $IntegrationProtection).")
            exit 1
        }
    }
}

# --- Assemble the object in canonical key order (Core first, then optional) -----
# An ordered hashtable preserves key order in the serialized JSON. Add only keys
# the plan supplied. implementerAgent is intentionally never added.
$obj = [ordered]@{}
$obj['integrationBranch'] = $IntegrationBranch
$obj['protectedBranch']   = $ProtectedBranch
$obj['sourceGlobs']       = $sourceGlobsVal
# projectDocs is the FIRST optional key (slot immediately after the Core keys),
# emitted ONLY when it diverges from the bundled default — omit-when-default
# against the BUNDLED default (mirror of write-feeder-config.ps1:94). Same slot as
# the .sh twin so output stays byte-identical.
if ($ProjectDocs -ne $DefaultProjectDocs) { $obj['projectDocs'] = $ProjectDocs }
if ($uiSurfaceGlobsIn.Supplied) { $obj['uiSurfaceGlobs'] = $uiSurfaceGlobsVal }
if ($writeVersioningFalse)      { $obj['versioning'] = $false }
if ($unitTestCmdIn.Supplied)    { $obj['unitTestCmd'] = $unitTestCmdIn.Value }
if ($preflightCmdIn.Supplied)   { $obj['preflightCmd'] = $preflightCmdIn.Value }
if ($domainSkillsIn.Supplied)   { $obj['domainSkills'] = $domainSkillsVal }
# nonNegotiables sits immediately after domainSkills so the two Enrichment array
# keys stay adjacent (schema relative order; profile-schema.md:117). Same slot as
# the .sh twin so output stays byte-identical.
if ($nonNegotiablesIn.Supplied) { $obj['nonNegotiables'] = $nonNegotiablesVal }
if ($e2eEnvIn.Supplied)         { $obj['e2eEnv'] = $e2eEnvVal }
# stack / stackVersionFile: additive keys shipping ahead of the canonical schema
# (see GUARDRAIL EXEMPTION above). stack written only for a non-`none` enum member;
# stackVersionFile written only when passed (supplied-ness tracked). Same slot as
# the .sh twin so output stays byte-identical.
if ($writeStack)                  { $obj['stack'] = $Stack }
if ($stackVersionFileIn.Supplied) { $obj['stackVersionFile'] = $stackVersionFileIn.Value }
# integrationProtection: a bootstrapper-owned additive key permanently exempt from
# the driver schema (see GUARDRAIL EXEMPTION above). Written only for `floor` — a
# key at its default (`none`) is not written (SPEC.md:271-273), same discipline as
# the `versioning` boolean. LAST slot, adjacent to the other bootstrapper-owned
# keys. Same slot as the .sh twin so output stays byte-identical.
if ($writeIntegrationProtection)  { $obj['integrationProtection'] = $IntegrationProtection }

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
