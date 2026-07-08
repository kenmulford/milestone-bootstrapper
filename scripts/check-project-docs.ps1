#!/usr/bin/env pwsh
#
# check-project-docs.ps1 — re-derive the machine-derivable slice of the `.project/`
# docs from live repo signals and diff it against what the docs already record,
# reporting drift. STRICTLY READ-ONLY: never writes or rewrites any `.project/`
# file, on any code path. The PowerShell 7+ twin of check-project-docs.sh (suite
# cross-platform convention). Behavior, flags, exit codes, and the drift/no-drift
# determination are identical to the bash twin.
#
# What this does, in plain terms:
#   Re-runs scripts/detect-stack.ps1 against the repo to re-derive the detected
#   application stack(s), then checks — for each detected stack — whether that
#   stack's identifying name appears in the captured content of
#   `.project/library-manifest.md#Runtime & frameworks`. A detected stack whose
#   name the manifest does NOT mention is reported as DRIFT. It never edits any
#   `.project/` file; it only reports. Scope is EXACTLY this one doc+anchor (the
#   whole of issue #129); it does not diff conventions.md, domainSkills, or any
#   other `.project/` doc.
#
# Reuse, never reimplement: the stack detection is scripts/detect-stack.ps1,
#   invoked as an external child pwsh process and parsed from its TSV stdout. This
#   script duplicates none of that per-stack detection logic. (detect-stack.ps1
#   calls `exit`, so it MUST run in a child process, not via `&`/dot-source, or its
#   exit would terminate this script.)
#
# Sentinel / skipped rows (surfaced as INFORMATIONAL notes, neither drift nor
#   no-drift — mirroring detect-stack's own flag-don't-guess discipline,
#   .project/design-philosophy.md#Error & failure philosophy):
#   - a detect-stack TSV row with flag=="human" AND stack in {none,(multi-stack)}
#     is a meta/sentinel row, not an application stack — excluded from comparison.
#     (A flag=="human" row that is NOT one of those two, e.g. an unresolved-
#     framework `Node ([TBD])` row, is still a real app-stack row and IS compared.)
#   - when detect-stack finds NO application stack at all (solely the `none`
#     sentinel), there is nothing to compare -> exit 0, always, even under -Check.
#   - a `Runtime & frameworks` anchor whose content is still the literal [TBD]
#     placeholder (never captured) is skipped and listed as "not yet captured".
#
# Drift definition: a PRESENCE check — the detected stack's FRAMEWORK-SPECIFIC
#   identifying token is matched case-insensitively as a substring of the anchor's
#   captured content. The identifying token is the parenthetical qualifier when it
#   names a real framework (e.g. `Rails` from `Ruby (Rails)`, `FastAPI` from
#   `Python (FastAPI)`); otherwise — no qualifier, or a generic/placeholder one
#   (`generic`, `non...`, `[TBD]`, or the bare runtime `Node`) — the base name
#   (e.g. `React` from `React (Node)`, `MAUI` from `.NET MAUI`, `Node` from
#   `Node (generic)`). Selecting the framework token (not any-token-of-the-name)
#   is what makes `React (Node)` require `React` and not be satisfied by a bare
#   `Node` mention. NOT a literal string-equality diff (which would false-positive
#   every run, since the manifest prose is human-composed, not a copy of the TSV).
#
# Inputs:
#   -Check          make drift a nonzero exit (CI gate). Without it, drift is
#                   informational only (exit 0).
#   -Repo <dir>     repo root to check (default: current directory). detect-stack
#                   is invoked against this dir and the manifest is read from
#                   <dir>/.project/library-manifest.md. Mirrors detect-stack.ps1's
#                   [-RepoDir] convention; lets the check point at a fixture dir.
#   -Help           print this header comment.
#
# Exit codes (per-failure-class, mirroring write-project-docs.ps1):
#   0  ran cleanly — no drift; OR drift reported but -Check was NOT passed; OR no
#      application stack detected ("nothing to compare"), always, even under
#      -Check; OR the sole in-scope anchor is [TBD] (skipped).
#   1  usage / read error — bad flag, -Repo not a directory, missing
#      `.project/library-manifest.md`, a detect-stack invocation failure, or
#      unparseable TSV output. ALWAYS nonzero regardless of -Check.
#   2  drift detected AND -Check was passed (the ONLY path where drift is nonzero).
#
# Run it:
#   ./scripts/check-project-docs.ps1
#   ./scripts/check-project-docs.ps1 -Check
#   ./scripts/check-project-docs.ps1 -Repo /path/to/other/repo -Check

[CmdletBinding()]
param(
    [switch]$Check,
    [string]$Repo,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Emit UTF-8 on stdout so the 🔴 marker in any passed-through detect-stack text
# survives across hosts (Windows PowerShell 5.1 would otherwise mangle it).
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$Anchor        = 'Runtime & frameworks'
$ManifestRel   = '.project/library-manifest.md'
$TbdToken      = '[TBD]'
$ManifestLabel = "$ManifestRel#$Anchor"

if ($Help) {
    Get-Content -LiteralPath $PSCommandPath |
        Where-Object { $_ -match '^# ' } |
        ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

# --- Inputs -------------------------------------------------------------------
# Distinguish "flag never passed" from "flag passed empty" via ContainsKey
# (mirroring write-project-docs.ps1). `-Repo ''` must NOT silently default to cwd
# — it should fail the not-a-directory check, exactly as the bash twin does (bash
# `${2:?}` only guards an UNSET arg, so `--repo ''` sets REPO='' and errors on the
# `[ -d ]` test). Only default to cwd when the param was never bound.
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

$manifest = Join-Path $Repo $ManifestRel

# --- Re-run detect-stack (external child pwsh; never reimplemented) -----------
$detectOut = & pwsh -NoProfile -File $detect $Repo 2>$null
$rc = $LASTEXITCODE
if ($rc -ne 0) {
    [Console]::Error.WriteLine("ERROR: detect-stack.ps1 failed (exit $rc) — the drift check could not run.")
    exit 1
}

$rows = @($detectOut)
if ($rows.Count -lt 1) {
    [Console]::Error.WriteLine('ERROR: detect-stack.ps1 produced no output — the drift check could not run.')
    exit 1
}
# First line MUST be the exact TSV header; otherwise the output is unparseable.
# Check the FULL literal header (the exact string detect-stack.ps1 always emits,
# detect-stack.ps1:305), case-sensitively (-cne) — stricter than the old prefix
# match AND identical to the bash twin's check, so the two cannot diverge on
# header strictness.
$expectedHeader = "stack`tsignal`tconvention`tmanifestPin`tdomainSkills`tflag`tversionFile"
if ($rows[0] -cne $expectedHeader) {
    [Console]::Error.WriteLine('ERROR: detect-stack.ps1 output could not be parsed (missing TSV header) — the drift check could not run.')
    exit 1
}

# --- Classify rows: application stacks vs meta/sentinel rows ------------------
$appStacks     = [System.Collections.Generic.List[string]]::new()
$sentinelNotes = [System.Collections.Generic.List[string]]::new()
$dataRows = if ($rows.Count -gt 1) { $rows[1..($rows.Count - 1)] } else { @() }
foreach ($line in $dataRows) {
    if ([string]::IsNullOrEmpty($line)) { continue }
    $cols   = $line -split "`t"
    $fStack = $cols[0]
    if ([string]::IsNullOrEmpty($fStack)) { continue }   # skip an empty-stack row (parity with bash awk `$1 == ""`)
    $fFlag  = if ($cols.Count -ge 6) { $cols[5] } else { '' }
    if ($fFlag -eq 'human' -and ($fStack -eq 'none' -or $fStack -eq '(multi-stack)')) {
        $sentinelNotes.Add("sentinel row — skipped: $fStack")
        continue
    }
    $appStacks.Add($fStack)
}

# --- No application stack at all: nothing to compare (exit 0, even under -Check)
# app-empty implies the solely-`none` sentinel (a `(multi-stack)` sentinel only
# ever appears alongside real app rows), so this is the legitimate none outcome —
# NOT the error path, and never conflated with a missing/uncaptured manifest.
if ($appStacks.Count -eq 0) {
    Write-Output "no application stack detected — nothing to compare ($ManifestLabel)."
    exit 0
}

# --- There are stacks to compare: the manifest anchor is now required ---------
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    [Console]::Error.WriteLine("ERROR: $ManifestRel not found — run apply first.")
    exit 1
}
$manifestText = Get-Content -LiteralPath $manifest -Raw
if ($null -eq $manifestText) { $manifestText = '' }
$manifestLines = ($manifestText -replace "`r`n", "`n").Split("`n")

# Extract the anchor's section body: every line after the `## <Anchor>` heading up
# to (excluding) the next `## ` heading. Case-sensitive (-cmatch), like the bash
# twin's awk. The heading pattern is built FROM $Anchor so the anchor name has
# exactly one source of truth (not a second hardcoded literal). Read-only.
# NOTE: this anchor-walk deliberately duplicates the "track current `## ` heading"
# algorithm in write-project-docs.ps1. Extracting a shared read-doc-section.ps1
# helper (which does not exist in this repo yet) would touch write-project-docs.ps1
# — out of #129's file scope — so the duplication is a deliberate scope decision;
# that helper is the natural follow-up if a third caller ever needs the pattern.
$anchorPattern = "^## $Anchor" + '[ \t]*$'
$anchorFound = $false
$section = [System.Collections.Generic.List[string]]::new()
$ins = $false
foreach ($ln in $manifestLines) {
    if ($ln -cmatch '^## ') {
        if ($ins) { break }
        if ($ln -cmatch $anchorPattern) { $ins = $true; $anchorFound = $true; continue }
    }
    if ($ins) { $section.Add($ln) }
}
if (-not $anchorFound) {
    [Console]::Error.WriteLine("ERROR: anchor '## $Anchor' not found in $ManifestRel — the drift check could not run.")
    exit 1
}
$sectionText = ($section -join "`n")

# Informational notes (e.g. a (multi-stack) sentinel alongside the real rows).
foreach ($n in $sentinelNotes) { Write-Output $n }

# --- [TBD] (never captured): skip the anchor entirely -------------------------
# The only in-scope anchor is uncaptured, so there is nothing to compare -> no
# drift (exit 0, even under -Check). Neither drift nor no-drift; listed as such.
if ($sectionText.Contains($TbdToken)) {
    Write-Output "skipped — $ManifestLabel not yet captured ($TbdToken); nothing to compare."
    exit 0
}

# --- Presence check: each detected stack's identifying name in the content ----
$sectionLc = $sectionText.ToLowerInvariant()
# One-line snippet for the drift report ("checked against").
$snippet = (($sectionText -replace "`n", ' ') -replace '\s+', ' ').Trim()
if ($snippet.Length -gt 140) { $snippet = $snippet.Substring(0, 137) + '...' }

$driftLines = [System.Collections.Generic.List[string]]::new()
foreach ($stack in $appStacks) {
    # Select the FRAMEWORK-SPECIFIC identifying source for this stack, structurally
    # (parse the `(...)` group), NOT by a hand-maintained word stoplist:
    #   - a `(...)` qualifier that names a real framework IS the identifying source
    #     (`Ruby (Rails)` -> Rails; `Python (FastAPI)` -> FastAPI);
    #   - a generic/placeholder qualifier (`generic`, `non...`, `[TBD]`, or the
    #     bare runtime `Node`) means the framework is in the BASE, so fall back to
    #     it (`React (Node)` -> React; `Node (generic)` -> Node; `.NET (non-MAUI)`
    #     -> .NET; `Node ([TBD])` -> Node);
    #   - no `(...)` at all -> the whole name is the source (`.NET MAUI` -> .NET
    #     MAUI; `Rust` -> Rust; `Claude Code plugin` -> that phrase).
    # This makes `React (Node)` require `React` (not be satisfied by a bare `Node`)
    # — the issue's worked example — and keeps both twins selecting identical tokens.
    if ($stack -match '^(.*?)\(([^)]*)\)') {
        $base   = $Matches[1].Trim()
        $qual   = $Matches[2].Trim()
        $qualLc = $qual.ToLowerInvariant()
        if ($qualLc -eq 'generic' -or $qualLc -eq 'node' -or $qualLc -like 'non*' -or $qualLc -like '*tbd*') {
            $idSrc = $base
        } else {
            $idSrc = $qual
        }
    } else {
        $idSrc = $stack
    }
    # Tokenize the identifying source: replace every non-[alnum . + #] char with a
    # space, split on whitespace. Present if ANY token is a case-insensitive
    # substring of the captured content (per the issue's locked substring match).
    $toks = ($idSrc -replace '[^A-Za-z0-9.+#]', ' ') -split '\s+'
    $present = $false
    foreach ($tok in $toks) {
        if ([string]::IsNullOrEmpty($tok)) { continue }
        $tokLc = $tok.ToLowerInvariant()
        if ($tokLc -notmatch '[a-z0-9]') { continue }                 # must carry an alnum
        if ($sectionLc.Contains($tokLc)) { $present = $true; break }
    }
    if (-not $present) {
        $driftLines.Add("DRIFT — $ManifestLabel does not mention detected stack '$stack' (checked against: `"$snippet`")")
    }
}

# --- Report + exit ------------------------------------------------------------
if ($driftLines.Count -eq 0) {
    Write-Output "no drift — every detected stack is recorded in $ManifestLabel."
    exit 0
}

foreach ($l in $driftLines) { Write-Output $l }
Write-Output "drift: $($driftLines.Count) detected stack(s) not found in $ManifestLabel."
if ($Check) { exit 2 }
Write-Output '(informational only — re-run with -Check to make drift a CI failure.)'
exit 0
