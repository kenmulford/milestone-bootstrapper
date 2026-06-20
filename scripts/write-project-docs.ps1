#!/usr/bin/env pwsh
#
# write-project-docs.ps1 — place resolved interview/detection content into a
# `.project/` doc template by replacing the `[TBD]` placeholder UNDER each stable
# `##` anchor. The PowerShell 7+ twin of write-project-docs.sh (suite cross-
# platform convention). Behavior, flags, exit codes, and the placement algorithm
# are identical to the bash twin.
#
# What this does, in plain terms:
#   The `plan` / `apply` skills (#9/#13) compose the understanding-interview
#   answers (#4, docs/understanding-interview.md) with the stack detection (#3,
#   scripts/detect-stack.sh) into a per-anchor content map, then call THIS writer
#   to do the deterministic mechanical placement. The COMPOSITION judgment — which
#   value belongs under which anchor, and whether a field is captured / "None" /
#   a genuine unknown — is done UPSTREAM. This writer does not interview, does not
#   detect, and does not decide; it places already-resolved content under the
#   anchor the caller names, exactly, and never anywhere else.
#
# The field -> doc -> anchor routing this serves is FIXED and authoritative in
# docs/understanding-interview.md §2 and SPEC.md §5/§6. The caller keys the input
# map by the correct anchor; this writer only verifies the anchor EXISTS in the
# template (and errors loudly if it does not — a renamed or missing heading is
# never silently skipped).
#
# Recording discipline (docs/understanding-interview.md §3, SPEC.md §4.3) — the
# three states are kept distinct and NEVER collapsed:
#   - captured : a real answer            -> replace the placeholder.
#   - none     : a recorded "None" answer -> replace the placeholder (NO 🔴).
#   - tbd      : a genuine unknown        -> LEAVE the [TBD] in place and flag 🔴.
#   An anchor present in the template but NOT named by any input entry is left
#   untouched (still [TBD]) — partial population is legitimate. Only an input
#   anchor MISSING from the template is an error.
#
# Append-only anchor discipline (§3.1): never renames / rewords / reorders a `##`
# heading; never invents a heading; never touches `[TBD]` tokens inside the
# leading <!-- ... --> header comment (those sit before the first `##` heading, so
# they are structurally out of reach).
#
# Inputs:
#   -Template <file>   the `.project/` doc to populate (edited in place). REQUIRED.
#   -Map <file>        JSON map keyed by exact `##` anchor text (WITHOUT "## ").
#                      Each value: { "state": "captured"|"none"|"tbd", "content": "<text>" }
#                      `content` may be multi-line; it replaces the WHOLE contiguous
#                      [TBD] placeholder block under that anchor. For "tbd", content
#                      is ignored and the placeholder is kept + flagged.
#   -Anchor <text>     single-anchor mode: exact `##` heading text (no "## ").
#   -State <s>         single-anchor mode: captured | none | tbd (default captured).
#   -Content <text>    single-anchor mode: the replacement content.
#   -Repo <dir>        accepted for suite-flag parity; ignored.
#   Env fallbacks (params win): PROJECT_DOCS_TEMPLATE, PROJECT_DOCS_MAP.
#
# Behavior: idempotent (same map -> byte-identical file; pure no-op leaves the
# file untouched), atomic temp-file write, BOM-free UTF-8 output.
#
# Exit codes:
#   0  populated (or already up to date — true no-op).
#   1  bad input / usage (missing flag, unreadable file, malformed map JSON).
#   2  write / serialize failure.
#   3  unmatched anchor — an input anchor is NOT a `##` heading (renamed/missing
#      heading). Loud failure; the file is left UNCHANGED.
#
# Run it:
#   ./scripts/write-project-docs.ps1 -Template .project/environment.md -Map caps.json
#   ./scripts/write-project-docs.ps1 -Template .project/environment.md `
#       -Anchor "Caching" -State none -Content "None — no cache layer."

[CmdletBinding()]
param(
    [string]$Template,
    [string]$Map,
    [string]$Anchor,
    [string]$State = 'captured',
    [string]$Content,
    [string]$Repo   # accepted for suite-flag parity; unused
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# 🔴 built from its surrogate pair so the marker is correct regardless of how the
# source file's own encoding is interpreted by the host.
$Flag     = "$([char]0xD83D)$([char]0xDD34)"
$TbdToken = '[TBD]'

# Drop trailing empty elements from a string array. PowerShell's `$a[0..($n-1)]`
# range slice silently turns into a reverse/wrap slice when $n hits 0 (`0..-1`),
# so truncate by counting the trailing empties and slicing with explicit guards
# (empty input or an all-empty array both yield an empty array).
#
# `-All` drops EVERY trailing empty — used for template lines, parity with the
# bash twin reading the template via `$(cat ...)`, which strips all trailing
# newlines (an all-blank template collapses to nothing, re-gaining one `\n` on the
# final write).
#
# Without `-All`, drop exactly ONE trailing empty, and only when the array has
# more than one element — used for the content split. This is parity with the bash
# awk pass: its getline treats `\n` as a record TERMINATOR, so content ending in
# `\n` loses that final newline, but empty content (or a lone `\n`) still emits one
# line (one blank). The >1 guard keeps that single-element base case intact;
# interior blank lines are always preserved.
function Remove-TrailingEmpty {
    param([string[]]$Items, [switch]$All)
    if ($null -eq $Items -or $Items.Count -eq 0) { return @() }
    $end = $Items.Count - 1
    if ($All) {
        while ($end -ge 0 -and $Items[$end] -eq '') { $end-- }
    } elseif ($Items.Count -gt 1 -and $Items[$end] -eq '') {
        $end--
    }
    if ($end -lt 0) { return @() }
    return ,@($Items[0..$end])
}

# --- Inputs (params override env) ---------------------------------------------
if (-not $PSBoundParameters.ContainsKey('Template')) {
    $Template = if ($env:PROJECT_DOCS_TEMPLATE) { $env:PROJECT_DOCS_TEMPLATE } else { '' }
}
if (-not $PSBoundParameters.ContainsKey('Map')) {
    $Map = if ($env:PROJECT_DOCS_MAP) { $env:PROJECT_DOCS_MAP } else { '' }
}
$haveSingle = $PSBoundParameters.ContainsKey('Anchor') -or
              $PSBoundParameters.ContainsKey('State')  -or
              $PSBoundParameters.ContainsKey('Content')

# --- Validate inputs ----------------------------------------------------------
if (-not $Template) {
    [Console]::Error.WriteLine('ERROR: -Template is required.')
    exit 1
}
if (-not (Test-Path -LiteralPath $Template -PathType Leaf)) {
    [Console]::Error.WriteLine("ERROR: template not found or not a file: $Template")
    exit 1
}

if ($haveSingle -and $Map) {
    [Console]::Error.WriteLine('ERROR: use either -Map OR the single-anchor params (-Anchor/-State/-Content), not both.')
    exit 1
}

# Build the placement map (anchor -> @{ state; content }) from whichever mode.
$placeMap = [ordered]@{}
if ($haveSingle) {
    if (-not $Anchor) {
        [Console]::Error.WriteLine('ERROR: single-anchor mode needs -Anchor.')
        exit 1
    }
    if ($State -notin @('captured', 'none', 'tbd')) {
        [Console]::Error.WriteLine("ERROR: -State must be captured | none | tbd (got: $State).")
        exit 1
    }
    $singleContent = if ($null -ne $Content) { $Content } else { '' }
    $placeMap[$Anchor] = @{ state = $State; content = $singleContent }
} else {
    if (-not $Map) {
        [Console]::Error.WriteLine('ERROR: provide -Map <file> or the single-anchor params.')
        exit 1
    }
    if (-not (Test-Path -LiteralPath $Map -PathType Leaf)) {
        [Console]::Error.WriteLine("ERROR: map file not found or not a file: $Map")
        exit 1
    }
    try {
        $raw = Get-Content -LiteralPath $Map -Raw
        # -AsHashtable preserves arbitrary anchor keys; -Ordered keeps input order.
        $parsed = $raw | ConvertFrom-Json -AsHashtable
    } catch {
        [Console]::Error.WriteLine("ERROR: -Map is not valid JSON: $Map")
        exit 1
    }
    foreach ($key in $parsed.Keys) {
        $val = $parsed[$key]
        if ($val -isnot [System.Collections.IDictionary]) {
            [Console]::Error.WriteLine("ERROR: map entry for anchor '$key' must be an object { state, content }.")
            exit 1
        }
        $st = if ($val.Contains('state') -and $null -ne $val['state']) { [string]$val['state'] } else { 'captured' }
        if ($st -notin @('captured', 'none', 'tbd')) {
            [Console]::Error.WriteLine("ERROR: map entry for anchor '$key' has invalid state '$st' (want captured|none|tbd).")
            exit 1
        }
        $ct = if ($val.Contains('content') -and $null -ne $val['content']) { [string]$val['content'] } else { '' }
        $placeMap[$key] = @{ state = $st; content = $ct }
    }
}

# --- Read the template as lines (normalize CRLF -> LF for a single code path) ---
$rawTemplate = Get-Content -LiteralPath $Template -Raw
if ($null -eq $rawTemplate) { $rawTemplate = '' }
$normalized = $rawTemplate -replace "`r`n", "`n"
# Split on LF (String.Split keeps every empty element). Drop ALL trailing empty
# elements, not just one: the bash twin reads the template via `$(cat ...)`, which
# strips every trailing newline, and the final write re-adds exactly one — so a
# template ending in `\n\n\n` collapses to a single trailing `\n`. Stripping only
# the last empty element here would keep the extra blank lines and diverge from
# bash (and from this script's own TrimEnd-based no-op check below). NB: do NOT use
# `-split "`n", -1`; the -1 max-substrings arg collapses the result to a single
# element. String.Split on the LF char is unambiguous.
$lines = Remove-TrailingEmpty -Items $normalized.Split("`n") -All

# --- Pre-flight: every input anchor MUST be a `##` heading in the template ------
$templateAnchors = @{}
foreach ($ln in $lines) {
    if ($ln -match '^## (.+)$') { $templateAnchors[$Matches[1]] = $true }
}
$missing = @()
foreach ($want in $placeMap.Keys) {
    if (-not $templateAnchors.ContainsKey($want)) { $missing += $want }
}
if ($missing.Count -gt 0) {
    [Console]::Error.WriteLine("ERROR: unmatched anchor(s) — not a '## ' heading in ${Template}:")
    foreach ($m in $missing) { [Console]::Error.WriteLine("  - $m") }
    [Console]::Error.WriteLine('  (a renamed/missing heading breaks citations; the template was NOT modified.)')
    exit 3
}

# --- Place content under each anchor ------------------------------------------
# Walk the lines, tracking the current `## ` heading. Within a mapped anchor, the
# FIRST contiguous run of [TBD]-bearing lines is the placeholder block; replace it
# (captured/none) or keep+flag it (tbd). Mirrors the bash awk pass exactly.
$out = [System.Collections.Generic.List[string]]::new()
$cur = ''
$inblock = $false
$seen = @{}

foreach ($line in $lines) {
    if ($line -like '## *') {
        $cur = $line.Substring(3)
        $inblock = $false
        $out.Add($line)
        continue
    }
    if ($cur -ne '' -and $placeMap.Contains($cur) -and -not $seen.ContainsKey($cur)) {
        if ($line.Contains($TbdToken)) {
            if (-not $inblock) {
                $inblock = $true
                if ($placeMap[$cur].state -eq 'tbd') {
                    if (-not $line.Contains($Flag)) { $out.Add("$line $Flag") } else { $out.Add($line) }
                } else {
                    # captured / none: replace the whole block with the content,
                    # split on LF into its own lines. Drop a single trailing empty
                    # element so content ending in `\n` does not emit a spurious
                    # blank line — parity with the bash awk pass, whose getline
                    # drops the content's final newline (a record terminator, not
                    # data). Interior blank lines are preserved.
                    foreach ($cl in (Remove-TrailingEmpty -Items $placeMap[$cur].content.Split("`n"))) { $out.Add($cl) }
                }
            } else {
                if ($placeMap[$cur].state -eq 'tbd') {
                    if (-not $line.Contains($Flag)) { $out.Add("$line $Flag") } else { $out.Add($line) }
                }
                # captured/none: drop extra placeholder lines (already replaced).
            }
            continue
        } else {
            if ($inblock) { $inblock = $false; $seen[$cur] = $true }
            $out.Add($line)
            continue
        }
    }
    $out.Add($line)
}

# Join with LF and a single trailing newline (parity with the bash twin).
$newContent = ($out -join "`n") + "`n"

# --- Idempotent no-op ---------------------------------------------------------
# Compare against the template normalized the same way (LF, single trailing LF).
$existingNorm = ($normalized.TrimEnd("`n")) + "`n"
if ($existingNorm -eq $newContent) {
    Write-Output "$Template already up to date (no change)."
    exit 0
}

# --- Atomic write -------------------------------------------------------------
$destDir = Split-Path -Parent (Resolve-Path -LiteralPath $Template).Path
$tmp = $null
try {
    $tmp = Join-Path $destDir ('.write-project-docs.' + [System.IO.Path]::GetRandomFileName())
    # utf8NoBOM keeps the doc BOM-free and portable (PS 7+ default; set explicitly).
    # -NoNewline so we control the single trailing newline already in $newContent.
    Set-Content -LiteralPath $tmp -Value $newContent -Encoding utf8NoBOM -NoNewline
    Move-Item -LiteralPath $tmp -Destination $Template -Force
} catch {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    [Console]::Error.WriteLine("ERROR: failed to write populated doc to: $destDir ($($_.Exception.Message))")
    exit 2
}

Write-Output "$Template populated."
exit 0
