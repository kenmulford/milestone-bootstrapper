#!/usr/bin/env bash
#
# provision-labels.sh — provision the suite's label taxonomy idempotently.
#
# What this does, in plain terms:
#   The `apply` and `update` verbs call this to guarantee that every label
#   milestone-driver and milestone-feeder rely on already exists in the target
#   GitHub repo, so both downstream tools run with no further label setup. It
#   creates the eleven labels (six from the driver, four from the feeder, one
#   from the suite) if they are missing, and upserts color + description if
#   they already exist — so a re-run never produces duplicates and corrects
#   any drifted color/description.
#
# Why provision in-house (not by invoking the sibling setup skills):
#   `milestone-driver:setup` and `milestone-feeder:setup` also write config and
#   run an interview, so invoking them solely for labels is the wrong tool. We
#   reuse the canonical `gh label create --force` idiom and the exact taxonomy
#   values those skills own — never a second, drifting definition. (BRIEF.md
#   §"Job 2" line 52, §"Recorded design decisions" line 68.)
#
# Taxonomy source of truth (verbatim):
#   Driver slice — milestone-driver/skills/setup/SKILL.md:178-186, :205-211
#   Feeder slice — milestone-feeder/skills/setup/SKILL.md:95-100,  :107-110
#   Suite slice  — bootstrapper-owned; canonical prose enumeration SPEC.md §6.3
#
# Preconditions:
#   `gh` installed and authenticated, run inside a GitHub-connected working
#   directory. If a precondition is unmet, this names it and exits non-zero
#   before touching any label — never a silent failure (BRIEF.md §"Constraints"
#   line 82). Cross-platform companion: provision-labels.ps1.

set -euo pipefail

fail() {
  echo "milestone-bootstrapper: $1" >&2
  exit 1
}

# api_fail <msg> — the post-write read-back still disagrees after one retry.
# Never a silent pass-through; exit 2 mirrors the sibling scripts' mid-run
# API-failure code (provision-branches.sh, provision-protection.sh).
api_fail() {
  echo "milestone-bootstrapper: 🔴 $1" >&2
  exit 2
}

# --- Preconditions (surface the unmet one by name; provision nothing) --------

command -v gh >/dev/null 2>&1 \
  || fail "GitHub CLI ('gh') is not installed or not on PATH. Install it from https://cli.github.com, then re-run."

command -v jq >/dev/null 2>&1 \
  || fail "'jq' is required but not found on PATH (needed to parse the post-write label read-back). Install jq, then re-run."

gh auth status >/dev/null 2>&1 \
  || fail "GitHub CLI is not authenticated. Run 'gh auth login' (with a token that can manage labels), then re-run."

gh repo view >/dev/null 2>&1 \
  || fail "the working directory is not connected to a GitHub repository (or the repo is unreachable). Run this inside a repo with a GitHub remote, then re-run."

# --- Legacy reconcile (runs FIRST, before the bulk block) --------------------
# A legacy 'judgment-call' / '⚠ judgment-call' label may predate the canonical
# 'judgment call' name. Renaming it here preserves all existing issue/PR
# associations before the upsert block re-asserts its color/description. If
# neither legacy name exists the edit errors harmlessly — tolerated, not fatal
# (so it cannot abort the run under `set -e`).
# Reference: milestone-driver/skills/setup/SKILL.md:189-198.
gh label edit "judgment-call"   --name "judgment call" --color FBCA04 >/dev/null 2>&1 || true
gh label edit "⚠ judgment-call" --name "judgment call" --color FBCA04 >/dev/null 2>&1 || true

# --- Label taxonomy: single source of truth for both upsert and read-back ---
# Parallel arrays (bash 3.2-safe — no associative arrays), one element per
# label, index-aligned. Defined once so the post-write read-back below (issue
# #109) compares against exactly what was just asserted rather than a second,
# driftable copy. Values verbatim from SPEC.md §6.3.
#   Driver slice (6)  — milestone-driver/skills/setup/SKILL.md:205-211
#   Feeder slice (4)  — milestone-feeder/skills/setup/SKILL.md:107-110
#   Suite slice  (1)  — bootstrapper-owned; canonical prose enumeration SPEC.md §6.3
LABEL_NAMES=(
  "in progress" "blocked" "needs design" "needs decision" "needs review" "judgment call"
  "ui" "logic" "risk:light" "risk:heavy"
  "md-epic"
)
LABEL_COLORS=(
  1D76DB B60205 5319E7 D93F0B 0E8A16 FBCA04
  5319E7 0E8A16 C2E0C6 B60205
  006B75
)
LABEL_DESCRIPTIONS=(
  "Branch open with partial or parked work; not yet done"
  "Can't proceed; waiting on something external (unmerged dependency, unverified E2E)"
  "Design direction required before building"
  "Non-design human decision required"
  "Built; awaiting human review/merge (e.g. a UI PR awaiting visual sign-off)"
  "Borderline autonomous call — audit post-run"
  "UI-surface issue (design review applies)"
  "Logic / non-UI issue"
  "Reduced-ceremony build profile (driver override)"
  "Full-ceremony build profile (driver override)"
  "Parent issue grouping several milestones into one ordered feature (driver builds them in order)"
)

# upsert_labels — idempotent `--force` upsert over the taxonomy above: creates
# a missing label, corrects a drifted color/description, never duplicates on
# re-run. Callable more than once (the retry below re-invokes it verbatim).
upsert_labels() {
  local i
  for ((i = 0; i < ${#LABEL_NAMES[@]}; i++)); do
    gh label create "${LABEL_NAMES[$i]}" --color "${LABEL_COLORS[$i]}" \
      --description "${LABEL_DESCRIPTIONS[$i]}" --force
  done
}

upsert_labels
echo "milestone-bootstrapper: provisioned 11 labels (6 driver + 4 feeder + 1 suite)."

# --- Read-back verify + one bounded retry (issue #109) -----------------------
# GitHub's API can accept a label write (exit 0) that doesn't durably stick
# (eventual consistency) — the upsert above succeeding is not on its own proof
# the taxonomy landed. Compare `gh label list` against the same eleven
# name/color/description triples the upsert just asserted; on any mismatch,
# retry the upsert exactly ONCE and re-verify before halting — never a second
# retry (`.project/design-philosophy.md#Error & failure philosophy`; mirrors
# `provision-protection.sh`'s existing read-back-and-halt sibling pattern).
#
# verify_labels — echoes each diverged label's name (one per line) and returns
# non-zero if any label's read-back doesn't match; returns 0 when all match.
# `--limit 100` covers the taxonomy plus any pre-existing repo labels; color is
# compared case-insensitively via jq's ascii_downcase (GitHub normalizes hex
# color casing on read-back).
verify_labels() {
  local actual i name color desc mismatched=0
  actual="$(gh label list --json name,color,description --limit 100 2>/dev/null)" || actual="[]"
  for ((i = 0; i < ${#LABEL_NAMES[@]}; i++)); do
    name="${LABEL_NAMES[$i]}"; color="${LABEL_COLORS[$i]}"; desc="${LABEL_DESCRIPTIONS[$i]}"
    if ! printf '%s' "$actual" | jq -e --arg n "$name" --arg c "$color" --arg d "$desc" \
        'any(.[]; .name == $n and (.color | ascii_downcase) == ($c | ascii_downcase) and .description == $d)' \
        >/dev/null 2>&1; then
      echo "$name"
      mismatched=1
    fi
  done
  return "$mismatched"
}

if ! MISMATCHED="$(verify_labels)"; then
  echo "milestone-bootstrapper: label read-back drift for: ${MISMATCHED//$'\n'/, } — retrying once."
  upsert_labels
  if ! MISMATCHED="$(verify_labels)"; then
    api_fail "label read-back still diverges after one retry for: ${MISMATCHED//$'\n'/, }. Labels already correct were left in place; re-run after resolving the drift."
  fi
fi
