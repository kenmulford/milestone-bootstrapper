#!/usr/bin/env bash
#
# check-driver-config.sh — re-derive the milestone-driver `domainSkills` slice from
# live repo signals and set-compare it against what `.milestone-config/driver.json`
# already records, reporting drift. STRICTLY READ-ONLY: never writes or rewrites
# driver.json, on any code path (including under --check). The domainSkills-scoped
# sibling of check-project-docs.sh (which owns the `.project/` freshness slice);
# this script owns EXACTLY one field of one file — driver.json's `domainSkills`
# array — and touches nothing else. Advisory only: a human decides whether reported
# drift is real or an intentional override.
#
# What this does, in plain terms:
#   Re-runs scripts/detect-stack.sh against the repo to re-derive the detected
#   application stack(s), unions the `domainSkills` column of every NON-EXEMPT
#   app-stack row into a detected set, and set-compares it (order-insensitive,
#   duplicates collapsed) against driver.json's recorded `domainSkills` array. Any
#   difference in either direction is reported as DRIFT. It never edits driver.json;
#   it only reports.
#
# Reuse, never reimplement: the stack detection is scripts/detect-stack.sh, invoked
#   as an external subprocess and parsed from its TSV stdout. This script duplicates
#   none of that per-stack detection logic. JSON parsing / set arithmetic is jq
#   (already an approved, present dependency — .project/library-manifest.md).
#
# Row classification (three-way; mirrors the sentinel predicate of
#   check-project-docs.sh:144-163, then adds a Ruby-exemption layer):
#   - SENTINEL — a detect-stack TSV row with flag=="human" AND stack in
#     {none,(multi-stack)} is a meta row, not an application stack — excluded from
#     the compare and surfaced as an informational note. (A flag=="human" row that
#     is NOT one of those two, e.g. an unresolved-framework `Node ([TBD])` row, is
#     still a real app-stack row and IS compared.)
#   - EXEMPT — a non-sentinel row whose stack is EXACTLY `Ruby (Rails)` or
#     `Ruby (generic)` (detect-stack.sh:309/317) is excluded from the compare
#     entirely (neither detected nor drift) and surfaced as a sentinel note.
#     detect-stack maps both Ruby rows to
#     ["ruby-lsp","superpowers:test-driven-development","superpowers:systematic-debugging"]
#     (detect-stack.sh:300) — a documented, TRACKED divergence from the driver's own
#     Stack->domainSkills table (detect-stack.sh:12-23, resolves #104), so comparing
#     it against driver.json would false-positive on every Ruby/Rails repo. This is
#     NOT an error in either script. Do NOT extend this allowlist to any other stack.
#   - APP — every other row is a real, non-exempt application stack; its
#     `domainSkills` column (a JSON array literal or empty) joins the detected set.
#
# Nothing-to-compare (exit 0 ALWAYS, even under --check):
#   - detect-stack finds NO application stack (solely the `none` sentinel,
#     detect-stack.sh:355-364), OR every detected app-stack row is Ruby-exempt: the
#     non-exempt app set is empty, so there is nothing to compare.
#   - An empty DETECTED set with a non-empty RECORDED array is NOT this case — that
#     is a legitimate compare (every recorded entry reports as "recorded but not
#     detected"); it only happens when non-exempt app rows exist but all map to an
#     empty domainSkills column (e.g. Node (generic), .NET (non-MAUI), Rust).
#
# Inputs:
#   --check          make drift a nonzero exit (CI gate). Without it, drift is
#                    informational only (exit 0).
#   --repo <dir>     repo root to check (default: $PWD). detect-stack is invoked
#                    against this dir and driver.json is read from
#                    <dir>/.milestone-config/driver.json. Mirrors detect-stack.sh's
#                    [REPO_DIR] convention; lets the check point at a fixture dir.
#   -h|--help        print this header comment.
#
# Exit codes (per-failure-class, mirroring check-project-docs.sh):
#   0  ran cleanly — no drift; OR drift reported but --check was NOT passed; OR
#      nothing to compare (no non-exempt application stack), always, even under
#      --check.
#   1  usage / read error — bad flag, jq absent, --repo not a directory, missing
#      driver.json, malformed/missing domainSkills in driver.json, a detect-stack
#      invocation failure, or unparseable TSV output. ALWAYS nonzero regardless of
#      --check.
#   2  drift detected AND --check was passed (the ONLY path where drift is nonzero).
#
# Run it:
#   ./scripts/check-driver-config.sh
#   ./scripts/check-driver-config.sh --check
#   ./scripts/check-driver-config.sh --repo /path/to/other/repo --check

set -euo pipefail

readonly DRIVER_REL='.milestone-config/driver.json'
readonly RUBY_RAILS='Ruby (Rails)'
readonly RUBY_GENERIC='Ruby (generic)'

CHECK=0
REPO="$PWD"

# --- Inputs (long-option while/case loop, mirroring check-project-docs.sh) -----
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --repo)  REPO="${2:?--repo needs a value}"; shift 2 ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1 ;;
  esac
done

# jq is a hard requirement here (both driver.json and each row's domainSkills column
# are parsed via jq). Unlike detect-stack.sh, this script has no jq-absent fallback.
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for check-driver-config.sh but was not found on PATH." >&2
  exit 1
fi

# Strip ALL trailing slashes (parity with the pwsh twin's TrimEnd('/','\')); a
# POSIX path only needs '/'. `--repo /a//` and `--repo /a` normalize identically.
while [ "$REPO" != "${REPO%/}" ]; do REPO="${REPO%/}"; done
if [ ! -d "$REPO" ]; then
  echo "ERROR: --repo is not a directory: ${REPO}" >&2
  exit 1
fi

# detect-stack.sh is a sibling of this script; find it via this script's own dir
# (not $PWD/--repo), so --repo can point at a fixture that has no scripts/ of its own.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECT="${SCRIPT_DIR}/detect-stack.sh"
if [ ! -f "$DETECT" ]; then
  echo "ERROR: detect-stack.sh not found next to this script: ${DETECT}" >&2
  exit 1
fi

DRIVER="${REPO}/${DRIVER_REL}"

# --- Re-run detect-stack (external subprocess; never reimplemented) -----------
# Capture stdout and the real exit code without letting `set -e` abort on a
# nonzero detect-stack exit (that is a reportable condition, not a crash).
set +e
DETECT_OUT="$(bash "$DETECT" "$REPO" 2>/dev/null)"
DETECT_RC=$?
set -e
if [ "$DETECT_RC" -ne 0 ]; then
  echo "ERROR: detect-stack.sh failed (exit ${DETECT_RC}) — the drift check could not run." >&2
  exit 1
fi

# First line MUST be the exact literal TSV header; otherwise the output is
# unparseable. Full-literal equality (the exact string detect-stack.sh always
# emits, detect-stack.sh:353) — identical to the pwsh twin's check, so the two
# twins cannot diverge on header strictness.
HEADER="${DETECT_OUT%%$'\n'*}"
EXPECTED_HEADER="$(printf 'stack\tsignal\tconvention\tmanifestPin\tdomainSkills\tflag\tversionFile')"
if [ "$HEADER" != "$EXPECTED_HEADER" ]; then
  echo "ERROR: detect-stack.sh output could not be parsed (missing TSV header) — the drift check could not run." >&2
  exit 1
fi

# --- Classify rows: sentinel / Ruby-exempt / real app stack -------------------
# Field extraction uses awk (-F'\t'), NOT `IFS=$'\t' read`: tab is a whitespace-
# class IFS char, so `read` collapses consecutive tabs — awk keeps every field
# positional. It emits `kind<TAB>stack<TAB>domainSkills` per data row; the first
# two fields are always non-empty and only the (possibly empty) domainSkills field
# is trailing, so the downstream `read -r kind stack skills` is collapse-safe.
CLASSIFIED="$(printf '%s\n' "$DETECT_OUT" | awk -F'\t' -v ruby_rails="$RUBY_RAILS" -v ruby_generic="$RUBY_GENERIC" '
  NR == 1 { next }                         # skip header
  $1 == "" { next }
  {
    if ($6 == "human" && ($1 == "none" || $1 == "(multi-stack)"))
      printf "sentinel\t%s\t%s\n", $1, $5
    else if ($1 == ruby_rails || $1 == ruby_generic)
      printf "exempt\t%s\t%s\n", $1, $5
    else
      printf "app\t%s\t%s\n", $1, $5
  }
')"

NOTES=()          # sentinel + exempt informational notes, in row-encounter order
APP_OBJS=""       # NDJSON accumulator: one {stack,skills} object per non-exempt app row
APP_COUNT=0
while IFS=$'\t' read -r kind stack skills; do
  [ -z "$kind" ] && continue
  case "$kind" in
    sentinel) NOTES+=("sentinel row — skipped: ${stack}") ;;
    exempt)   NOTES+=("exempt row — skipped (tracked divergence, resolves #104): ${stack}") ;;
    app)
      # An empty domainSkills column is a legitimate empty array (omit rows:
      # detect-stack.sh:29-30), not an error.
      [ -z "$skills" ] && skills='[]'
      # Validate the domainSkills cell is parseable JSON AND an array-of-strings
      # BEFORE feeding it to `jq --argjson` — otherwise a malformed cell would let
      # `set -e` abort with jq's own raw error and jq's exit code 2, colliding with
      # this script's documented exit 2 (drift + --check). Fail cleanly as a
      # usage/read error (exit 1) with a framed message mirroring the missing-header
      # error's phrasing. Only app rows reach here; sentinel/exempt cells are unused.
      if ! printf '%s' "$skills" | jq -e '(type=="array") and (all(.[]; type=="string"))' >/dev/null 2>&1; then
        echo "ERROR: detect-stack.sh output could not be parsed (domainSkills for stack '${stack}' is not a valid JSON array) — the drift check could not run." >&2
        exit 1
      fi
      APP_OBJS+="$(jq -cn --arg s "$stack" --argjson k "$skills" '{stack:$s, skills:$k}')"$'\n'
      APP_COUNT=$((APP_COUNT + 1)) ;;
  esac
done <<< "$CLASSIFIED"

# --- Print sentinel + exempt notes, in encounter order, before anything else --
if [ "${#NOTES[@]}" -gt 0 ]; then
  for n in "${NOTES[@]}"; do echo "$n"; done
fi

# --- Nothing to compare: no non-exempt app stack (exit 0, even under --check) --
if [ "$APP_COUNT" -eq 0 ]; then
  echo "nothing to compare — no non-exempt application stack detected."
  exit 0
fi

# --- There is something to compare: driver.json is now required ---------------
if [ ! -f "$DRIVER" ]; then
  echo "ERROR: .milestone-config/driver.json not found — run milestone-driver:setup first." >&2
  exit 1
fi
# domainSkills must be present AND a JSON array (an empty array [] is VALID). A
# parse failure, an absent key, or a non-array value all fail this one check.
if ! jq -e '(.domainSkills | type) == "array"' "$DRIVER" >/dev/null 2>&1; then
  echo "ERROR: .milestone-config/driver.json domainSkills is missing or malformed — fix the JSON, then re-run." >&2
  exit 1
fi

# --- Set-compare recorded vs detected domainSkills ----------------------------
APP_JSON="$(printf '%s' "$APP_OBJS" | jq -s '.')"
RECORDED_JSON="$(jq -c '.domainSkills | unique' "$DRIVER")"
DETECTED_JSON="$(printf '%s' "$APP_JSON" | jq -c '[.[].skills[]] | unique')"

# recorded - detected  and  detected - recorded (both sorted, duplicates collapsed).
RECORDED_NOT_DETECTED="$(jq -rn --argjson r "$RECORDED_JSON" --argjson d "$DETECTED_JSON" '($r - $d) | sort | .[]')"
DETECTED_NOT_RECORDED="$(jq -rn --argjson r "$RECORDED_JSON" --argjson d "$DETECTED_JSON" '($d - $r) | sort | .[]')"
# Loop-entry signal is the jq ARRAY LENGTH (an unambiguous integer), NOT the captured
# string's emptiness. bash `$(...)` strips ALL trailing newlines, so a diff set whose
# SOLE element is a genuine empty string "" (raw jq output "\n") collapses to a literal
# empty capture — byte-for-byte identical to the zero-element case. Testing the string
# with `[ -n ... ]` would then treat that real single empty-string entry as "no diff"
# and silently under-report drift. The count is derived from the SAME set expressions.
RECORDED_NOT_DETECTED_COUNT="$(jq -n --argjson r "$RECORDED_JSON" --argjson d "$DETECTED_JSON" '($r - $d) | length')"
DETECTED_NOT_RECORDED_COUNT="$(jq -n --argjson r "$RECORDED_JSON" --argjson d "$DETECTED_JSON" '($d - $r) | length')"

DRIFT_LINES=()
# Gate on the integer count, not the WHOLE variable's emptiness: a bash `<<<"$VAR"`
# here-string always feeds one phantom line even when $VAR is empty, so the count
# guards the loop against that phantom, while a within-content blank line (including
# the sole-empty-string diff element the string-emptiness test could not see) is
# processed normally. Skipping per-line blanks (the old `[ -z "$skill" ] && continue`)
# would silently drop a legitimate empty-string domainSkills entry ("").
if [ "$RECORDED_NOT_DETECTED_COUNT" -gt 0 ]; then
  while IFS= read -r skill; do
    DRIFT_LINES+=("DRIFT — domainSkills '${skill}' recorded in driver.json but not detected by any current app stack")
  done <<< "$RECORDED_NOT_DETECTED"
fi
if [ "$DETECTED_NOT_RECORDED_COUNT" -gt 0 ]; then
  while IFS= read -r skill; do
    # Which non-exempt app-stack row(s) contributed this skill (sorted, joined by ", ").
    contrib="$(printf '%s' "$APP_JSON" | jq -r --arg s "$skill" '[.[] | select(.skills | index($s)) | .stack] | unique | sort | join(", ")')"
    DRIFT_LINES+=("DRIFT — domainSkills '${skill}' detected by app stack '${contrib}' but absent from driver.json")
  done <<< "$DETECTED_NOT_RECORDED"
fi

# --- Report + exit ------------------------------------------------------------
if [ "${#DRIFT_LINES[@]}" -eq 0 ]; then
  echo "no drift — driver.json domainSkills matches the currently detected app stack(s)."
  exit 0
fi

for l in "${DRIFT_LINES[@]}"; do echo "$l"; done
echo "drift: ${#DRIFT_LINES[@]} domainSkills difference(s) between driver.json and detected app stack(s)."
if [ "$CHECK" -eq 1 ]; then
  exit 2
fi
echo "(informational only — re-run with --check to make drift a CI failure.)"
exit 0
