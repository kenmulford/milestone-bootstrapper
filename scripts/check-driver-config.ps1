#!/usr/bin/env pwsh
#
# check-driver-config.ps1 — re-derive the milestone-driver `domainSkills` slice from
# live repo signals and set-compare it against what `.milestone-config/driver.json`
# already records, reporting drift. STRICTLY READ-ONLY: never writes or rewrites
# driver.json, on any code path (including under -Check). The PowerShell 7+ twin of
# check-driver-config.sh (suite cross-platform convention). Behavior, flags, exit
# codes, and the drift/no-drift determination are identical to the bash twin. The
# domainSkills-scoped sibling of check-project-docs.ps1 (which owns the `.project/`
# freshness slice); this script owns EXACTLY one field of one file — driver.json's
# `domainSkills` array — and touches nothing else. Advisory only: a human decides
# whether reported drift is real or an intentional override.
#
# What this does, in plain terms:
#   Re-runs scripts/detect-stack.ps1 against the repo to re-derive the detected
#   application stack(s), unions the `domainSkills` column of every NON-EXEMPT
#   app-stack row into a detected set, and set-compares it (order-insensitive,
#   duplicates collapsed) against driver.json's recorded `domainSkills` array. Any
#   difference in either direction is reported as DRIFT. It never edits driver.json;
#   it only reports.
#
# Reuse, never reimplement: the stack detection is scripts/detect-stack.ps1, invoked
#   as an external child pwsh process and parsed from its TSV stdout. This script
#   duplicates none of that per-stack detection logic. (detect-stack.ps1 calls
#   `exit`, so it MUST run in a child process, not via `&`/dot-source, or its exit
#   would terminate this script.) JSON parsing / set arithmetic uses the built-in
#   ConvertFrom-Json (no external tool — .project/library-manifest.md).
#
# Row classification (three-way; mirrors the sentinel predicate of
#   check-project-docs.ps1:146-161, then adds a Ruby-exemption layer):
#   - SENTINEL — a detect-stack TSV row with flag=="human" AND stack in
#     {none,(multi-stack)} is a meta row, not an application stack — excluded from
#     the compare and surfaced as an informational note. (A flag=="human" row that
#     is NOT one of those two, e.g. an unresolved-framework `Node ([TBD])` row, is
#     still a real app-stack row and IS compared.)
#   - EXEMPT — a non-sentinel row whose stack is EXACTLY `Ruby (Rails)` or
#     `Ruby (generic)` (detect-stack.ps1:264/272) is excluded from the compare
#     entirely (neither detected nor drift) and surfaced as a sentinel note.
#     detect-stack maps both Ruby rows to
#     ["ruby-lsp","superpowers:test-driven-development","superpowers:systematic-debugging"]
#     (detect-stack.ps1:259) — a documented, TRACKED divergence from the driver's
#     own Stack->domainSkills table (detect-stack.ps1:8-19, resolves #104), so
#     comparing it against driver.json would false-positive on every Ruby/Rails
#     repo. This is NOT an error in either script. Do NOT extend this allowlist.
#   - APP — every other row is a real, non-exempt application stack; its
#     `domainSkills` column (a JSON array literal or empty) joins the detected set.
#
# Nothing-to-compare (exit 0 ALWAYS, even under -Check):
#   - detect-stack finds NO application stack (solely the `none` sentinel,
#     detect-stack.ps1:307-316), OR every detected app-stack row is Ruby-exempt: the
#     non-exempt app set is empty, so there is nothing to compare.
#   - An empty DETECTED set with a non-empty RECORDED array is NOT this case — that
#     is a legitimate compare (every recorded entry reports as "recorded but not
#     detected"); it only happens when non-exempt app rows exist but all map to an
#     empty domainSkills column (e.g. Node (generic), .NET (non-MAUI), Rust).
#
# Inputs:
#   -Check          make drift a nonzero exit (CI gate). Without it, drift is
#                   informational only (exit 0).
#   -Repo <dir>     repo root to check (default: current directory). detect-stack
#                   is invoked against this dir and driver.json is read from
#                   <dir>/.milestone-config/driver.json. Mirrors detect-stack.ps1's
#                   [-RepoDir] convention; lets the check point at a fixture dir.
#   -Help           print this header comment.
#
# Exit codes (per-failure-class, mirroring check-project-docs.ps1):
#   0  ran cleanly — no drift; OR drift reported but -Check was NOT passed; OR
#      nothing to compare (no non-exempt application stack), always, even under
#      -Check.
#   1  usage / read error — bad flag, -Repo not a directory, missing driver.json,
#      malformed/missing domainSkills in driver.json, a detect-stack invocation
#      failure, or unparseable TSV output. ALWAYS nonzero regardless of -Check.
#   2  drift detected AND -Check was passed (the ONLY path where drift is nonzero).
#
# Run it:
#   ./scripts/check-driver-config.ps1
#   ./scripts/check-driver-config.ps1 -Check
#   ./scripts/check-driver-config.ps1 -Repo /path/to/other/repo -Check

[CmdletBinding()]
param(
    [switch]$Check,
    [string]$Repo,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Emit UTF-8 (BOM-less) on stdout so the — em dash in "DRIFT — " renders correctly
# across hosts (Windows PowerShell 5.1 would otherwise mangle it).
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$DriverRel   = '.milestone-config/driver.json'
$RubyRails   = 'Ruby (Rails)'
$RubyGeneric = 'Ruby (generic)'

if ($Help) {
    Get-Content -LiteralPath $PSCommandPath |
        Where-Object { $_ -match '^# ' } |
        ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

# --- Inputs -------------------------------------------------------------------
# Distinguish "flag never passed" from "flag passed empty" via ContainsKey
# (mirroring check-project-docs.ps1). `-Repo ''` must NOT silently default to cwd —
# it should fail the not-a-directory check, exactly as the bash twin does.
if (-not $PSBoundParameters.ContainsKey('Repo')) { $Repo = (Get-Location).Path }
$Repo = $Repo.TrimEnd('/', '\')
if ([string]::IsNullOrEmpty($Repo) -or -not (Test-Path -LiteralPath $Repo -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: -Repo is not a directory: $Repo")
    exit 1
}

# detect-stack.ps1 is a sibling of this script; find it via $PSScriptRoot (not
# -Repo), so -Repo can point at a fixture that has no scripts/ of its own.
$detect = Join-Path $PSScriptRoot 'detect-stack.ps1'
if (-not (Test-Path -LiteralPath $detect -PathType Leaf)) {
    [Console]::Error.WriteLine("ERROR: detect-stack.ps1 not found next to this script: $detect")
    exit 1
}

$driver = Join-Path $Repo $DriverRel

# --- Re-run detect-stack (external child pwsh; never reimplemented) -----------
$detectOut = & pwsh -NoProfile -File $detect $Repo 2>$null
$rc = $LASTEXITCODE
if ($rc -ne 0) {
    [Console]::Error.WriteLine("ERROR: detect-stack.ps1 failed (exit $rc) — the drift check could not run.")
    exit 1
}

# Check the "no output" condition on the RAW $detectOut BEFORE wrapping it in @():
# `@($null).Count` is 1 (the array-subexpression wraps $null into a 1-element array),
# so a `.Count -lt 1` check on the wrapped value is dead code and never fires. Test
# the raw value — $null, an empty array, or all-blank lines all mean "no output".
if ($null -eq $detectOut -or [string]::IsNullOrWhiteSpace(($detectOut -join "`n"))) {
    [Console]::Error.WriteLine('ERROR: detect-stack.ps1 produced no output — the drift check could not run.')
    exit 1
}
$rows = @($detectOut)
# First line MUST be the exact TSV header; otherwise the output is unparseable.
# Full-literal, case-sensitive (-cne) — identical to the bash twin's check.
$expectedHeader = "stack`tsignal`tconvention`tmanifestPin`tdomainSkills`tflag`tversionFile"
if ($rows[0] -cne $expectedHeader) {
    [Console]::Error.WriteLine('ERROR: detect-stack.ps1 output could not be parsed (missing TSV header) — the drift check could not run.')
    exit 1
}

# --- Classify rows: sentinel / Ruby-exempt / real app stack -------------------
$notes    = [System.Collections.Generic.List[string]]::new()
$appObjs  = [System.Collections.Generic.List[object]]::new()
$dataRows = if ($rows.Count -gt 1) { $rows[1..($rows.Count - 1)] } else { @() }
foreach ($line in $dataRows) {
    if ([string]::IsNullOrEmpty($line)) { continue }
    $cols   = $line -split "`t"
    $fStack = $cols[0]
    if ([string]::IsNullOrEmpty($fStack)) { continue }   # skip an empty-stack row (parity with bash awk `$1 == ""`)
    $fSkills = if ($cols.Count -ge 5) { $cols[4] } else { '' }
    $fFlag   = if ($cols.Count -ge 6) { $cols[5] } else { '' }
    if ($fFlag -eq 'human' -and ($fStack -eq 'none' -or $fStack -eq '(multi-stack)')) {
        $notes.Add("sentinel row — skipped: $fStack")
        continue
    }
    if ($fStack -eq $RubyRails -or $fStack -eq $RubyGeneric) {
        $notes.Add("exempt row — skipped (tracked divergence, resolves #104): $fStack")
        continue
    }
    # An empty domainSkills column is a legitimate empty array (omit rows), not an error.
    # Parse defensively: a malformed cell would otherwise throw an uncaught terminating
    # exception under $ErrorActionPreference='Stop' (raw .NET stack trace, exit 1) — a
    # different failure shape AND path than the bash twin. Fail cleanly as a usage/read
    # error (exit 1) with a framed message matching the bash twin. Only app rows reach
    # here; sentinel/exempt cells are unused. The parsed value must also be an array of
    # strings (reject numbers/booleans/objects) to match the bash array-of-strings check.
    if ([string]::IsNullOrWhiteSpace($fSkills)) {
        $skills = @()
    } else {
        $parseOk = $true
        # The RAW cell must be array-shaped ('['-leading) BEFORE parsing. ConvertFrom-Json
        # + the @() array-subexpression wrap ANY scalar (e.g. a bare JSON string
        # "solo-skill") into a 1-element array, indistinguishable from a genuine 1-element
        # array literal ["solo-skill"] — so the per-element string-type check ALONE would
        # silently accept a non-array cell. Discriminate on the raw text first, reusing
        # this repo's own idiom (write-driver-config.ps1:222, ConvertFrom-JsonArray), so
        # this twin rejects exactly the malformed input the bash twin rejects via jq's
        # `type=="array"` check (check-driver-config.sh:186) — twin parity, AC11.
        if ($fSkills.TrimStart() -notmatch '^\[') { $parseOk = $false }
        if ($parseOk) {
            try { $skills = @($fSkills | ConvertFrom-Json) } catch { $parseOk = $false }
        }
        if ($parseOk) {
            foreach ($el in $skills) { if ($el -isnot [string]) { $parseOk = $false; break } }
        }
        if (-not $parseOk) {
            [Console]::Error.WriteLine("ERROR: detect-stack.ps1 output could not be parsed (domainSkills for stack '$fStack' is not a valid JSON array) — the drift check could not run.")
            exit 1
        }
    }
    $appObjs.Add([pscustomobject]@{ Stack = $fStack; Skills = @($skills) })
}

# --- Print sentinel + exempt notes, in encounter order, before anything else --
foreach ($n in $notes) { Write-Output $n }

# --- Nothing to compare: no non-exempt app stack (exit 0, even under -Check) ---
if ($appObjs.Count -eq 0) {
    Write-Output 'nothing to compare — no non-exempt application stack detected.'
    exit 0
}

# --- There is something to compare: driver.json is now required ---------------
if (-not (Test-Path -LiteralPath $driver -PathType Leaf)) {
    [Console]::Error.WriteLine('ERROR: .milestone-config/driver.json not found — run milestone-driver:setup first.')
    exit 1
}
# domainSkills must be present AND a JSON array (an empty array [] is VALID). A
# parse failure, an absent key, or a non-array value all fail this one check.
$driverJson = $null
try { $driverJson = Get-Content -LiteralPath $driver -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $driverJson = $null }
$malformed = $false
if ($null -eq $driverJson) { $malformed = $true }
elseif (-not ($driverJson.PSObject.Properties.Name -contains 'domainSkills')) { $malformed = $true }
elseif (-not ($driverJson.domainSkills -is [array])) { $malformed = $true }
if ($malformed) {
    [Console]::Error.WriteLine('ERROR: .milestone-config/driver.json domainSkills is missing or malformed — fix the JSON, then re-run.')
    exit 1
}

# --- Set-compare recorded vs detected domainSkills ----------------------------
# Every set operation here is CASE-SENSITIVE to match jq's `unique` / `-` semantics
# in the bash twin (jq is case-sensitive; PowerShell's Sort-Object -Unique and
# -contains/-notcontains are case-INSENSITIVE by default, which would make the twins
# disagree — "Foo-Skill" vs "foo-skill" — violating twin parity, AC11).
$recorded = @($driverJson.domainSkills | Sort-Object -Unique -CaseSensitive)
$detectedList = [System.Collections.Generic.List[string]]::new()
foreach ($o in $appObjs) { foreach ($s in $o.Skills) { $detectedList.Add([string]$s) } }
$detected = @($detectedList | Sort-Object -Unique -CaseSensitive)

# Build the diff sets with the case-sensitive filters (unchanged), then order them
# with an EXPLICIT ORDINAL sort. jq's `sort` in the bash twin (check-driver-config.sh:
# 224-225) is strict ordinal/codepoint order; PowerShell's Sort-Object — even
# -CaseSensitive — is culture-aware and orders mixed-case values differently (jq puts
# every uppercase-leading string before every lowercase-leading one; culture sort
# interleaves them). Only [StringComparer]::Ordinal reproduces jq's print order, so the
# two twins emit byte-identical DRIFT lines for mixed-case domainSkills too (AC11).
# The arrays MUST be [string[]]-typed, not object[]: [array]::Sort(object[], IComparer)
# silently ignores the ordinal comparer and falls back to culture order, whereas
# [array]::Sort(string[], IComparer) honors it. @(...) yields object[], so cast first.
[string[]]$recordedNotDetected = @($recorded | Where-Object { $detected -cnotcontains $_ })
[string[]]$detectedNotRecorded = @($detected | Where-Object { $recorded -cnotcontains $_ })
[array]::Sort($recordedNotDetected, [System.StringComparer]::Ordinal)
[array]::Sort($detectedNotRecorded, [System.StringComparer]::Ordinal)

$driftLines = [System.Collections.Generic.List[string]]::new()
foreach ($skill in $recordedNotDetected) {
    $driftLines.Add("DRIFT — domainSkills '$skill' recorded in driver.json but not detected by any current app stack")
}
foreach ($skill in $detectedNotRecorded) {
    # Which non-exempt app-stack row(s) contributed this skill (case-sensitively deduped,
    # then ordinal-sorted, joined by ", "). Mirrors the bash twin's `unique | sort`
    # (check-driver-config.sh:250): jq `unique` is a case-sensitive dedup + sort, so use
    # -CaseSensitive uniquing then re-sort ordinally to keep the joined order identical.
    [string[]]$contrib = @($appObjs | Where-Object { $_.Skills -ccontains $skill } | ForEach-Object { $_.Stack } | Sort-Object -Unique -CaseSensitive)
    [array]::Sort($contrib, [System.StringComparer]::Ordinal)
    $contribStr = ($contrib -join ', ')
    $driftLines.Add("DRIFT — domainSkills '$skill' detected by app stack '$contribStr' but absent from driver.json")
}

# --- Report + exit ------------------------------------------------------------
if ($driftLines.Count -eq 0) {
    Write-Output 'no drift — driver.json domainSkills matches the currently detected app stack(s).'
    exit 0
}

foreach ($l in $driftLines) { Write-Output $l }
Write-Output "drift: $($driftLines.Count) domainSkills difference(s) between driver.json and detected app stack(s)."
if ($Check) { exit 2 }
Write-Output '(informational only — re-run with -Check to make drift a CI failure.)'
exit 0
