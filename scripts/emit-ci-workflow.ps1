#!/usr/bin/env pwsh
#
# emit-ci-workflow.ps1 — emit the target repo's `.github/workflows/ci.yml`: the
# GitHub Actions workflow that gates PRs into the integration branch on the
# project's detected test/preflight commands.
#
# What this does, in plain terms:
#   The bootstrapper's `apply` skill makes the TARGET repo suite-ready (Job 2
#   "CI workflow", BRIEF.md:51). The last consequential write is the CI workflow,
#   because branch protection (#12) registers this workflow's job names as the
#   required status checks and `milestone-driver`'s per-PR merge gate (#13) waits
#   on them. This is the deterministic, reusable writer `apply` calls to produce
#   that file. The PowerShell 7+ twin of emit-ci-workflow.sh (suite cross-platform
#   convention) — the two emit byte-identical YAML.
#
#   It does NOT re-detect or re-decide anything: it CONSUMES the values #8 already
#   resolved into `.milestone-config/driver.json` — the `integrationBranch` (PR
#   target), the `unitTestCmd`, and the `preflightCmd`. GitHub Actions is the only
#   CI provider in v1; non-GitHub providers are out of scope (BRIEF.md:76).
#
# Mirrors the sibling CI pattern EXACTLY (the single structural source of truth):
#   milestone-feeder/.github/workflows/ci.yml:20-52
#     - `on: pull_request` with a `branches:` filter        (:20-22)
#     - `permissions: contents: read`                       (:24-25)
#     - `concurrency` keyed on `${{ github.workflow }}-${{ github.ref }}`
#       with `cancel-in-progress: true`                      (:27-29)
#     - one `runs-on: ubuntu-latest` job per gate whose `name:` is the
#       human-readable required-status-check context         (:31-52)
#     - each job checks out (`actions/checkout`) then runs its command
#   The comment at that file's :13-18 declares the job names as the contexts to
#   wire in branch protection — the same contract this writer upholds (below).
#
# CONTEXT-NAME STABILITY CONTRACT (do not drift — #12 and #13 consume these):
#   The job `name:` values this writer emits ARE the required-status-check context
#   strings branch protection (#12) registers and the merge gate (#13) waits on.
#   They are FIXED, regardless of which commands are present:
#     - the unit-test gate's context is  ->  unit-tests
#     - the preflight    gate's context is ->  preflight
#   Changing either string here is a breaking change that MUST be made in lockstep
#   with #12's protection registration and #13's gate. A `[TBD]`-flagged command
#   does NOT change the context name — the job (and thus the context) still exists
#   so protection has a stable check to require; only the command step is flagged.
#
# Inputs:
#   -Repo <dir>   target repo root (default: current directory). The writer reads
#                 <repo>/.milestone-config/driver.json and writes
#                 <repo>/.github/workflows/ci.yml.
#   Env fallback (param wins): CI_EMIT_REPO.
#
# Behavior (acceptance criteria, issue #11):
#   - Happy path: `driver.json` records an `integrationBranch` and a `unitTestCmd`
#     and/or `preflightCmd` -> emit `on: pull_request` into that branch with one
#     named job per recorded command running that command.
#   - Absent command (flag-don't-guess, BRIEF.md:30,67): a command that is absent
#     from `driver.json` still gets its job (so the status-check context exists),
#     but the run step is a `[TBD]` placeholder that fails loudly, AND the missing
#     command is flagged to the human on stderr with 🔴. A command is NEVER
#     fabricated. If only one command is absent, only that job is `[TBD]`-flagged.
#   - Absent integrationBranch: the `pull_request` branch filter cannot be
#     resolved. The branch is left as a flagged `[TBD]` (never a guessed branch),
#     and the missing `integrationBranch` is flagged to the human with 🔴. The
#     file is still valid YAML and still names its jobs.
#   - Error / failure path (never a silent failure, BRIEF.md:82): a missing or
#     malformed `driver.json`, or an unwritable `.github/workflows/` path, surfaces
#     a clear message naming the precondition and exits non-zero — no partial or
#     invalid file is left behind (atomic temp-file write).
#   - Idempotent / non-destructive (BRIEF.md:54,65): an absent file is created; a
#     file byte-identical to what we'd emit is left untouched (true no-op). A file
#     that EXISTS but DIFFERS is NOT clobbered — human edits are preserved and the
#     divergence is flagged; reconciling a changed plan onto an existing file is
#     `update`'s diff-first job, not this `apply`-time writer's.
#
# Run it:  ./scripts/emit-ci-workflow.ps1 -Repo /path/to/target
# Exit 0 = file is present and correct (incl. emitted-with-[TBD]-flags, and the
#          no-op case). Exit 1 = bad input / unreadable-or-malformed driver.json.
# Exit 2 = write/serialize failure. Exit 3 = existing file diverges (not clobbered;
#          run `update` to reconcile).

[CmdletBinding()]
param(
    [string]$Repo
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- CONTEXT-NAME STABILITY CONTRACT: the fixed required-status-check contexts --
# These two strings are the contract #12 registers and #13 waits on. Editing them
# is a breaking change — keep in lockstep with #12/#13 and with the .sh twin.
$UnitTestsContext = 'unit-tests'
$PreflightContext = 'preflight'

# --- Inputs (param overrides env; env overrides default) -----------------------
if (-not $PSBoundParameters.ContainsKey('Repo')) {
    $Repo = if ($env:CI_EMIT_REPO) { $env:CI_EMIT_REPO } else { '.' }
}

# --- Read the resolved values from driver.json (#8's output) -------------------
$DriverFile = Join-Path ($Repo.TrimEnd('/', '\')) '.milestone-config/driver.json'

if (-not (Test-Path -LiteralPath $DriverFile -PathType Leaf)) {
    [Console]::Error.WriteLine("ERROR: cannot read driver config: $DriverFile not found.")
    [Console]::Error.WriteLine("       Run the driver-config writer (#8) first so the integration branch and test commands are recorded.")
    exit 1
}

# Parse once; a malformed driver.json is a clear, non-silent failure (never emit
# a partial/guessed workflow from unreadable config).
try {
    $raw = Get-Content -LiteralPath $DriverFile -Raw
    if ($null -eq $raw) { $raw = '' }
    $driver = $raw | ConvertFrom-Json
} catch {
    [Console]::Error.WriteLine("ERROR: cannot parse driver config: $DriverFile is not valid JSON.")
    [Console]::Error.WriteLine("       ($($_.Exception.Message))")
    exit 1
}

# Shape gate: the config MUST be a JSON object. ConvertFrom-Json does NOT throw on
# valid-but-non-object input — an empty/whitespace/null file yields $null, a
# top-level array yields object[], and a bare string/number yields a primitive.
# None of those have the keys to read, so without this gate the writer would
# silently emit a fully-[TBD] ci.yml. Reject it here as a clear precondition
# failure (exit 1, no file) — byte-identical with the .sh twin's `type=="object"`.
# A JSON object deserializes to PSCustomObject; anything else (incl. $null) fails.
if ($driver -isnot [System.Management.Automation.PSCustomObject]) {
    [Console]::Error.WriteLine("ERROR: $DriverFile is not a JSON object.")
    [Console]::Error.WriteLine("       Expected an object recording integrationBranch and the test commands; got a non-object JSON value. Re-run the driver-config writer (#8).")
    exit 1
}

# Extract the three values. A missing property, $null, or a non-string value all
# mean "not recorded" — exactly the [TBD]-flag trigger below. (StrictMode-safe
# property access via PSObject.Properties.)
function Get-StringProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return '' }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return '' }
    $val = $prop.Value
    if ($val -is [string]) { return $val }
    return ''
}

$IntegrationBranch = Get-StringProp $driver 'integrationBranch'
$UnitTestCmd       = Get-StringProp $driver 'unitTestCmd'
$PreflightCmd      = Get-StringProp $driver 'preflightCmd'

# --- Resolve the trigger branch (flag-don't-guess when absent) -----------------
# An absent integrationBranch is flagged and rendered as a [TBD] branch filter —
# the file stays valid YAML and never gates against a guessed branch.
$flags = [System.Collections.Generic.List[string]]::new()
if ($IntegrationBranch -ne '') {
    $BranchFilter = $IntegrationBranch
} else {
    $BranchFilter = '[TBD]'
    $flags.Add("🔴 integrationBranch is absent from $DriverFile — the pull_request branch filter is left as [TBD]. Record it (re-run #8) and re-emit; the workflow will not gate any PR until the branch is set.")
}

# --- Resolve each command's run step (flag-don't-guess when absent) ------------
# A [TBD] command renders a step that FAILS LOUDLY rather than silently passing,
# so a forgotten command can never let a PR merge unchecked. The job (and thus the
# status-check context) still exists either way — the context name never drifts.
$TbdRun = 'echo "::error::milestone-bootstrapper: this command is [TBD] — record it in .milestone-config/driver.json and re-run apply/update." && exit 1'

if ($UnitTestCmd -ne '') {
    $UnitRun = $UnitTestCmd
} else {
    $UnitRun = $TbdRun
    $flags.Add("🔴 unitTestCmd is absent from $DriverFile — the '$UnitTestsContext' job runs a [TBD] placeholder that fails until a command is recorded. No command was fabricated.")
}

if ($PreflightCmd -ne '') {
    $PreflightRun = $PreflightCmd
} else {
    $PreflightRun = $TbdRun
    $flags.Add("🔴 preflightCmd is absent from $DriverFile — the '$PreflightContext' job runs a [TBD] placeholder that fails until a command is recorded. No command was fabricated.")
}

# --- Assemble the workflow YAML (mirrors the sibling structure exactly) --------
# The four resolved values (branch filter + two run lines, both single-line by
# construction) are emitted as YAML single-quoted scalars so an arbitrary command
# (which may contain ${{ }}, ':', '#', or other YAML-significant characters) is
# always a valid, unambiguous scalar. Per YAML, a single-quote inside a
# single-quoted scalar is escaped by doubling it.
function ConvertTo-YamlSQuote { param([string]$Value) return $Value.Replace("'", "''") }

$BranchFilterQ = ConvertTo-YamlSQuote $BranchFilter
$UnitRunQ      = ConvertTo-YamlSQuote $UnitRun
$PreflightRunQ = ConvertTo-YamlSQuote $PreflightRun

# A single-quoted PowerShell here-string performs NO interpolation; the resolved
# values are substituted explicitly so the YAML frame stays byte-identical to the
# bash twin. The `${{ }}` GitHub expressions are literal here (no $-expansion).
$NewContent = @"
name: CI

# CI gate for PRs into the integration branch. Emitted by milestone-bootstrapper
# from .milestone-config/driver.json (#8's output) — do not hand-edit the command
# steps or job names here; change them in driver.json and re-run apply/update.
#
# The two job names below ("$UnitTestsContext" and "$PreflightContext") are the
# required-status-check contexts wired into branch protection. They are a stable
# contract — branch protection (#12) requires these exact strings and the per-PR
# merge gate (#13) waits on them. A [TBD] command step means the command was not
# recorded in driver.json yet; record it and re-emit.
#
# Runs on pull_request only: required status checks are evaluated on PRs, so a
# push-triggered run would gate nothing and only add noise on the protected
# branch tip.

on:
  pull_request:
    branches: ['$BranchFilterQ']

permissions:
  contents: read

concurrency:
  group: `${{ github.workflow }}-`${{ github.ref }}
  cancel-in-progress: true

jobs:
  ${UnitTestsContext}:
    name: $UnitTestsContext
    runs-on: ubuntu-latest
    steps:
      - name: Check out the code under review
        uses: actions/checkout@v7
      - name: Run the unit-test gate
        run: '$UnitRunQ'

  ${PreflightContext}:
    name: $PreflightContext
    runs-on: ubuntu-latest
    steps:
      - name: Check out the code under review
        uses: actions/checkout@v7
      - name: Run the preflight gate
        run: '$PreflightRunQ'
"@

# Normalize to LF so output is byte-identical to the bash twin on every host
# (here-strings carry the file's own newline; the repo policy is LF — .gitattributes).
$NewContent = $NewContent -replace "`r`n", "`n"

# --- Resolve the destination path ----------------------------------------------
$WorkflowsDir = Join-Path ($Repo.TrimEnd('/', '\')) '.github/workflows'
$WorkflowFile = Join-Path $WorkflowsDir 'ci.yml'

# Guard: if the workflow path is an existing DIRECTORY, a later Move-Item -Force
# would move the temp file INTO it (ci.yml/<tmp>) and falsely report success —
# the real file would never be written. Refuse up front with a clear message.
if (Test-Path -LiteralPath $WorkflowFile -PathType Container) {
    [Console]::Error.WriteLine("ERROR: cannot write CI workflow: $WorkflowFile exists and is a directory.")
    exit 2
}

# --- Emit any accumulated 🔴 flags to stderr (never silent) --------------------
function Write-Flags {
    foreach ($f in $flags) { [Console]::Error.WriteLine("milestone-bootstrapper: $f") }
}

# --- Idempotent / non-destructive ----------------------------------------------
# Absent -> create. Byte-identical -> true no-op. Exists-but-differs -> do NOT
# clobber (preserve human edits); flag the divergence and exit 3 so `apply`
# surfaces it. Reconciling a changed plan onto an existing file is `update`'s
# diff-first job, not this writer's (BRIEF.md:54,65).
if (Test-Path -LiteralPath $WorkflowFile -PathType Leaf) {
    $existing = Get-Content -LiteralPath $WorkflowFile -Raw
    if ($null -eq $existing) { $existing = '' }
    if ($existing.TrimEnd("`r", "`n") -eq $NewContent.TrimEnd("`r", "`n")) {
        Write-Output "$WorkflowFile already up to date (no change)."
        Write-Flags
        exit 0
    }
    [Console]::Error.WriteLine("ERROR: $WorkflowFile already exists and differs from the plan's CI workflow.")
    [Console]::Error.WriteLine("       Not overwriting — human edits are preserved. Run 'update' to review the diff and reconcile.")
    exit 3
}

# --- Write (create .github/workflows/ if absent) -------------------------------
# Initialize $tmp BEFORE the try so the catch can reference it safely under
# StrictMode (parity with the sibling writers' temp-file pattern).
$tmp = $null
try {
    if (-not (Test-Path -LiteralPath $WorkflowsDir)) {
        New-Item -ItemType Directory -Path $WorkflowsDir -Force | Out-Null
    }
    # Atomic-ish write via a temp file so a failure never leaves a partial file.
    # utf8NoBOM keeps the YAML BOM-free and portable; an explicit trailing LF
    # matches the bash twin's `printf '%s\n'`.
    $tmp = Join-Path $WorkflowsDir ('.ci.yml.' + [System.IO.Path]::GetRandomFileName())
    Set-Content -LiteralPath $tmp -Value $NewContent -Encoding utf8NoBOM -NoNewline
    Add-Content -LiteralPath $tmp -Value "`n" -Encoding utf8NoBOM -NoNewline
    Move-Item -LiteralPath $tmp -Destination $WorkflowFile -Force
} catch {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    [Console]::Error.WriteLine("ERROR: failed to write CI workflow to: $WorkflowsDir ($($_.Exception.Message))")
    exit 2
}

Write-Output "$WorkflowFile written."
Write-Output "  required-status-check contexts: $UnitTestsContext, $PreflightContext"
Write-Flags
exit 0
