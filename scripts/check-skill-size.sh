#!/usr/bin/env bash
#
# check-skill-size.sh — the CI skill-size gate for SKILL.md word ceilings.
#
# What this checks, in plain terms:
#   Every skills/*/SKILL.md in this repo has a written word-budget: the whole
#   file must stay at or under 2,500 words (wc -w), and its frontmatter
#   description: field must stay at or under ~200 words. The sibling
#   milestone-feeder repo set the same size standard in writing once, then
#   regrew a SKILL.md to 3.4x the target because nothing enforced it — this
#   script is the enforcement that closes that gap here.
#
# Ceilings enforced, verbatim, no rounding:
#   - whole-file word count (wc -w)               <= 2500
#   - frontmatter description: field word count   <= ~200
#
# Deliberately bash-only, no PowerShell twin (a stated exception to this
# repo's cross-platform-twin convention, .project/library-manifest.md#Avoid /
# banned): this is CI-only tooling whose required, primary execution is the
# ubuntu-latest Action runner. It is never part of the suite's cross-platform
# component surface (the scripts/*.{sh,ps1} twins a contributor or a skill
# invokes directly). The sibling milestone-feeder repo already established
# this exact precedent: scripts/check-vocabulary.sh ships bash-only with no
# .ps1 twin and is wired into that repo's CI as a CI-only job.
#
# bash-3.2 compatible on purpose, even though the required execution is the
# ubuntu-latest runner's bash 5: a contributor may still run this locally on
# macOS system bash (3.2) to reproduce a CI failure. No ${var,,}/${var^^}, no
# mapfile/readarray, no declare -A. The skills/*/SKILL.md glob-then-existence-
# check idiom below mirrors scripts/detect-stack.sh:82 (no nullglob shopt
# needed, no array-of-matches required).
#
# Frontmatter description: assumption (matches every SKILL.md in this repo
# today — skills/plan, skills/apply, skills/update): description: is a single-
# line YAML scalar between the first two `---` frontmatter fences. A folded
# or block-scalar (multi-line) description is not handled — none exists in
# this repo, and adding that generality now would be speculative, not
# grounded in a real case.
#
# Run it locally from the repo root: ./scripts/check-skill-size.sh
# Exit 0 = every skills/*/SKILL.md is within both ceilings (or none exist).
# Exit 1 = at least one SKILL.md breached a ceiling — the offending file, the
#          ceiling breached, and its actual word count are printed to stderr.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FILE_CEILING=2500
DESC_CEILING=200

fail=0
found_any=0

for f in skills/*/SKILL.md; do
  [ -e "$f" ] || continue
  found_any=1

  # --- whole-file ceiling ---
  words="$(wc -w < "$f" | tr -d ' ')"
  if [ "$words" -gt "$FILE_CEILING" ]; then
    echo "FAIL: ${f} — whole-file word count is ${words}, exceeds the ${FILE_CEILING}-word ceiling." >&2
    fail=1
  fi

  # --- frontmatter description: ceiling ---
  # Between the first two `---` fences, grab the description: line if present.
  # Absent key -> empty match -> skip gracefully, never a crash (edge case).
  desc_line="$(awk '/^---$/{n++; next} n==1 && /^description:/{print; exit}' "$f")"
  if [ -n "$desc_line" ]; then
    desc_words="$(printf '%s' "$desc_line" | sed 's/^description:[[:space:]]*//' | wc -w | tr -d ' ')"
    if [ "$desc_words" -gt "$DESC_CEILING" ]; then
      echo "FAIL: ${f} — frontmatter description: word count is ${desc_words}, exceeds the ~${DESC_CEILING}-word ceiling." >&2
      fail=1
    fi
  fi
done

if [ "$found_any" -eq 0 ]; then
  echo "PASS: no skills/*/SKILL.md files found — nothing to check."
  exit 0
fi

if [ "$fail" -eq 1 ]; then
  exit 1
fi

echo "PASS: every skills/*/SKILL.md is within the whole-file (<= ${FILE_CEILING} words) and description: (<= ~${DESC_CEILING} words) ceilings."
exit 0
