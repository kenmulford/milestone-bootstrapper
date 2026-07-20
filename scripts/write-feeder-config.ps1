#!/usr/bin/env pwsh
#
# write-feeder-config.ps1 — write the target repo's `.milestone-config/feeder.json`
# config slice (the feeder-owned keys: `projectDocs`, `versioning`).
#
# What this does, in plain terms:
#   The bootstrapper's `apply` skill (#13) leaves the TARGET repo with the correct
#   feeder-config SIGNAL — a present, non-empty `feeder.json` when any key diverges
#   from its default, or NO `feeder.json` at all when every key is at its default —
#   so `milestone-feeder`'s first-run `setup` runs exactly when it should (it
#   auto-invokes on an ABSENT file). `apply` is non-interactive, so this is a
#   deterministic, reusable writer it calls — NOT the interactive
#   `milestone-feeder:setup` interview (that path is interview-only, with no
#   non-interactive entry, so it cannot run unattended). Recorded decision: issue
#   #5 "✅ Design decision — Option A". For the non-default case this writer
#   produces the identical file `setup`'s Phase 3 would, to the same schema and the
#   same absent-means-default discipline; when every key is at its default the
#   assembled object is empty and the file is deliberately left ABSENT rather than
#   emitted as `{}` (issue #77) — see Behavior below. The PowerShell 7+ twin of
#   write-feeder-config.sh (suite cross-platform convention).
#
# Authoritative schema (DRIFT GUARDRAIL — do not widen without updating both):
#   The feeder-owned key set and the absent-means-default discipline are defined
#   by the canonical schema doc:
#     milestone-feeder/docs/profile-schema.md
#       - "Own keys" table          -> projectDocs (default ".project/"),
#                                       versioning  ("semver"|"none"; NO bundled
#                                                    default — absent = infer-or-ask;
#                                                    profile-schema.md:52,115-133)
#       - "Absent-means-default discipline" -> omit a key left at its BUNDLED
#                                       default; an empty `{}` remains a valid
#                                       profile to READ, but this writer no longer
#                                       EMITS it — an all-default slice is left
#                                       ABSENT (issue #77, see Behavior).
#   This slice writes the feeder-OWNED keys `projectDocs` and `versioning`. The
#   two `versioning` keys are DISTINCT: this writes
#   `feeder.json#versioning` — the feeder's own STRING enum "semver"|"none" (its
#   read-contract key, profile-schema.md:52), which is NOT the driver's BOOLEAN
#   `driver.json#versioning` (owned by the driver-config slice #8, ever only
#   written as `false`). A single Tier-6 answer maps to BOTH keys (dual-write):
#   versioned => driver OMITS / feeder "semver"; non-versioned => driver `false` /
#   feeder "none"; skipped/[TBD] => BOTH omit. This slice deliberately does NOT
#   write the shared/driver keys (uiSurfaceGlobs, integrationBranch, the consumer's
#   sourceGlobs, domainSkills, nonNegotiables, and the driver's BOOLEAN versioning)
#   — those are read from the driver config and owned by the driver-config slice
#   (#8). The feeder retired its `reviewer` own-key, so this writer no longer emits
#   it. If the feeder's schema gains or renames an own-key, update this script in
#   lockstep.
#
# Inputs (resolved values — this writer does NOT re-derive them):
#   -Repo <dir>          target repo root (default: current directory)
#   -ProjectDocs <str>   the resolved `.project/` path from Job 1
#                        (default ".project/"; omitted when equal to the default)
#   -Versioning <val>    "semver" | "none" — the Tier-6 versioning policy as the
#                        feeder's STRING enum. Three-way UNSET-sentinel (NOT the
#                        omit-when-equals-default rule -ProjectDocs uses, because
#                        feeder#versioning has NO bundled default):
#                        "semver" => emit "versioning":"semver"; "none" => emit
#                        "versioning":"none"; not-passed => OMIT the key entirely
#                        (never a placeholder — absent = infer-or-ask). Any other
#                        value is bad input (exit 1).
#   Env fallbacks (params win): FEEDER_PROJECT_DOCS, FEEDER_VERSIONING, FEEDER_REPO.
#
# Behavior:
#   - Writes the file ONLY when the assembled config DIVERGES from the bundled
#     defaults. When every key is at its default the assembled object is empty and
#     the file is deliberately left ABSENT rather than emitted as `{}`, so
#     milestone-feeder's absent-only first-run `setup` trigger fires (issue #77).
#     Non-destructive: an all-default run never writes AND never deletes an
#     existing file.
#   - Idempotent / non-destructive: identical existing content is left byte-
#     identical (true no-op); re-runs never duplicate. (Key-level diff+patch of
#     human edits is the future `update` skill's job, not this writer's.)
#   - Errors (unwritable path, serialize failure) surface a clear message on
#     stderr and exit non-zero — never leaving a partial/invalid file in place.
#
# Run it:  ./scripts/write-feeder-config.ps1 -Repo /path/to/target [-ProjectDocs ...] [-Versioning ...]
# Exit 0 = feeder.json is present-and-correct OR deliberately left absent (all keys at default).
# Exit 1 = bad input. Exit 2 = write/serialize failure.

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$ProjectDocs,
    # Versioning is the feeder's own STRING enum "semver"|"none" (never a boolean),
    # so a plain [string] param — no bundled default (absent = infer-or-ask). Its
    # supplied-ness is tracked below so an unpassed value is OMITTED (three-way),
    # mirroring write-driver-config.ps1's UNSET handling for its optional keys.
    [string]$Versioning
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Bundled defaults (mirror milestone-feeder/docs/profile-schema.md) ---------
$DefaultProjectDocs = '.project/'

# --- Inputs (params override env; env overrides default) -----------------------
if (-not $PSBoundParameters.ContainsKey('Repo')) {
    $Repo = if ($env:FEEDER_REPO) { $env:FEEDER_REPO } else { '.' }
}
if (-not $PSBoundParameters.ContainsKey('ProjectDocs')) {
    $ProjectDocs = if ($env:FEEDER_PROJECT_DOCS) { $env:FEEDER_PROJECT_DOCS } else { $DefaultProjectDocs }
}
# versioning supplied-ness: param wins, else non-empty env, else NOT supplied
# (=> OMIT). Tracked as a hashtable so an unpassed value is omitted (three-way),
# distinct from a passed value — feeder#versioning has NO bundled default. Mirrors
# write-driver-config.ps1:181's $versioningIn supplied-ness idiom.
$versioningIn = if ($PSBoundParameters.ContainsKey('Versioning')) { @{ Supplied = $true; Value = $Versioning } } elseif ($null -ne $env:FEEDER_VERSIONING -and $env:FEEDER_VERSIONING -ne '') { @{ Supplied = $true; Value = $env:FEEDER_VERSIONING } } else { @{ Supplied = $false } }

# --- Validate versioning against the feeder schema's enum (unset => omit) -------
# Only "semver"|"none" are valid (profile-schema.md:52); any other PASSED value is
# bad input. Unset (not supplied) is valid and means OMIT (absent = infer-or-ask).
# Mirrors write-driver-config.ps1:259-274.
if ($versioningIn.Supplied -and ($versioningIn.Value -notin @('semver', 'none'))) {
    [Console]::Error.WriteLine("ERROR: -Versioning must be `"semver`" or `"none`" (got: $($versioningIn.Value)).")
    exit 1
}

# --- Assemble the minimal object (absent-means-default: omit bundled defaults) --
# An ordered hashtable preserves key order in the serialized JSON; add only keys
# whose resolved value DIVERGES from the bundled default. An all-default run
# leaves it empty, which would serialize to `{}` — but that is then NOT written
# (see the empty-object guard below, issue #77).
$obj = [ordered]@{}
if ($ProjectDocs -ne $DefaultProjectDocs) { $obj['projectDocs'] = $ProjectDocs }
# versioning is a three-way UNSET-sentinel key (no bundled default): emit the
# resolved string enum, or OMIT when unset. Adding it makes $obj non-empty so the
# empty-object guard below (issue #77) correctly WRITES the file; an all-default
# run with no versioning leaves $obj empty and stays ABSENT (unchanged #77). Same
# slot as the .sh twin so output stays byte-identical.
if ($versioningIn.Supplied) { $obj['versioning'] = $versioningIn.Value }

try {
    if ($obj.Count -eq 0) {
        # ConvertTo-Json on an empty ordered hashtable yields "{}" but guard
        # explicitly so the empty-state output is unambiguous and stable.
        $NewContent = '{}'
    } else {
        $NewContent = ($obj | ConvertTo-Json -Depth 5 -Compress:$false)
    }
} catch {
    [Console]::Error.WriteLine("ERROR: failed to serialize feeder.json: $($_.Exception.Message)")
    exit 2
}

# --- Resolve the destination path ----------------------------------------------
$ConfigDir  = Join-Path ($Repo.TrimEnd('/', '\')) '.milestone-config'
$ConfigFile = Join-Path $ConfigDir 'feeder.json'

# --- Never emit an empty {} — leave feeder.json ABSENT (issue #77) --------------
# (Same rationale as the bash twin.) An all-default run leaves $obj empty; rather
# than emit `{}`, leave the file absent so milestone-feeder's absent-only first-run
# setup fires. Non-destructive: never writes AND never deletes an existing file.
if ($obj.Count -eq 0) {
    Write-Output "All feeder keys at bundled defaults — leaving $ConfigFile absent so milestone-feeder's first-run setup fires."
    exit 0
}

# Guard: if the config path is an existing DIRECTORY, a later Move-Item -Force
# would move the temp file INTO it (feeder.json/<tmp>) and falsely report success
# — the real file would never be written. Refuse up front with a clear message.
# (Parity with the bash twin's directory guard.)
if (Test-Path -LiteralPath $ConfigFile -PathType Container) {
    [Console]::Error.WriteLine("ERROR: cannot write feeder.json: $ConfigFile exists and is a directory.")
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
# Initialize $tmp BEFORE the try so the catch can reference it safely. If
# New-Item below throws (e.g. unwritable path), control jumps to the catch
# before $tmp would otherwise be assigned; under Set-StrictMode an unassigned
# $tmp would raise a NEW error and bury the intended clean message + exit 2.
$tmp = $null
try {
    if (-not (Test-Path -LiteralPath $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    # Atomic-ish write via a temp file so a failure never leaves a partial file.
    # utf8NoBOM keeps the JSON BOM-free and portable (PS 7+ default, set
    # explicitly to be unambiguous).
    $tmp = Join-Path $ConfigDir ('.feeder.json.' + [System.IO.Path]::GetRandomFileName())
    Set-Content -LiteralPath $tmp -Value $NewContent -Encoding utf8NoBOM -NoNewline
    Add-Content -LiteralPath $tmp -Value "`n" -Encoding utf8NoBOM -NoNewline
    Move-Item -LiteralPath $tmp -Destination $ConfigFile -Force
} catch {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    [Console]::Error.WriteLine("ERROR: failed to write feeder.json to: $ConfigDir ($($_.Exception.Message))")
    exit 2
}

Write-Output "$ConfigFile written."
Write-Output $NewContent
exit 0
