#!/usr/bin/env bash
#
# emit-ci-workflow.sh — emit the target repo's `.github/workflows/ci.yml`: the
# GitHub Actions workflow that gates PRs into the integration branch on the
# project's detected test/preflight commands.
#
# What this does, in plain terms:
#   The bootstrapper's `apply` skill makes the TARGET repo suite-ready (Job 2
#   "CI workflow", BRIEF.md:51). The last consequential write is the CI workflow,
#   because branch protection (#12) registers this workflow's job names as the
#   required status checks and `milestone-driver`'s per-PR merge gate (#13) waits
#   on them. This is the deterministic, reusable writer `apply` calls to produce
#   that file. The PowerShell 7+ twin is emit-ci-workflow.ps1 (suite cross-
#   platform convention) — the two emit byte-identical YAML.
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
#   --repo <dir>   target repo root (default: current directory). The writer reads
#                  <repo>/.milestone-config/driver.json and writes
#                  <repo>/.github/workflows/ci.yml.
#   Env fallback (arg wins): CI_EMIT_REPO.
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
# Run it:  ./scripts/emit-ci-workflow.sh --repo /path/to/target
# Exit 0 = file is present and correct (incl. emitted-with-[TBD]-flags, and the
#          no-op case). Exit 1 = bad input / unreadable-or-malformed driver.json.
# Exit 2 = write/serialize failure. Exit 3 = existing file diverges (not clobbered;
#          run `update` to reconcile).

set -euo pipefail

# --- CONTEXT-NAME STABILITY CONTRACT: the fixed required-status-check contexts --
# These two strings are the contract #12 registers and #13 waits on. Editing them
# is a breaking change — keep in lockstep with #12/#13 and with the .ps1 twin.
readonly UNIT_TESTS_CONTEXT="unit-tests"
readonly PREFLIGHT_CONTEXT="preflight"

# --- Inputs (arg overrides env; env overrides default) -------------------------
REPO="${CI_EMIT_REPO:-.}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?--repo needs a value}"; shift 2 ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found on PATH." >&2; exit 2; }

# --- Read the resolved values from driver.json (#8's output) -------------------
DRIVER_FILE="${REPO%/}/.milestone-config/driver.json"

if [ ! -f "$DRIVER_FILE" ]; then
  echo "ERROR: cannot read driver config: ${DRIVER_FILE} not found." >&2
  echo "       Run the driver-config writer (#8) first so the integration branch and test commands are recorded." >&2
  exit 1
fi

# Parse once; a malformed driver.json is a clear, non-silent failure (never emit
# a partial/guessed workflow from unreadable config).
if ! DRIVER_JSON="$(jq -e '.' "$DRIVER_FILE" 2>&1)"; then
  echo "ERROR: cannot parse driver config: ${DRIVER_FILE} is not valid JSON." >&2
  echo "       (${DRIVER_JSON})" >&2
  exit 1
fi

# Shape gate: the config MUST be a JSON object. Valid-but-non-object JSON (a
# top-level array/string/number, or null) has no keys to read; without this gate
# the per-key `jq` reads below abort under `set -euo pipefail` with a raw `jq:`
# error and a confusing exit code. Reject it here as a clear precondition failure
# (exit 1, no file) — and stay byte-identical with the .ps1 twin's object check.
if ! printf '%s' "$DRIVER_JSON" | jq -e 'type=="object"' >/dev/null 2>&1; then
  echo "ERROR: ${DRIVER_FILE} is not a JSON object." >&2
  echo "       Expected an object recording integrationBranch and the test commands; got a non-object JSON value. Re-run the driver-config writer (#8)." >&2
  exit 1
fi

# Extract the three values. jq prints an empty string for an absent/null key, so
# an absent key is indistinguishable from "" here — both mean "not recorded",
# which is exactly the [TBD]-flag trigger below.
INTEGRATION_BRANCH="$(printf '%s' "$DRIVER_JSON" | jq -r '.integrationBranch // "" | if type=="string" then . else "" end')"
UNIT_TEST_CMD="$(printf '%s' "$DRIVER_JSON"      | jq -r '.unitTestCmd       // "" | if type=="string" then . else "" end')"
PREFLIGHT_CMD="$(printf '%s' "$DRIVER_JSON"      | jq -r '.preflightCmd      // "" | if type=="string" then . else "" end')"

# stack / stackVersionFile (#63's output) — CONSUMED, never re-detected (the
# consume-not-detect contract above). `stack` is the runtime family the emitter
# scaffolds a per-job setup STEP for; `stackVersionFile` is the optional version-
# file path that pins the toolchain. Both absent on a pre-#63 (or stack-less)
# driver.json — that yields NO setup step and the byte-identical two-job frame.
STACK="$(printf '%s' "$DRIVER_JSON"              | jq -r '.stack            // "" | if type=="string" then . else "" end')"
STACK_VERSION_FILE="$(printf '%s' "$DRIVER_JSON" | jq -r '.stackVersionFile // "" | if type=="string" then . else "" end')"

# --- Resolve the trigger branch (flag-don't-guess when absent) -----------------
# An absent integrationBranch is flagged and rendered as a [TBD] branch filter —
# the file stays valid YAML and never gates against a guessed branch.
FLAGS=()
if [ -n "$INTEGRATION_BRANCH" ]; then
  BRANCH_FILTER="$INTEGRATION_BRANCH"
else
  BRANCH_FILTER="[TBD]"
  FLAGS+=("🔴 integrationBranch is absent from ${DRIVER_FILE} — the pull_request branch filter is left as [TBD]. Record it (re-run #8) and re-emit; the workflow will not gate any PR until the branch is set.")
fi

# --- Resolve each command's run step (flag-don't-guess when absent) ------------
# A [TBD] command renders a step that FAILS LOUDLY rather than silently passing,
# so a forgotten command can never let a PR merge unchecked. The job (and thus the
# status-check context) still exists either way — the context name never drifts.
TBD_RUN='echo "::error::milestone-bootstrapper: this command is [TBD] — record it in .milestone-config/driver.json and re-run apply/update." && exit 1'

if [ -n "$UNIT_TEST_CMD" ]; then
  UNIT_RUN="$UNIT_TEST_CMD"
else
  UNIT_RUN="$TBD_RUN"
  FLAGS+=("🔴 unitTestCmd is absent from ${DRIVER_FILE} — the '${UNIT_TESTS_CONTEXT}' job runs a [TBD] placeholder that fails until a command is recorded. No command was fabricated.")
fi

if [ -n "$PREFLIGHT_CMD" ]; then
  PREFLIGHT_RUN="$PREFLIGHT_CMD"
else
  PREFLIGHT_RUN="$TBD_RUN"
  FLAGS+=("🔴 preflightCmd is absent from ${DRIVER_FILE} — the '${PREFLIGHT_CONTEXT}' job runs a [TBD] placeholder that fails until a command is recorded. No command was fabricated.")
fi

# Emit a string as a YAML single-quoted scalar body (a single-quote inside a
# single-quoted scalar is escaped by doubling it). Defined here because the setup-
# step block below quotes the version-file path; reused for the branch/run scalars.
yaml_squote() { printf "%s" "$1" | sed "s/'/''/g"; }

# --- Resolve the per-stack runtime setup STEP (fail-OPEN, never [TBD]->exit 1) --
# This block makes a freshly-bootstrapped repo's PR #1 GREEN: each of the two jobs
# gets a runtime installed BEFORE its gate runs, so `npm test` / `pytest` / `dotnet
# test` resolve instead of red-CI'ing on a missing toolchain. The setup is a STEP
# prepended inside BOTH existing jobs (after checkout, before the gate) — never a
# new or renamed job, so the unit-tests/preflight required-status-check contexts
# stay byte-stable (#12/#13's contract).
#
# Fail-OPEN by design (.project/design-philosophy.md#Error & failure philosophy):
# a correctly-detected stack missing only an OPTIONAL detail (no stackVersionFile,
# no committed lockfile) gets a sane default + a `::warning::` annotation — NEVER
# the `[TBD]`->`exit 1` pattern above, which is reserved for a genuinely-absent
# TEST command. A warning keeps CI green on PR #1; an absent stack key yields NO
# step at all (back-compat: byte-identical to the prior two-job frame).
#
# SETUP_STEPS is either empty (no step) or one-or-more fully-indented YAML lines,
# EACH terminated by a newline, slotted between the checkout step and the gate
# step in both jobs. Action majors pinned against the live action releases (Jun
# 2026): setup-node@v6, setup-python@v6, setup-dotnet@v5.
SETUP_STEPS=""
case "$STACK" in
  node)
    # Lockfile presence is an observable fact about the TARGET repo (not a stack
    # re-detection): `npm ci` requires a committed package-lock.json; without one
    # we fall back to `npm install` + a ::warning:: (still GREEN), per criterion 2.
    if [ -n "$STACK_VERSION_FILE" ]; then
      NODE_VERSION_INPUT="          node-version-file: '$(yaml_squote "$STACK_VERSION_FILE")'"
    else
      NODE_VERSION_INPUT="          node-version: 'lts/*'"
    fi
    if [ -f "${REPO%/}/package-lock.json" ]; then
      SETUP_STEPS="$(cat <<EOF
      - name: Set up Node.js
        uses: actions/setup-node@v6
        with:
${NODE_VERSION_INPUT}
      - name: Install dependencies (clean, from lockfile)
        run: npm ci
EOF
)"
    else
      SETUP_STEPS="$(cat <<EOF
      - name: Set up Node.js
        uses: actions/setup-node@v6
        with:
${NODE_VERSION_INPUT}
      - name: Install dependencies (no lockfile committed)
        run: |
          echo "::warning::milestone-bootstrapper: no package-lock.json committed — using 'npm install' (non-reproducible). Commit a lockfile for deterministic CI."
          npm install
EOF
)"
    fi
    ;;
  python)
    if [ -n "$STACK_VERSION_FILE" ]; then
      PYTHON_VERSION_INPUT="          python-version-file: '$(yaml_squote "$STACK_VERSION_FILE")'"
    else
      PYTHON_VERSION_INPUT="          python-version: '3.x'"
    fi
    SETUP_STEPS="$(cat <<EOF
      - name: Set up Python
        uses: actions/setup-python@v6
        with:
${PYTHON_VERSION_INPUT}
EOF
)"
    ;;
  dotnet|maui)
    # global-json-file pins the SDK when present; absent => the runner's latest
    # installed SDK (a sane default, never an error). maui shares the dotnet setup.
    if [ -n "$STACK_VERSION_FILE" ]; then
      SETUP_STEPS="$(cat <<EOF
      - name: Set up .NET
        uses: actions/setup-dotnet@v5
        with:
          global-json-file: '$(yaml_squote "$STACK_VERSION_FILE")'
EOF
)"
    else
      SETUP_STEPS="$(cat <<EOF
      - name: Set up .NET
        uses: actions/setup-dotnet@v5
EOF
)"
    fi
    ;;
  rust)
    # No setup step: the Rust toolchain (rustc + cargo) is pre-installed on the
    # ubuntu-latest runner, so a setup-rust step would be redundant.
    SETUP_STEPS="      # Rust toolchain (rustc + cargo) is pre-installed on ubuntu-latest — no setup step needed."
    ;;
  plugin|none|*)
    # plugin / none / absent (incl. pre-#63 driver.json): NO setup step. An absent
    # stack key yields the byte-identical two-job frame the prior version emitted.
    SETUP_STEPS=""
    ;;
esac

# Render SETUP_STEPS as a heredoc-ready prefix: when non-empty, ensure it ends in
# exactly one newline so it slots cleanly ABOVE the gate step line; when empty it
# contributes nothing (no blank line). Built once, reused in both jobs.
if [ -n "$SETUP_STEPS" ]; then
  SETUP_BLOCK="${SETUP_STEPS}
"
else
  SETUP_BLOCK=""
fi

# --- Assemble the workflow YAML (mirrors the sibling structure exactly) --------
# Single-quoted heredoc body for the static frame; the four resolved values
# (branch filter + two run lines, both single-line by construction) are
# interpolated via printf so the heredoc itself performs no shell expansion.
#
# The run lines are emitted as YAML single-quoted scalars so an arbitrary command
# (which may contain ${{ }}, ':', '#', or other YAML-significant characters) is
# always a valid, unambiguous scalar. Per YAML, a single-quote inside a
# single-quoted scalar is escaped by doubling it (see yaml_squote, defined above).
BRANCH_FILTER_Q="$(yaml_squote "$BRANCH_FILTER")"
UNIT_RUN_Q="$(yaml_squote "$UNIT_RUN")"
PREFLIGHT_RUN_Q="$(yaml_squote "$PREFLIGHT_RUN")"

NEW_CONTENT="$(cat <<EOF
name: CI

# CI gate for PRs into the integration branch. Emitted by milestone-bootstrapper
# from .milestone-config/driver.json (output of #8) — do not hand-edit the command
# steps or job names here; change them in driver.json and re-run apply/update.
#
# The two job names below ("${UNIT_TESTS_CONTEXT}" and "${PREFLIGHT_CONTEXT}") are the
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
    branches: ['${BRANCH_FILTER_Q}']

permissions:
  contents: read

concurrency:
  group: \${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: true

jobs:
  ${UNIT_TESTS_CONTEXT}:
    name: ${UNIT_TESTS_CONTEXT}
    runs-on: ubuntu-latest
    steps:
      - name: Check out the code under review
        uses: actions/checkout@v7
${SETUP_BLOCK}      - name: Run the unit-test gate
        run: '${UNIT_RUN_Q}'

  ${PREFLIGHT_CONTEXT}:
    name: ${PREFLIGHT_CONTEXT}
    runs-on: ubuntu-latest
    steps:
      - name: Check out the code under review
        uses: actions/checkout@v7
${SETUP_BLOCK}      - name: Run the preflight gate
        run: '${PREFLIGHT_RUN_Q}'
EOF
)"

# --- Resolve the destination path ----------------------------------------------
WORKFLOWS_DIR="${REPO%/}/.github/workflows"
WORKFLOW_FILE="${WORKFLOWS_DIR}/ci.yml"

# Guard: if the workflow path is an existing DIRECTORY, a later `mv` would silently
# move the temp file INTO it (ci.yml/<tmp>) and falsely report success — the real
# file would never be written. Refuse up front with a clear message.
if [ -d "$WORKFLOW_FILE" ]; then
  echo "ERROR: cannot write CI workflow: ${WORKFLOW_FILE} exists and is a directory." >&2
  exit 2
fi

# --- Idempotent / non-destructive ----------------------------------------------
# Absent -> create. Byte-identical -> true no-op. Exists-but-differs -> do NOT
# clobber (preserve human edits); flag the divergence and exit 3 so `apply`
# surfaces it. Reconciling a changed plan onto an existing file is `update`'s
# diff-first job, not this writer's (BRIEF.md:54,65).
emit_flags() {  # print any accumulated 🔴 flags to stderr (never silent)
  # Each flag is a multi-word sentence; iterate the array elements with the
  # quoted ${FLAGS+"${FLAGS[@]}"} expansion so a flag's internal spaces are never
  # word-split AND an empty array never trips `set -u` (portable to bash 3.2).
  local f
  for f in ${FLAGS+"${FLAGS[@]}"}; do
    echo "milestone-bootstrapper: $f" >&2
  done
}

if [ -f "$WORKFLOW_FILE" ]; then
  if [ "$(cat "$WORKFLOW_FILE")" = "$NEW_CONTENT" ]; then
    echo "${WORKFLOW_FILE} already up to date (no change)."
    emit_flags
    exit 0
  fi
  echo "ERROR: ${WORKFLOW_FILE} already exists and differs from the plan's CI workflow." >&2
  echo "       Not overwriting — human edits are preserved. Run 'update' to review the diff and reconcile." >&2
  exit 3
fi

# --- Write (create .github/workflows/ if absent) -------------------------------
# write_workflow — writes NEW_CONTENT atomically via a temp file so a failure
# never leaves a partial/invalid ci.yml in place. printf (not echo) for
# portable, BOM-free UTF-8 output. Callable more than once (the read-back
# retry below re-invokes it verbatim). Returns 0 on success.
write_workflow() {
  if ! mkdir -p "$WORKFLOWS_DIR" 2>/dev/null; then
    echo "ERROR: cannot create directory: ${WORKFLOWS_DIR}" >&2
    return 1
  fi

  TMP_FILE="$(mktemp "${WORKFLOWS_DIR}/.ci.yml.XXXXXX" 2>/dev/null)" || {
    echo "ERROR: cannot write to: ${WORKFLOWS_DIR} (path not writable)." >&2
    return 1
  }
  trap 'rm -f "$TMP_FILE"' EXIT

  if ! printf '%s\n' "$NEW_CONTENT" > "$TMP_FILE" 2>/dev/null; then
    echo "ERROR: failed to write CI workflow to: ${WORKFLOWS_DIR}" >&2
    return 1
  fi

  if ! mv "$TMP_FILE" "$WORKFLOW_FILE" 2>/dev/null; then
    echo "ERROR: failed to write CI workflow to: ${WORKFLOWS_DIR}" >&2
    return 1
  fi
  trap - EXIT
  return 0
}

write_workflow || exit 2

# --- Read-back verify + one bounded retry (issue #109) -----------------------
# This writer makes no gh/API call (verified: it only touches local disk), so
# there is no eventual-consistency risk to guard against — the "read-back" is
# simply re-reading the just-written file and comparing it to what we emitted,
# catching a truncated/corrupt write despite a successful `mv`. One retry (rewrite
# via the same atomic temp-file path, then re-compare) before halting — never
# a second retry (`.project/design-philosophy.md#Error & failure philosophy`).
if [ "$(cat "$WORKFLOW_FILE" 2>/dev/null)" != "$NEW_CONTENT" ]; then
  echo "milestone-bootstrapper: read-back of ${WORKFLOW_FILE} differs from what was written — retrying once."
  write_workflow || exit 2
  if [ "$(cat "$WORKFLOW_FILE" 2>/dev/null)" != "$NEW_CONTENT" ]; then
    echo "ERROR: ${WORKFLOW_FILE} still diverges from the emitted content after one retry. Re-run to confirm; the path may need manual inspection." >&2
    exit 2
  fi
fi

echo "${WORKFLOW_FILE} written."
echo "  required-status-check contexts: ${UNIT_TESTS_CONTEXT}, ${PREFLIGHT_CONTEXT}"
emit_flags
exit 0
