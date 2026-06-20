#!/usr/bin/env bash
#
# provision-protection.sh — assert the suite's branch-protection floor idempotently.
#
# What this does, in plain terms:
#   The `apply` and `update` verbs call this to guarantee the target repo's
#   protected branch carries the suite's server-side safety floor, so the
#   milestone-driver gates hold even when a local hook is bypassed or absent. It
#   asserts, via the GitHub API, that on the protected branch: direct pushes are
#   blocked, a pull request is required before merge, and the CI status checks
#   #11 emits ('unit-tests' and 'preflight') must pass. Re-asserting the same
#   protection is a safe no-op, so `apply` and `update` may run it repeatedly. It
#   NEVER weakens or removes protection it did not author — it GETs the existing
#   protection first and merges the floor in per field, taking the STRONGER value,
#   so a re-apply onto an already-hardened repo only asserts the floor or
#   reconciles drift UP to it. A stronger-than-floor setting (an extra required
#   approval, a push-restriction allowlist, strict-up-to-date) is preserved, never
#   reconciled DOWN.
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
#   - required_status_checks.contexts = UNION(existing contexts, the #11 CI job
#       names 'unit-tests'/'preflight') — the floor contexts are added, any
#       existing extra contexts are kept. strict = (existing.strict OR false) =
#       existing is preserved (the floor never turns OFF require-up-to-date).
#   - enforce_admins=true (floor; existing cannot exceed true — admins cannot
#       bypass, the key hardening signal).
#   - allow_force_pushes=false, allow_deletions=false (floor; false is the
#       strongest value, so an existing false is preserved).
#   - restrictions = the existing push-restriction allowlist, PRESERVED (the floor
#       adds none; if an allowlist exists it is kept, never nulled). On a fresh
#       repo with no allowlist this is null.
#
# The required status-check contexts are SOURCED, never guessed:
#   the contexts are the stable job names #11 registers. They are read from the
#   emitted .github/workflows/ci.yml when present; absent that file, the canonical
#   contract names ('unit-tests' / 'preflight') are used — the exact strings #11's
#   emit-ci-workflow.sh hard-codes (emit-ci-workflow.sh:84-85,214-224) and shares
#   with #12 as a contract. If neither source yields any context, this fails with
#   a clear message rather than registering an empty or guessed context.
#
# The protection target is SOURCED, never chosen:
#   `protectedBranch` is read from the target repo's .milestone-config/driver.json
#   (written by issue #8). An absent file or empty key is a clear precondition
#   failure, never a guessed name. (Issue #12 Design; sibling shape at
#   scripts/provision-branches.sh:97-118.)
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
# Run it:  ./scripts/provision-protection.sh [--repo /path/to/target] [--dry-run]
# Exit 0 = protection asserted / already correct (or previewed).
# Exit 1 = precondition unmet / config missing / repo-admin scope absent / branch
#          or CI contexts missing (nothing changed).
# Exit 2 = GitHub API failure mid-step (reports the failing endpoint; nothing weakened).

set -euo pipefail

REPO="."
DRY_RUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)    REPO="${2:?--repo needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
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

# --- Preconditions (surface the unmet one by name; change nothing) -----------

command -v gh >/dev/null 2>&1 \
  || fail "GitHub CLI ('gh') is not installed or not on PATH. Install it from https://cli.github.com, then re-run."

command -v jq >/dev/null 2>&1 \
  || fail "'jq' is required but not found on PATH. Install jq, then re-run."

gh auth status >/dev/null 2>&1 \
  || fail "GitHub CLI is not authenticated. Run 'gh auth login' (with a token that holds repo-admin on the target repo), then re-run."

gh repo view >/dev/null 2>&1 \
  || fail "the working directory is not connected to a GitHub repository (or the repo is unreachable). Run this inside a repo with a GitHub remote, then re-run."

# --- Read the protected branch from the target repo's driver.json -------------
# The target is sourced, never chosen: an absent file or empty key is a
# precondition failure, never a guessed name (Issue #12 Design).

CONFIG_FILE="${REPO%/}/.milestone-config/driver.json"

[ -f "$CONFIG_FILE" ] \
  || fail "config not found: ${CONFIG_FILE}. Run the config writer (issue #8) first so protectedBranch is defined; no protection changed."

if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
  fail "config is not valid JSON: ${CONFIG_FILE}. Fix it, then re-run; no protection changed."
fi

PROTECTED_BRANCH="$(jq -r '.protectedBranch // empty' "$CONFIG_FILE")"
[ -n "$PROTECTED_BRANCH" ] \
  || fail "key 'protectedBranch' is missing or empty in ${CONFIG_FILE}. Branch protection cannot be asserted without it; no protection changed."

# --- Resolve the required status-check contexts (#11's CI job names) ----------
# Sourced, never guessed. Prefer the emitted ci.yml's job names; absent that file,
# fall back to the contract names #11 hard-codes. Either way the contexts are the
# stable strings #11/#12 share — never an empty or invented context.
#
# ci.yml is emitted by emit-ci-workflow.sh, which ALWAYS writes both the
# 'unit-tests' and 'preflight' jobs (a missing command becomes a [TBD] step that
# fails loudly; the job name — and thus the context — never drifts). So the job
# keys under `jobs:` are the authoritative contexts when the file exists.
CANONICAL_CONTEXTS=("unit-tests" "preflight")
CI_WORKFLOW="${REPO%/}/.github/workflows/ci.yml"

CONTEXTS=()
if [ -f "$CI_WORKFLOW" ]; then
  # Read the keys directly under the top-level `jobs:` mapping. The emitter writes
  # each job as a 2-space-indented `<name>:` line inside the `jobs:` block; parse
  # exactly that shape (no yq dependency) and stop at the next top-level key.
  while IFS= read -r ctx; do
    [ -n "$ctx" ] && CONTEXTS+=("$ctx")
  done < <(
    awk '
      /^jobs:[[:space:]]*$/ { injobs=1; next }
      injobs && /^[^[:space:]]/ { injobs=0 }
      injobs && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ {
        line=$0
        sub(/^  /, "", line)
        sub(/:[[:space:]]*$/, "", line)
        print line
      }
    ' "$CI_WORKFLOW"
  )
  [ "${#CONTEXTS[@]}" -gt 0 ] \
    || fail "🔴 found ${CI_WORKFLOW} but could not read any CI job name from its 'jobs:' block. The required status-check context is the #11 CI job name; re-emit the CI workflow (issue #11) and re-run rather than guessing a context. No protection changed."
else
  # No emitted workflow yet: use the contract names #11/#12 share verbatim.
  CONTEXTS=("${CANONICAL_CONTEXTS[@]}")
fi

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

# --- Missing-prerequisite edge: the protected branch must already exist (#10) --
gh api "repos/${SLUG}/branches/${PROTECTED_BRANCH}" >/dev/null 2>&1 \
  || fail "🔴 the protected branch '${PROTECTED_BRANCH}' does not exist on '${SLUG}' yet. Provision the branch model first (issue #10 / provision-branches), then re-run — protection is not asserted against a non-existent branch. No protection changed."

# --- Read current protection FIRST (the merge reads from it; absence is fine) -
# A non-weakening floor cannot be a context-free declarative PUT: a full-object
# PUT of the floor alone would reconcile a STRONGER pre-existing setting DOWN
# (restrictions:null would wipe an allowlist, 0 approvals would lower a 2-approval
# rule, strict:false would turn off require-up-to-date). So we GET the existing
# protection and merge the floor INTO it, per field, taking the stronger value.
# A 404 here means "no protection yet" — a normal first-apply state, not an error;
# CURRENT is then empty and the merge collapses to exactly the floor. This GET is
# read-only, so --dry-run runs it too and its preview reflects the true merge.
CURRENT="$(gh api "repos/${SLUG}/branches/${PROTECTED_BRANCH}/protection" 2>/dev/null)" || CURRENT=""
# Feed the merge a JSON object even on a fresh repo: 'null' means "no existing
# protection" and every existing-side lookup falls back to the floor value.
[ -n "$CURRENT" ] || CURRENT="null"

# --- Build the EXACT protection PUT body by MERGING existing-with-floor -------
# Four fields are REQUIRED by the API (each may be null): required_status_checks,
# enforce_admins, required_pull_request_reviews, restrictions. The PUT uses bare
# booleans (the GET response wraps them as {"enabled": ...}); the merge reads the
# wrapped GET shape and emits this flat plan shape. Per field, STRONGER wins:
#   - required_status_checks.contexts = UNION(existing, <#11 job names>)  (add the
#       floor contexts, keep existing extras); strict = existing OR false (preserve
#       an existing require-up-to-date, never turn it off).
#   - required_pull_request_reviews.required_approving_review_count = MAX(existing,
#       0)  (PR required; never lower an existing approval requirement).
#   - enforce_admins=true (floor) · allow_force_pushes=false · allow_deletions=false
#       (false is strongest; an existing false is preserved).
#   - restrictions = the existing allowlist mapped back to the PUT shape (user
#       logins / team slugs / app slugs), PRESERVED; null only when none exists.
# This jq program is shared byte-for-byte with provision-protection.ps1, so both
# emit an identical PUT body from identical inputs.
CONTEXTS_JSON="$(printf '%s\n' "${CONTEXTS[@]}" | jq -R . | jq -s .)"
MERGE_FILTER='. as $cur | {
  required_status_checks: {
    strict: (($cur.required_status_checks.strict) // false),
    contexts: ((($cur.required_status_checks.contexts) // []) + $contexts | unique)
  },
  enforce_admins: true,
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
PUT_BODY="$(printf '%s' "$CURRENT" | jq --argjson contexts "$CONTEXTS_JSON" "$MERGE_FILTER")"

# Normalize the existing protection into the same flat PUT shape (no floor added,
# no UNION/MAX) so an exact match against the merged target means "already at or
# above the floor" — a true no-op. The two filters differ ONLY in that the merge
# unions the floor contexts and floors the approval count; when the existing
# state already meets the floor, that addition is empty and the shapes are equal.
NORMALIZE_FILTER='. as $cur | {
  required_status_checks: {
    strict: (($cur.required_status_checks.strict) // false),
    contexts: ((($cur.required_status_checks.contexts) // []) | unique)
  },
  enforce_admins: true,
  required_pull_request_reviews: {
    required_approving_review_count: (($cur.required_pull_request_reviews.required_approving_review_count) // 0)
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

# The contexts the merged PUT actually carries (UNION result), for display.
CONTEXTS_DISPLAY="$(printf '%s' "$PUT_BODY" | jq -r '.required_status_checks.contexts | join(", ")')"

# --- Preview (--dry-run): print the exact MERGED PUT body; write nothing ------
if [ "$DRY_RUN" -eq 1 ]; then
  echo "milestone-bootstrapper: branch-protection plan for ${SLUG} branch '${PROTECTED_BRANCH}' (preview — nothing written):"
  echo "  required status checks: ${CONTEXTS_DISPLAY}"
  echo "  PUT repos/${SLUG}/branches/${PROTECTED_BRANCH}/protection with body:"
  printf '%s\n' "$PUT_BODY"
  exit 0
fi

# --- No-op when already at-or-above the floor; else reconcile UP --------------
# Compare the existing state (normalized) to the merged target. Equal means the
# merge added nothing — the repo is already at or above the floor, so writing
# would be a pointless re-PUT. (On a fresh repo CURRENT is 'null', so the
# normalized existing differs from the floor target and we proceed to write.)
NORM_CURRENT="$(printf '%s' "$CURRENT" | jq "$NORMALIZE_FILTER")"
if [ "$NORM_CURRENT" = "$PUT_BODY" ]; then
  echo "milestone-bootstrapper: branch protection already meets the suite floor on ${SLUG} branch '${PROTECTED_BRANCH}' (no change)."
  echo "milestone-bootstrapper: required status checks: ${CONTEXTS_DISPLAY}."
  exit 0
fi

# --- Assert / reconcile the protection (merged PUT — never weakens) -----------
# The PUT is existing-merged-with-floor: a re-apply onto an at-or-above-floor repo
# is a no-op (handled above), and a reconcile pulls only the BELOW-floor fields UP
# while preserving every stronger pre-existing rule (extra contexts, extra
# approvals, an allowlist, strict-up-to-date).
if [ "$CURRENT" != "null" ]; then
  echo "milestone-bootstrapper: branch protection on '${PROTECTED_BRANCH}' is below the suite floor — reconciling UP (stronger existing settings are preserved)."
fi

printf '%s' "$PUT_BODY" | gh api -X PUT "repos/${SLUG}/branches/${PROTECTED_BRANCH}/protection" \
  --input - >/dev/null 2>&1 \
  || api_fail "failed to assert branch protection on '${SLUG}' branch '${PROTECTED_BRANCH}' (PUT repos/${SLUG}/branches/${PROTECTED_BRANCH}/protection). No protection was weakened or removed. Re-run after resolving the error (a 403 here means the token lacks repo-admin)."

# --- Read back and verify the floor landed (the acceptance check) -------------
VERIFY="$(gh api "repos/${SLUG}/branches/${PROTECTED_BRANCH}/protection" 2>/dev/null)" \
  || api_fail "asserted protection but could not read it back to verify (GET repos/${SLUG}/branches/${PROTECTED_BRANCH}/protection). Re-run to confirm."

PR_REQUIRED="$(printf '%s' "$VERIFY" | jq -r 'if .required_pull_request_reviews == null then "no" else "yes" end')"
ADMINS_ENFORCED="$(printf '%s' "$VERIFY" | jq -r '.enforce_admins.enabled // false')"
HAS_CONTEXTS="$(printf '%s' "$VERIFY" | jq -r '(.required_status_checks.contexts // []) | length')"
if [ "$PR_REQUIRED" != "yes" ] || [ "$ADMINS_ENFORCED" != "true" ] || [ "${HAS_CONTEXTS:-0}" -eq 0 ]; then
  api_fail "asserted protection but the read-back does not show all three floors (PR required=${PR_REQUIRED}, enforce_admins=${ADMINS_ENFORCED}, status-check contexts=${HAS_CONTEXTS}) on '${PROTECTED_BRANCH}'. Re-run to confirm."
fi

echo "milestone-bootstrapper: branch protection asserted on ${SLUG} branch '${PROTECTED_BRANCH}'."
echo "milestone-bootstrapper: direct pushes blocked, PR required (0 approvals), required status checks: ${CONTEXTS_DISPLAY}; enforce_admins on."
exit 0
