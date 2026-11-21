#!/usr/bin/env bash
#
# provision-protection.sh — assert the suite's branch-protection floor idempotently.
#
# What this does, in plain terms:
#   The `apply` and `update` verbs call this to guarantee a target repo branch
#   carries the suite's server-side safety floor, so the milestone-driver gates
#   hold even when a local hook is bypassed or absent. It asserts, via the GitHub
#   API, that on the target branch: direct pushes are blocked, a pull request is
#   required before merge, and, when ci.yml is the current generated file, the
#   CI checks 'unit-tests' and 'preflight' must pass. Re-asserting the same protection is a safe no-op, so
#   `apply` and `update` may run it repeatedly. It NEVER weakens or removes
#   protection it did not author — it GETs the existing protection first and
#   merges the floor in per field, taking the STRONGER value, so a re-apply onto
#   an already-hardened repo only asserts the floor or reconciles drift UP to it.
#   A stronger-than-floor setting (an extra required approval, a push-restriction
#   allowlist, strict-up-to-date) is preserved, never reconciled DOWN. That holds
#   for BOTH floors: the integration floor below is create-only or reconcile-UP —
#   never a downgrade — so it REFUSES rather than clear an existing
#   `enforce_admins: true`, and there is deliberately no --force / downgrade path.
#
# Two floors — `--floor release` (default) and `--floor integration`:
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
#   - required_status_checks.contexts = UNION(existing contexts, 'unit-tests'/
#       'preflight' when ci.yml is the current generated file, else nothing) — any
#       existing extra contexts are kept; with none existing and none added the
#       field is null. strict = (existing.strict OR false) =
#       existing is preserved (the floor never turns OFF require-up-to-date).
#   - enforce_admins = the FLOOR'S value: true for `--floor release` (existing
#       cannot exceed true — admins cannot bypass, the key hardening signal);
#       false for `--floor integration` (admins may override, so a transient CI
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
#   only the checks the plugin generates are required. This asks
#   `emit-ci-workflow --check` whether ci.yml is the current generated file; on
#   exit 0 'unit-tests' and 'preflight' are required (the exact job names the
#   emitter writes, which run on PRs into both branches). On exit 3 (hand-written,
#   outdated generated, or no ci.yml) no check is added: existing required checks
#   are kept and listed with 🔴, and none are ever removed. Any other exit fails
#   with the emitter's error and changes no protection.
#
# The protection target is SOURCED, never chosen:
#   `--floor release` reads `protectedBranch`; `--floor integration` reads
#   `integrationBranch` — both from the target repo's .milestone-config/driver.json
#   (written by issue #8). An absent file or empty key is a clear precondition
#   failure, never a guessed name. (Issue #12 Design; sibling shape at
#   scripts/provision-branches.sh:97-118.)
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
#   and a human performs it knowingly — this script has NO --force, no
#   --allow-downgrade, and no other downgrade path (issue #93 decision c). The
#   check runs BEFORE the merge, so a --dry-run preview surfaces the deadlock too.
#
# Preconditions:
#   `gh` installed and authenticated, `jq` installed, run inside a
#   GitHub-connected working directory, with a token that holds REPO-ADMIN on the
#   target repo. Branch protection is a repository-administration write, so this
#   probes admin permission BEFORE any write and hard-stops with a clear,
#   actionable message on insufficient scope (the GitHub API returns 403 without
#   it) — never a silent failure (BRIEF.md:82). It also requires the protected
#   branch to already exist (#10); an absent branch is a named precondition
#   failure, not a write against a non-existent ref. Companion: provision-protection.ps1.
#
# Preview (`plan`): pass --dry-run to print the EXACT protection PUT body it would
#   send (the resolved contexts and every setting) without writing anything to the
#   remote — the preview-then-execute split the `plan` verb records (BRIEF.md
#   §"The surface"). The dry-run still runs the read-only preconditions so the
#   preview reflects what an `apply` would actually do.
#
# Run it:  ./scripts/provision-protection.sh [--repo /path/to/target] [--dry-run] \
#            [--floor release|integration]
# Exit 0 = protection asserted / already correct (or previewed) — or the
#          integration floor was not opted in (reported no-op, nothing changed).
# Exit 1 = precondition unmet / config missing / unknown --floor or
#          integrationProtection value / repo-admin scope absent / branch
#          missing / emit-ci-workflow --check failed (exit 1 or 2) /
#          integration floor REFUSED on an enforce_admins:true branch
#          (nothing changed). A missing ci.yml is not an exit 1: no checks are
#          added, a 🔴 line says why, and the run continues.
# Exit 2 = GitHub API failure mid-step (reports the failing endpoint; nothing weakened).

set -euo pipefail

# --- jq output normalization (Windows text-mode stdout) ------------------------
# A native-Windows jq opens stdout in TEXT mode, so every `\n` it writes becomes
# `\r\n` and any jq value the shell consumes as TEXT carries a stray `\r`. Cause,
# mechanism, and the `s/\r$//` rationale are documented once in the canonical
# block at scripts/write-project-docs.sh:87-121 — not restated here.
# One site here is LIVE; the rest are LATENT. Both are recorded, so nobody
# "proves" the latent ones safe and removes the seam:
#
# LIVE — PUT_BODY (and NORM_CURRENT beside it) are MULTI-line, and `$(...)`
#   strips only the TRAILING newline, so every interior CR survives. Measured on
#   jq-1.8.1: 24 CR bytes in the --dry-run preview. That means a garbled preview,
#   a non-canonical body on the wire, and divergence from the byte-identical
#   output contract this script shares with provision-protection.ps1. The no-op
#   compare at NORM_CURRENT vs PUT_BODY still returns the right answer unfolded —
#   but only because BOTH sides come from the same text-mode jq and are mangled
#   IDENTICALLY. That is an accident of symmetry, not a property. Folding both
#   keeps them symmetric AND makes them canonical.
#
# LATENT — every other folded site is a SINGLE-line scalar, and on the msys
#   toolchain this script was developed against `$(...)` strips a trailing CRLF
#   WHOLE, so they come back clean today (measured CR=0). That is a TOOLCHAIN
#   behavior, not a guarantee — WSL bash invoking a Windows `jq.exe` need not do
#   it, and the multi-line form of the same pattern is ALREADY broken above. What
#   each would cost if a CR ever did survive:
#     - the enforce_admins read in the integration-floor REFUSE guard: a CR'd
#       "true" is not equal to "true", so the guard would not fire and the run
#       would PUT enforce_admins:false over a branch already carrying the
#       release-grade `true` — the never-weaken invariant broken SILENTLY,
#       exit 0. Worst case in the file: a safety refusal turned into a downgrade.
#     - HAS_CONTEXTS in read_back_protection lands in a `-ne` INTEGER test, which
#       bash would reject ("integer expression expected"). The function returns
#       non-zero, so a good PUT reads as read-back drift — one spurious re-PUT,
#       then a spurious `api_fail` (exit 2) on a correctly-protected repo.
#     - INTEGRATION_PROTECTION: a CR'd `floor` matches neither `""|none` nor
#       `floor`, falls to the reject-unknown `*)` arm, and fails with a message
#       naming the value the user DID set correctly — maximally confusing.
#     - TARGET_BRANCH rides straight into REST paths (`repos/${SLUG}/branches/
#       ${TARGET_BRANCH}`), where a CR'd name 404s and reports the branch as
#       missing (the issue #10 precondition) instead of the real cause.
#     - CONTEXTS_DISPLAY is echoed into user messages, where a bare CR returns
#       the cursor to column 0 and overwrites the line already printed.
# On a POSIX jq (LF stdout) the seam is a no-op, so applying it unconditionally
# is safe — verified: with LF input the --dry-run body is byte-identical before
# and after this change, on both floors (#93's release-path criterion).
#
# EXEMPT — do NOT "fix" these:
#   - the `jq -e .` config validation below: exit code only, no text consumed.
#   - CONTEXTS_JSON: re-parsed as JSON via `--argjson` when the merge filter
#     runs. CR is legal JSON whitespace (RFC 8259 §2), so it needs no fold.
#   - the `gh repo view --json … --jq` / `gh api … --jq` sites (SLUG, ADMIN).
#     `--jq` is gh's BUILT-IN Go jq, not the external binary: it writes bytes
#     directly with no Windows text-mode translation and emits zero CR (verified
#     on gh 2.87.3). Piping those through the seam would imply a hazard that is
#     not there.
# Note PUT_BODY has TWO consumers — the text compare, and `gh api -X PUT
# --input -`. Folding is safe for the PUT: `s/\r$//` removes only a CR that
# precedes the LF sed splits on, and that CR is insignificant JSON whitespace.
strip_cr() { sed $'s/\r$//'; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO="."
DRY_RUN=0
# The floor defaults to `release` — the pre-#93 behavior, byte-for-byte.
FLOOR="release"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)    REPO="${2:?--repo needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --floor)   FLOOR="${2:?--floor needs a value}"; shift 2 ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      echo "milestone-bootstrapper: unknown argument: $1" >&2
      exit 1 ;;
  esac
done

# fail <msg>  — precondition / config / missing-prerequisite failure: nothing changed.
fail() {
  echo "milestone-bootstrapper: $1" >&2
  exit 1
}

# api_fail <msg> — a GitHub API operation failed mid-step. Reports the failing
# endpoint; never weakens or removes protection to recover. Exit 2 so the
# orchestrator can surface it distinctly from a precondition failure.
api_fail() {
  echo "milestone-bootstrapper: 🔴 $1" >&2
  exit 2
}

# --- Validate the floor enum (reject-unknown; mirrors the --stack precedent at
# scripts/write-driver-config.sh:260-277) --------------------------------------
case "$FLOOR" in
  release|integration) ;;
  *) fail "--floor must be one of release|integration (got: ${FLOOR}). No protection changed." ;;
esac

# --- Preconditions (surface the unmet one by name; change nothing) -----------

command -v gh >/dev/null 2>&1 \
  || fail "GitHub CLI ('gh') is not installed or not on PATH. Install it from https://cli.github.com, then re-run."

command -v jq >/dev/null 2>&1 \
  || fail "'jq' is required but not found on PATH. Install jq, then re-run."

gh auth status >/dev/null 2>&1 \
  || fail "GitHub CLI is not authenticated. Run 'gh auth login' (with a token that holds repo-admin on the target repo), then re-run."

gh repo view >/dev/null 2>&1 \
  || fail "the working directory is not connected to a GitHub repository (or the repo is unreachable). Run this inside a repo with a GitHub remote, then re-run."

# --- Read the target branch (and the integration opt-in) from driver.json ------
# The target is sourced, never chosen: an absent file or empty key is a
# precondition failure, never a guessed name (Issue #12 Design).

CONFIG_FILE="${REPO%/}/.milestone-config/driver.json"

# WHICH key the caller must have defined is floor-dependent: `release` reads
# protectedBranch, `integration` reads integrationBranch. Naming the wrong one
# sends the user to define a key this run never reads. Resolved HERE — before the
# file is opened — so the not-found message can name the right one. `--floor
# release` substitutes `protectedBranch`, so that rendering stays byte-identical
# to pre-#93.
if [ "$FLOOR" = "release" ]; then
  TARGET_KEY="protectedBranch"
else
  TARGET_KEY="integrationBranch"
fi

[ -f "$CONFIG_FILE" ] \
  || fail "config not found: ${CONFIG_FILE}. Run the config writer (issue #8) first so ${TARGET_KEY} is defined; no protection changed."

if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
  fail "config is not valid JSON: ${CONFIG_FILE}. Fix it, then re-run; no protection changed."
fi

# TARGET_BRANCH / TARGET_LABEL / ENFORCE_ADMINS / ADMINS_NOTE /
# NOOP_ADMINS_SUFFIX are the only floor-dependent values; every downstream site
# reads them, so `--floor release` resolves them to exactly the pre-#93 constants
# and renders byte-identically.
#
# NOOP_ADMINS_SUFFIX exists because the write path states the admins posture
# (${ADMINS_NOTE}) but the already-at-floor no-op path did not — so an idempotent
# integration re-run never repeated that admins may override. It is EMPTY under
# `release` on purpose: appending the note there would change that path's
# long-standing output, and the release rendering is byte-frozen.
if [ "$FLOOR" = "release" ]; then
  TARGET_BRANCH="$(jq -r '.protectedBranch // empty' "$CONFIG_FILE" | strip_cr)"
  [ -n "$TARGET_BRANCH" ] \
    || fail "key 'protectedBranch' is missing or empty in ${CONFIG_FILE}. Branch protection cannot be asserted without it; no protection changed."
  TARGET_LABEL="protected"
  ENFORCE_ADMINS="true"
  ADMINS_NOTE="enforce_admins on"
  NOOP_ADMINS_SUFFIX=""
else
  # Opt-in gate FIRST: absent / "none" is the default and a reported no-op, so a
  # repo that never opted in cannot have its integration branch protected here.
  INTEGRATION_PROTECTION="$(jq -r '.integrationProtection // empty' "$CONFIG_FILE" | strip_cr)"
  case "$INTEGRATION_PROTECTION" in
    ""|none)
      echo "milestone-bootstrapper: integration protection is not opted in ('integrationProtection' absent or \"none\" in ${CONFIG_FILE}) — nothing changed."
      exit 0 ;;
    floor) ;;
    *)
      fail "key 'integrationProtection' must be one of none|floor in ${CONFIG_FILE} (got: ${INTEGRATION_PROTECTION}). No protection changed." ;;
  esac
  TARGET_BRANCH="$(jq -r '.integrationBranch // empty' "$CONFIG_FILE" | strip_cr)"
  [ -n "$TARGET_BRANCH" ] \
    || fail "key 'integrationBranch' is missing or empty in ${CONFIG_FILE}. Integration-branch protection cannot be asserted without it; no protection changed."
  TARGET_LABEL="integration"
  ENFORCE_ADMINS="false"
  ADMINS_NOTE="enforce_admins off (admins may override — integration floor)"
  NOOP_ADMINS_SUFFIX="; ${ADMINS_NOTE}"
fi

# --- Resolve the required status-check contexts (asked of the generator) ------
# Only the checks the plugin generates are required: it knows their names and that
# they run on PRs into both branches. Hand-written CI cannot be known to report
# (shared workflows, summary jobs and matrix jobs change what GitHub reports), so
# this asks the sibling emitter whether ci.yml is the current generated file.
# Exit 0 -> 'unit-tests' and 'preflight' are required. Exit 3 (hand-written,
# outdated generated, or no ci.yml) -> no checks are added; existing required
# checks are kept by the merge below, never removed. Any other exit -> fail.
CI_WORKFLOW="${REPO%/}/.github/workflows/ci.yml"

CONTEXTS=()
ADDS_CHECKS=0
CI_CAUSE=""
CHECK_ERR="$(bash "${SCRIPT_DIR}/emit-ci-workflow.sh" --repo "$REPO" --check 2>&1 >/dev/null)" && CHECK_RC=0 || CHECK_RC=$?
case "$CHECK_RC" in
  0)
    CONTEXTS=("unit-tests" "preflight")
    ADDS_CHECKS=1 ;;
  3)
    if [ ! -f "$CI_WORKFLOW" ]; then
      CI_CAUSE="absent"
    elif grep -q 'Emitted by milestone-bootstrapper' "$CI_WORKFLOW"; then
      CI_CAUSE="outdated generated"
    else
      CI_CAUSE="hand-written"
    fi ;;
  *)
    # Exit 1/2 (bad driver.json, unwritable path) or a missing emitter is not a
    # verdict on ci.yml, so it must not read as hand-written CI.
    echo "milestone-bootstrapper: 🔴 emit-ci-workflow --check failed (exit ${CHECK_RC}); no protection changed." >&2
    [ -z "$CHECK_ERR" ] || printf '%s\n' "$CHECK_ERR" >&2
    exit 1 ;;
esac

# --- Resolve owner/repo once (all protection ops are keyed on it) -------------
SLUG="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" \
  || api_fail "could not resolve the GitHub repository (owner/name). Nothing changed."
[ -n "$SLUG" ] || api_fail "could not resolve the GitHub repository (owner/name). Nothing changed."

# --- repo-admin precondition (clear message, never silent) -------------------
# Branch protection is a repository-administration write; without repo-admin the
# protection API returns 403. Probe the authenticated user's permission with a
# READ-only call BEFORE any write and hard-stop on insufficient scope (BRIEF.md:82).
ADMIN="$(gh api "repos/${SLUG}" --jq '.permissions.admin' 2>/dev/null)" || ADMIN=""
if [ "$ADMIN" != "true" ]; then
  fail "🔴 branch protection requires repo-admin on '${SLUG}', but the authenticated token does not hold it (the protection API returns 403 without it). Re-authenticate with an admin token — e.g. 'gh auth login' as a repo admin, or 'gh auth refresh -h github.com -s admin:org,repo' — then re-run. No protection was written."
fi

# --- Missing-prerequisite edge: the target branch must already exist (#10) -----
gh api "repos/${SLUG}/branches/${TARGET_BRANCH}" >/dev/null 2>&1 \
  || fail "🔴 the ${TARGET_LABEL} branch '${TARGET_BRANCH}' does not exist on '${SLUG}' yet. Provision the branch model first (issue #10 / provision-branches), then re-run — protection is not asserted against a non-existent branch. No protection changed."

# --- Read current protection FIRST (the merge reads from it; absence is fine) -
# A non-weakening floor cannot be a context-free declarative PUT: a full-object
# PUT of the floor alone would reconcile a STRONGER pre-existing setting DOWN
# (restrictions:null would wipe an allowlist, 0 approvals would lower a 2-approval
# rule, strict:false would turn off require-up-to-date). So we GET the existing
# protection and merge the floor INTO it, per field, taking the stronger value.
# A 404 here means "no protection yet" — a normal first-apply state, not an error;
# CURRENT is then empty and the merge collapses to exactly the floor. This GET is
# read-only, so --dry-run runs it too and its preview reflects the true merge.
CURRENT="$(gh api "repos/${SLUG}/branches/${TARGET_BRANCH}/protection" 2>/dev/null)" || CURRENT=""
# Feed the merge a JSON object even on a fresh repo: 'null' means "no existing
# protection" and every existing-side lookup falls back to the floor value.
[ -n "$CURRENT" ] || CURRENT="null"

# --- REFUSE: the integration floor never weakens an existing enforce_admins ----
# The integration floor's enforce_admins is FALSE, so asserting it onto a branch
# that already carries enforce_admins:true would reconcile a stronger pre-existing
# setting DOWN — precisely what the never-weaken invariant (header) forbids. The
# floor is therefore create-only or reconcile-UP: on this one state it changes
# NOTHING and exits 1, printing the exact command for the human to clear it
# knowingly. There is deliberately no --force / --allow-downgrade path (issue #93
# decision c). Placed BEFORE the merge — and so before the --dry-run print — so a
# `plan` preview surfaces the deadlock instead of previewing an impossible write.
if [ "$FLOOR" = "integration" ] && [ "$CURRENT" != "null" ] \
   && [ "$(printf '%s' "$CURRENT" | jq -r '.enforce_admins.enabled // false' | strip_cr)" = "true" ]; then
  echo "milestone-bootstrapper: 🔴 refusing to apply the integration floor to '${TARGET_BRANCH}' on '${SLUG}': that branch already carries enforce_admins:true (the release-grade floor). Leaving it in place DEADLOCKS the integration branch — admins cannot override a failing, pending, or broken required check, so the driver's PRs and any baseline PR can never land. Nothing was changed: this script never weakens protection it did not author, and it has no --force path." >&2
  echo "milestone-bootstrapper: clearing it is the one destructive act, so a human performs it knowingly. To clear it, run:" >&2
  echo "  gh api -X DELETE repos/${SLUG}/branches/${TARGET_BRANCH}/protection/enforce_admins" >&2
  echo "milestone-bootstrapper: then re-run this script to assert the integration floor." >&2
  echo "milestone-bootstrapper: Or, to leave that protection in place, set integrationProtection: \"none\" in driver.json and this floor will not be asserted." >&2
  exit 1
fi

# --- Build the EXACT protection PUT body by MERGING existing-with-floor -------
# Four fields are REQUIRED by the API (each may be null): required_status_checks,
# enforce_admins, required_pull_request_reviews, restrictions. The PUT uses bare
# booleans (the GET response wraps them as {"enabled": ...}); the merge reads the
# wrapped GET shape and emits this flat plan shape. Per field, STRONGER wins:
#   - required_status_checks.contexts = UNION(existing, generated job names)  (add
#       them only when generated, keep existing extras); strict = existing OR false (preserve
#       an existing require-up-to-date, never turn it off).
#   - required_pull_request_reviews.required_approving_review_count = MAX(existing,
#       0)  (PR required; never lower an existing approval requirement).
#   - enforce_admins = $enforceAdmins, the FLOOR'S value (release true /
#       integration false) · allow_force_pushes=false · allow_deletions=false
#       (false is strongest; an existing false is preserved).
#   - restrictions = the existing allowlist mapped back to the PUT shape (user
#       logins / team slugs / app slugs), PRESERVED; null only when none exists.
# This jq program is shared byte-for-byte with provision-protection.ps1, so both
# emit an identical PUT body from identical inputs.
if [ "$ADDS_CHECKS" -eq 1 ]; then
  CONTEXTS_JSON="$(printf '%s\n' "${CONTEXTS[@]}" | jq -R . | jq -s .)"
else
  CONTEXTS_JSON='[]'
fi
MERGE_FILTER='. as $cur | {
  required_status_checks: (
    if ($cur.required_status_checks) == null and ($contexts | length) == 0 then null
    else {
      strict: (($cur.required_status_checks.strict) // false),
      contexts: ((($cur.required_status_checks.contexts) // []) + $contexts | unique)
    }
    end
  ),
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
PUT_BODY="$(printf '%s' "$CURRENT" | jq --argjson contexts "$CONTEXTS_JSON" --argjson enforceAdmins "$ENFORCE_ADMINS" "$MERGE_FILTER" | strip_cr)"

# Normalize the existing protection into the same flat PUT shape, every field read
# from $cur as it is (absent -> null or false, no floor value filled in), so an
# exact match against the merged target means "already at or above the floor" — a
# true no-op. Filling a floor value in here would hide a missing PR rule, an
# allowed force push or deletion, or a 404 (no protection at all) whenever the
# merge adds no checks, and the PUT would be skipped.
NORMALIZE_FILTER='. as $cur | {
  required_status_checks: (
    if ($cur.required_status_checks) == null then null
    else {
      strict: (($cur.required_status_checks.strict) // false),
      contexts: ((($cur.required_status_checks.contexts) // []) | unique)
    }
    end
  ),
  enforce_admins: (($cur.enforce_admins.enabled) // false),
  required_pull_request_reviews: (
    if ($cur.required_pull_request_reviews) == null then null
    else {
      required_approving_review_count: (($cur.required_pull_request_reviews.required_approving_review_count) // 0)
    }
    end
  ),
  restrictions: (
    if ($cur.restrictions) == null then null
    else {
      users: [ ($cur.restrictions.users // [])[] | .login ],
      teams: [ ($cur.restrictions.teams // [])[] | .slug ],
      apps:  [ ($cur.restrictions.apps  // [])[] | .slug ]
    }
    end
  ),
  allow_force_pushes: (($cur.allow_force_pushes.enabled) // false),
  allow_deletions: (($cur.allow_deletions.enabled) // false)
}'

# The contexts the merged PUT actually carries (UNION result), for display.
CONTEXTS_DISPLAY="$(printf '%s' "$PUT_BODY" | jq -r '(.required_status_checks.contexts // []) | if length == 0 then "none" else join(", ") end' | strip_cr)"

# --- Say so when no checks are added (stderr; exit status unchanged) -----------
# Existing required checks are kept by the merge, so list them for the human to
# confirm each one reports on PRs into this branch.
if [ "$ADDS_CHECKS" -eq 0 ]; then
  case "$CI_CAUSE" in
    absent)
      CI_NOTE=".github/workflows/ci.yml is absent. Run update (or apply) to create it."
      CI_DESC="a missing ci.yml" ;;
    "outdated generated")
      CI_NOTE=".github/workflows/ci.yml is an outdated generated file. Review the diff with emit-ci-workflow --check, then delete it and re-run update (or apply), which recreates it; local edits to it are lost."
      CI_DESC="an outdated generated ci.yml" ;;
    *)
      CI_NOTE=".github/workflows/ci.yml is hand-written. Run emit-ci-workflow --check to print the diff."
      CI_DESC="hand-written CI" ;;
  esac
  echo "milestone-bootstrapper: 🔴 no required checks added: ${CI_NOTE}" >&2
  EXISTING_CONTEXTS="$(printf '%s' "$CURRENT" | jq -r '(.required_status_checks.contexts // [])[]' | strip_cr)"
  if [ -n "$EXISTING_CONTEXTS" ]; then
    echo "🔴 milestone-bootstrapper does not manage required checks for ${CI_DESC}. Confirm each of these reports on PRs into \`${TARGET_BRANCH}\`. To remove one: \`gh api -X DELETE repos/${SLUG}/branches/${TARGET_BRANCH}/protection/required_status_checks/contexts -f 'contexts[]=<name>'\`" >&2
    while IFS= read -r ctx; do
      echo "  ${ctx}" >&2
    done <<< "$EXISTING_CONTEXTS"
  fi
fi

# --- Preview (--dry-run): print the exact MERGED PUT body; write nothing ------
if [ "$DRY_RUN" -eq 1 ]; then
  echo "milestone-bootstrapper: branch-protection plan for ${SLUG} branch '${TARGET_BRANCH}' (preview — nothing written):"
  echo "  required status checks: ${CONTEXTS_DISPLAY}"
  echo "  PUT repos/${SLUG}/branches/${TARGET_BRANCH}/protection with body:"
  printf '%s\n' "$PUT_BODY"
  exit 0
fi

# --- No-op when already at-or-above the floor; else reconcile UP --------------
# Compare the existing state (normalized) to the merged target. Equal means the
# merge added nothing — the repo is already at or above the floor, so writing
# would be a pointless re-PUT. (On a fresh repo CURRENT is 'null', so the
# normalized existing differs from the floor target and we proceed to write.)
NORM_CURRENT="$(printf '%s' "$CURRENT" | jq "$NORMALIZE_FILTER" | strip_cr)"
if [ "$NORM_CURRENT" = "$PUT_BODY" ]; then
  echo "milestone-bootstrapper: branch protection already meets the suite floor on ${SLUG} branch '${TARGET_BRANCH}' (no change)."
  echo "milestone-bootstrapper: required status checks: ${CONTEXTS_DISPLAY}${NOOP_ADMINS_SUFFIX}."
  exit 0
fi

# --- Assert / reconcile the protection (merged PUT — never weakens) -----------
# The PUT is existing-merged-with-floor: a re-apply onto an at-or-above-floor repo
# is a no-op (handled above), and a reconcile pulls only the BELOW-floor fields UP
# while preserving every stronger pre-existing rule (extra contexts, extra
# approvals, an allowlist, strict-up-to-date).
if [ "$CURRENT" != "null" ]; then
  echo "milestone-bootstrapper: branch protection on '${TARGET_BRANCH}' is below the suite floor — reconciling UP (stronger existing settings are preserved)."
fi

# put_protection — issues the PUT asserted above; callable more than once (the
# retry below re-invokes it verbatim against the same, already-computed PUT_BODY).
put_protection() {
  printf '%s' "$PUT_BODY" | gh api -X PUT "repos/${SLUG}/branches/${TARGET_BRANCH}/protection" \
    --input - >/dev/null 2>&1
}

# read_back_protection — the pre-existing acceptance check (same pattern): GETs
# current protection and confirms the floors (PR required, enforce_admins, force
# pushes and deletions disallowed, and status-check contexts present only when
# this run added the generated checks). enforce_admins is asserted EQUAL TO THE FLOOR'S
# value ($ENFORCE_ADMINS) rather than hardcoded "true", so release still verifies
# `true` and integration verifies the `false` it just wrote — an assertion that
# would otherwise fail on every integration run. Populates PR_REQUIRED/
# ADMINS_ENFORCED/FORCE_PUSHES/DELETIONS/HAS_CONTEXTS for the caller's message; returns non-zero on a
# failed GET or a floor not holding.
read_back_protection() {
  VERIFY="$(gh api "repos/${SLUG}/branches/${TARGET_BRANCH}/protection" 2>/dev/null)" || return 1
  PR_REQUIRED="$(printf '%s' "$VERIFY" | jq -r 'if .required_pull_request_reviews == null then "no" else "yes" end' | strip_cr)"
  ADMINS_ENFORCED="$(printf '%s' "$VERIFY" | jq -r '.enforce_admins.enabled // false' | strip_cr)"
  FORCE_PUSHES="$(printf '%s' "$VERIFY" | jq -r '.allow_force_pushes.enabled // false' | strip_cr)"
  DELETIONS="$(printf '%s' "$VERIFY" | jq -r '.allow_deletions.enabled // false' | strip_cr)"
  HAS_CONTEXTS="$(printf '%s' "$VERIFY" | jq -r '(.required_status_checks.contexts // []) | length' | strip_cr)"
  [ "$PR_REQUIRED" = "yes" ] && [ "$ADMINS_ENFORCED" = "$ENFORCE_ADMINS" ] \
    && [ "$FORCE_PUSHES" = "false" ] && [ "$DELETIONS" = "false" ] || return 1
  [ "$ADDS_CHECKS" -eq 0 ] || [ "${HAS_CONTEXTS:-0}" -ne 0 ]
}

put_protection \
  || api_fail "failed to assert branch protection on '${SLUG}' branch '${TARGET_BRANCH}' (PUT repos/${SLUG}/branches/${TARGET_BRANCH}/protection). No protection was weakened or removed. Re-run after resolving the error (a 403 here means the token lacks repo-admin)."

# --- Read back and verify the floor landed, with one bounded retry (issue #109) -
# GitHub's API can accept the PUT above (exit 0) without the floor durably
# sticking (eventual consistency) — this is the existing acceptance check
# (read_back_protection, unchanged), now wrapped with exactly ONE retry
# (re-PUT once, re-verify) before falling into the halt below — never a second
# retry (`.project/design-philosophy.md#Error & failure philosophy`).
if ! read_back_protection; then
  echo "milestone-bootstrapper: branch-protection read-back drift on '${TARGET_BRANCH}' — retrying once (re-PUT, re-verify)."
  put_protection \
    || api_fail "retry failed: could not re-assert branch protection on '${SLUG}' branch '${TARGET_BRANCH}' (PUT repos/${SLUG}/branches/${TARGET_BRANCH}/protection). No protection was weakened or removed. Re-run after resolving the error."
  read_back_protection \
    || api_fail "asserted protection but the read-back still does not show the floors after one retry (PR required=${PR_REQUIRED:-unknown}, enforce_admins=${ADMINS_ENFORCED:-unknown}, allow_force_pushes=${FORCE_PUSHES:-unknown}, allow_deletions=${DELETIONS:-unknown}, status-check contexts=${HAS_CONTEXTS:-unknown}) on '${TARGET_BRANCH}'. Re-run to confirm."
fi

echo "milestone-bootstrapper: branch protection asserted on ${SLUG} branch '${TARGET_BRANCH}'."
echo "milestone-bootstrapper: direct pushes blocked, PR required (0 approvals), required status checks: ${CONTEXTS_DISPLAY}; ${ADMINS_NOTE}."
exit 0
