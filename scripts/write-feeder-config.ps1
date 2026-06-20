#!/usr/bin/env pwsh
#
# write-feeder-config.ps1 — write the target repo's `.milestone-config/feeder.json`
# config slice (the feeder-owned keys: `projectDocs`, `reviewer`).
#
# What this does, in plain terms:
#   The bootstrapper's `apply` skill (#13) leaves the TARGET repo with a valid
#   feeder profile so `milestone-feeder` runs with no further setup. `apply` is
#   non-interactive, so this is a deterministic, reusable writer it calls — NOT
#   the interactive `milestone-feeder:setup` interview (that path is interview-
#   only, with no non-interactive entry, so it cannot run unattended). Recorded
#   decision: issue #5 "✅ Design decision — Option A". This writer produces the
#   identical file `setup`'s Phase 3 would, to the same schema and the same
#   absent-means-default discipline. The PowerShell 7+ twin of
#   write-feeder-config.sh (suite cross-platform convention).
#
# Authoritative schema (DRIFT GUARDRAIL — do not widen without updating both):
#   The feeder-owned key set and the absent-means-default discipline are defined
#   by the canonical schema doc:
#     milestone-feeder/docs/profile-schema.md
#       - "Own keys" table          -> projectDocs (default ".project/"),
#                                       reviewer    (default "milestone-driver")
#       - "Absent-means-default discipline" -> omit a key left at its BUNDLED
#                                       default; an empty `{}` is a valid profile.
#   This slice writes ONLY `projectDocs` and `reviewer`. It deliberately does NOT
#   write the shared/driver keys (uiSurfaceGlobs, integrationBranch, the
#   consumer's sourceGlobs, domainSkills, versioning, nonNegotiables) — those are
#   read from the driver config and owned by the driver-config slice (#8). If the
#   feeder's schema gains or renames an own-key, update this script in lockstep.
#
# Inputs (resolved values — this writer does NOT re-derive them):
#   -Repo <dir>          target repo root (default: current directory)
#   -ProjectDocs <str>   the resolved `.project/` path from Job 1
#                        (default ".project/"; omitted when equal to the default)
#   -Reviewer <val>      "milestone-driver" | "internal" | false
#                        (default "milestone-driver"; omitted when equal to the
#                         BUNDLED default — so a resolved "internal" IS written)
#   Env fallbacks (params win): FEEDER_PROJECT_DOCS, FEEDER_REVIEWER, FEEDER_REPO.
#
# Behavior:
#   - ALWAYS writes the file (even `{}`) so config-presence is unambiguous.
#   - Idempotent / non-destructive: identical existing content is left byte-
#     identical (true no-op); re-runs never duplicate. (Key-level diff+patch of
#     human edits is the future `update` skill's job, not this writer's.)
#   - Errors (unwritable path, serialize failure) surface a clear message on
#     stderr and exit non-zero — never leaving a partial/invalid file in place.
#
# Run it:  ./scripts/write-feeder-config.ps1 -Repo /path/to/target [-ProjectDocs ...] [-Reviewer ...]
# Exit 0 = file is present and correct. Exit 1 = bad input. Exit 2 = write/serialize failure.

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$ProjectDocs,
    # Reviewer accepts the string enum or the boolean $false; typed as object so
    # `-Reviewer:$false` and `-Reviewer false` both round-trip to the JSON false.
    [object]$Reviewer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Bundled defaults (mirror milestone-feeder/docs/profile-schema.md) ---------
$DefaultProjectDocs = '.project/'
$DefaultReviewer    = 'milestone-driver'

# --- Inputs (params override env; env overrides default) -----------------------
if (-not $PSBoundParameters.ContainsKey('Repo')) {
    $Repo = if ($env:FEEDER_REPO) { $env:FEEDER_REPO } else { '.' }
}
if (-not $PSBoundParameters.ContainsKey('ProjectDocs')) {
    $ProjectDocs = if ($env:FEEDER_PROJECT_DOCS) { $env:FEEDER_PROJECT_DOCS } else { $DefaultProjectDocs }
}
if (-not $PSBoundParameters.ContainsKey('Reviewer')) {
    $Reviewer = if ($null -ne $env:FEEDER_REVIEWER -and $env:FEEDER_REVIEWER -ne '') { $env:FEEDER_REVIEWER } else { $DefaultReviewer }
}

# Normalize the string "false" (from env / positional) to the boolean $false.
if ($Reviewer -is [string] -and $Reviewer -eq 'false') { $Reviewer = $false }

# --- Validate reviewer against the schema's enum -------------------------------
$reviewerValid = ($Reviewer -is [bool] -and $Reviewer -eq $false) -or
                 ($Reviewer -is [string] -and ($Reviewer -in @('milestone-driver', 'internal')))
if (-not $reviewerValid) {
    [Console]::Error.WriteLine("ERROR: -Reviewer must be `"milestone-driver`", `"internal`", or `$false (got: $Reviewer).")
    exit 1
}

# --- Assemble the minimal object (absent-means-default: omit bundled defaults) --
# An ordered hashtable preserves key order in the serialized JSON; add only keys
# whose resolved value DIVERGES from the bundled default. An all-default run
# leaves it empty, which serializes to `{}`.
$obj = [ordered]@{}
if ($ProjectDocs -ne $DefaultProjectDocs) { $obj['projectDocs'] = $ProjectDocs }
# reviewer omit test is against the BUNDLED default, so a resolved "internal" or
# $false both diverge and ARE written.
$reviewerIsDefault = ($Reviewer -is [string]) -and ($Reviewer -eq $DefaultReviewer)
if (-not $reviewerIsDefault) { $obj['reviewer'] = $Reviewer }

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
