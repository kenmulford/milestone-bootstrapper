#!/usr/bin/env bash
#
# provision-branches.sh — provision the suite's branch model idempotently.
#
# What this does, in plain terms:
#   The `apply` and `update` verbs call this to guarantee the target repo's two
#   suite branches exist and the default-branch policy points at the protected
#   branch, so milestone-feeder and milestone-driver run with no further branch
#   setup. It creates the protected branch if missing, branches the integration
#   branch off it if missing, and sets the repo's default branch to the protected
#   branch if that policy is not already in place. It NEVER deletes a branch,
#   force-pushes, or resets an existing branch — a re-run on an already-correct
#   repo changes nothing (idempotent, adopt-or-init).
#
# Branch names are SOURCED, never chosen:
#   `integrationBranch` and `protectedBranch` are read from the target repo's
#   `.milestone-config/driver.json` (written by issue #8). The bootstrapper does
#   not invent or default these names — an absent file or empty key is a clear
#   precondition failure, never a guessed name. (Issue #10 Design; sibling shape
#   at milestone-driver/milestone-driver.json:1-2.)
#
# Order (BRIEF.md §"Sequencing hints" — "branch model" before protection/CI;
#   integration is branched FROM protected):
#   1. protected branch  (the base/root)
#   2. integration branch (created from protected when fresh)
#   3. default-branch policy -> protected
#
# Scope of this step (Issue #10 Design): ensure the two branches exist and set
#   the default-branch policy. It does NOT configure branch-protection rules
#   (no-direct-push / required PR / required status check) — that is a separate,
#   later step (issue #11) that depends on this one. BRIEF.md §"Job 2" lists
#   "Branch model" and "Branch protection" as two distinct bullets.
#
# Preconditions:
#   `gh` installed and authenticated, run inside a GitHub-connected working
#   directory, with a token that can create branches and change the default
#   branch (repo-admin). If a precondition is unmet, this names it and exits
#   non-zero before touching anything — never a silent failure (BRIEF.md
#   §"Constraints" line 82). Cross-platform companion: provision-branches.ps1.
#
# Preview (`plan`): pass --dry-run to print the intended branch-model actions
#   (which branches it would create, the default-branch policy it would set)
#   without writing anything to the remote — the preview-then-execute split the
#   `plan` verb records into its provisioning plan (BRIEF.md §"The surface").
#
# Run it:  ./scripts/provision-branches.sh [--repo /path/to/target] [--dry-run]
# Exit 0 = branches present and default-branch policy correct (or previewed).
# Exit 1 = precondition unmet / config missing / empty repo (nothing changed).
# Exit 2 = GitHub API failure mid-step (reports what was / was not done).

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

# fail <msg>  — precondition / config / empty-repo failure: nothing changed.
fail() {
  echo "milestone-bootstrapper: $1" >&2
  exit 1
}

# api_fail <msg> — a GitHub API operation failed mid-step. Reports what was and
# was not done; never deletes or force-pushes to recover. Exit 2 so the
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
  || fail "GitHub CLI is not authenticated. Run 'gh auth login' (with a token that can create branches and set the default branch), then re-run."

gh repo view >/dev/null 2>&1 \
  || fail "the working directory is not connected to a GitHub repository (or the repo is unreachable). Run this inside a repo with a GitHub remote, then re-run."

# --- Read the branch names from the target repo's driver.json ----------------
# Names are sourced, never chosen: an absent file or empty key is a precondition
# failure, never a guessed name (Issue #10 Design).

CONFIG_FILE="${REPO%/}/.milestone-config/driver.json"

[ -f "$CONFIG_FILE" ] \
  || fail "config not found: ${CONFIG_FILE}. Run the config writer (issue #8) first so integrationBranch / protectedBranch are defined; no branch created, no policy changed."

if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
  fail "config is not valid JSON: ${CONFIG_FILE}. Fix it, then re-run; no branch created, no policy changed."
fi

# jq '// empty' collapses an absent key, JSON null, AND an empty string to the
# same "missing" signal — so each is reported by name with the file path.
PROTECTED_BRANCH="$(jq -r '.protectedBranch // empty' "$CONFIG_FILE")"
INTEGRATION_BRANCH="$(jq -r '.integrationBranch // empty' "$CONFIG_FILE")"

[ -n "$PROTECTED_BRANCH" ] \
  || fail "key 'protectedBranch' is missing or empty in ${CONFIG_FILE}. The branch model cannot be provisioned without it; no branch created, no policy changed."
[ -n "$INTEGRATION_BRANCH" ] \
  || fail "key 'integrationBranch' is missing or empty in ${CONFIG_FILE}. The branch model cannot be provisioned without it; no branch created, no policy changed."

# --- Resolve owner/repo once (all branch + ref ops are keyed on it) -----------
SLUG="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" \
  || api_fail "could not resolve the GitHub repository (owner/name). Nothing changed."
[ -n "$SLUG" ] || api_fail "could not resolve the GitHub repository (owner/name). Nothing changed."

# branch_exists <name> — 0 if the branch exists on the remote, 1 if it does not.
# The branches endpoint returns the branch object (exit 0) or HTTP 404 (exit 1);
# an empty repo returns []/409 from the ref endpoint, handled by base_sha.
branch_exists() {
  gh api "repos/${SLUG}/branches/$1" >/dev/null 2>&1
}

# base_sha — the commit SHA to branch the protected branch FROM when it is
# missing. Prefers the protected branch ref itself (no-op when it exists), then
# the repo's reported default branch. Prints the SHA, or nothing for an empty
# repo (no commit/ref yet) — the caller turns "nothing" into the empty-repo
# precondition message.
base_sha() {
  local sha
  sha="$(gh api "repos/${SLUG}/git/ref/heads/${PROTECTED_BRANCH}" --jq '.object.sha' 2>/dev/null)" || sha=""
  if [ -z "$sha" ]; then
    local default_branch
    default_branch="$(gh api "repos/${SLUG}" --jq '.default_branch' 2>/dev/null)" || default_branch=""
    if [ -n "$default_branch" ]; then
      sha="$(gh api "repos/${SLUG}/git/ref/heads/${default_branch}" --jq '.object.sha' 2>/dev/null)" || sha=""
    fi
  fi
  printf '%s' "$sha"
}

# create_branch <name> <sha> — create a ref non-destructively. The git/refs POST
# only ever CREATES (it 422s if the ref already exists); it can never overwrite
# or force-update, so there is no destructive path here.
create_branch() {
  gh api "repos/${SLUG}/git/refs" \
    -f "ref=refs/heads/$1" -f "sha=$2" >/dev/null 2>&1
}

# --- Inspect current state (adopt-or-init: act only on what is missing) -------
CURRENT_DEFAULT="$(gh api "repos/${SLUG}" --jq '.default_branch' 2>/dev/null)" || CURRENT_DEFAULT=""

PROTECTED_PRESENT=0; branch_exists "$PROTECTED_BRANCH"   && PROTECTED_PRESENT=1
INTEGRATION_PRESENT=0; branch_exists "$INTEGRATION_BRANCH" && INTEGRATION_PRESENT=1

# The default-branch placeholder of an empty repo (e.g. "main") is NOT a real
# ref, so treat the policy as "already correct" only when the protected branch
# actually exists. Otherwise we'd report a no-op while no branch exists.
DEFAULT_CORRECT=0
if [ "$CURRENT_DEFAULT" = "$PROTECTED_BRANCH" ] && [ "$PROTECTED_PRESENT" -eq 1 ]; then
  DEFAULT_CORRECT=1
fi

# --- Plan the actions (shared by --dry-run preview and the executor) ----------
PLAN_PROTECTED="exists (adopt)"
[ "$PROTECTED_PRESENT" -eq 0 ] && PLAN_PROTECTED="CREATE from base commit"
PLAN_INTEGRATION="exists (adopt)"
[ "$INTEGRATION_PRESENT" -eq 0 ] && PLAN_INTEGRATION="CREATE from ${PROTECTED_BRANCH}"
PLAN_DEFAULT="already ${PROTECTED_BRANCH} (no-op)"
[ "$DEFAULT_CORRECT" -eq 0 ] && PLAN_DEFAULT="SET to ${PROTECTED_BRANCH} (currently: ${CURRENT_DEFAULT:-<none>})"

print_plan() {
  printf '  protected   (%s): %s\n' "$PROTECTED_BRANCH" "$PLAN_PROTECTED"
  printf '  integration (%s): %s\n' "$INTEGRATION_BRANCH" "$PLAN_INTEGRATION"
  printf '  default-branch policy: %s\n' "$PLAN_DEFAULT"
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "milestone-bootstrapper: branch-model plan for ${SLUG} (preview — nothing written):"
  print_plan
  # Empty-repo preview: surface that a base commit is required, but write nothing.
  if [ "$PROTECTED_PRESENT" -eq 0 ] && [ -z "$(base_sha)" ]; then
    echo "milestone-bootstrapper: 🔴 note: the repository has no commit yet; an initial commit/ref is required before the protected branch can be created." >&2
  fi
  exit 0
fi

# --- Execute (idempotent; create only what is missing) -----------------------
CHANGED=0

# 1. Protected branch — the base/root. Created from a base commit when missing.
if [ "$PROTECTED_PRESENT" -eq 0 ]; then
  SHA="$(base_sha)"
  [ -n "$SHA" ] \
    || fail "🔴 cannot create the protected branch '${PROTECTED_BRANCH}': the repository has no commit yet. Make an initial commit (e.g. 'git commit --allow-empty' then push), then re-run. Nothing changed."
  create_branch "$PROTECTED_BRANCH" "$SHA" \
    || api_fail "failed to create the protected branch '${PROTECTED_BRANCH}'. Nothing was deleted or force-pushed; no further step ran. Re-run after resolving the error."
  echo "milestone-bootstrapper: created protected branch '${PROTECTED_BRANCH}'."
  PROTECTED_PRESENT=1
  CHANGED=1
fi

# 2. Integration branch — branched FROM the (now-present) protected branch.
if [ "$INTEGRATION_PRESENT" -eq 0 ]; then
  SHA="$(gh api "repos/${SLUG}/git/ref/heads/${PROTECTED_BRANCH}" --jq '.object.sha' 2>/dev/null)" || SHA=""
  [ -n "$SHA" ] \
    || api_fail "cannot branch '${INTEGRATION_BRANCH}' from '${PROTECTED_BRANCH}': the protected branch ref could not be resolved. The protected branch was left in place; no force-push, no deletion. Re-run after resolving the error."
  create_branch "$INTEGRATION_BRANCH" "$SHA" \
    || api_fail "failed to create the integration branch '${INTEGRATION_BRANCH}' from '${PROTECTED_BRANCH}'. The protected branch was left in place; no force-push, no deletion. Re-run after resolving the error."
  echo "milestone-bootstrapper: created integration branch '${INTEGRATION_BRANCH}' from '${PROTECTED_BRANCH}'."
  INTEGRATION_PRESENT=1
  CHANGED=1
fi

# 3. Default-branch policy — set to protected only when it does not already match.
if [ "$DEFAULT_CORRECT" -eq 0 ]; then
  gh repo edit "$SLUG" --default-branch "$PROTECTED_BRANCH" >/dev/null 2>&1 \
    || api_fail "failed to set the default branch to '${PROTECTED_BRANCH}'. Branches already created were left in place; no force-push, no deletion. Re-run after resolving the error."
  echo "milestone-bootstrapper: set default branch to '${PROTECTED_BRANCH}'."
  CHANGED=1
fi

if [ "$CHANGED" -eq 0 ]; then
  echo "milestone-bootstrapper: branch model already correct for ${SLUG} (no change)."
else
  echo "milestone-bootstrapper: branch model provisioned for ${SLUG}."
fi
exit 0
