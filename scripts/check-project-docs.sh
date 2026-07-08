#!/usr/bin/env bash
#
# check-project-docs.sh — re-derive the machine-derivable slice of the `.project/`
# docs from live repo signals and diff it against what the docs already record,
# reporting drift. STRICTLY READ-ONLY: never writes or rewrites any `.project/`
# file, on any code path. The freshness-check counterpart to write-project-docs.sh
# (which is the writer); this is the auditor.
#
# What this does, in plain terms:
#   Re-runs scripts/detect-stack.sh against the repo to re-derive the detected
#   application stack(s), then checks — for each detected stack — whether that
#   stack's identifying name appears in the captured content of
#   `.project/library-manifest.md#Runtime & frameworks`. A detected stack whose
#   name the manifest does NOT mention is reported as DRIFT. It never edits any
#   `.project/` file; it only reports. Scope is EXACTLY this one doc+anchor (the
#   whole of issue #129); it does not diff conventions.md, domainSkills, or any
#   other `.project/` doc.
#
# Reuse, never reimplement: the stack detection is scripts/detect-stack.sh,
#   invoked as an external subprocess and parsed from its TSV stdout. This script
#   duplicates none of that per-stack detection logic.
#
# Sentinel / skipped rows (surfaced as INFORMATIONAL notes, neither drift nor
#   no-drift — mirroring detect-stack's own flag-don't-guess discipline,
#   .project/design-philosophy.md#Error & failure philosophy):
#   - a detect-stack TSV row with flag=="human" AND stack in {none,(multi-stack)}
#     is a meta/sentinel row, not an application stack — excluded from comparison.
#     (A flag=="human" row that is NOT one of those two, e.g. an unresolved-
#     framework `Node ([TBD])` row, is still a real app-stack row and IS compared.)
#   - when detect-stack finds NO application stack at all (solely the `none`
#     sentinel), there is nothing to compare -> exit 0, always, even under --check.
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
#   --check          make drift a nonzero exit (CI gate). Without it, drift is
#                    informational only (exit 0).
#   --repo <dir>     repo root to check (default: $PWD). detect-stack is invoked
#                    against this dir and the manifest is read from
#                    <dir>/.project/library-manifest.md. Mirrors detect-stack.sh's
#                    [REPO_DIR] convention; lets the check point at a fixture dir.
#   -h|--help        print this header comment.
#
# Exit codes (per-failure-class, mirroring write-project-docs.sh):
#   0  ran cleanly — no drift; OR drift reported but --check was NOT passed; OR no
#      application stack detected ("nothing to compare"), always, even under
#      --check; OR the sole in-scope anchor is [TBD] (skipped).
#   1  usage / read error — bad flag, --repo not a directory, missing
#      `.project/library-manifest.md`, a detect-stack invocation failure, or
#      unparseable TSV output. ALWAYS nonzero regardless of --check.
#   2  drift detected AND --check was passed (the ONLY path where drift is nonzero).
#
# Run it:
#   ./scripts/check-project-docs.sh
#   ./scripts/check-project-docs.sh --check
#   ./scripts/check-project-docs.sh --repo /path/to/other/repo --check

set -euo pipefail

readonly ANCHOR='Runtime & frameworks'
readonly MANIFEST_REL='.project/library-manifest.md'
readonly TBD_TOKEN='[TBD]'

CHECK=0
REPO="$PWD"

# --- Inputs (long-option while/case loop, mirroring write-project-docs.sh) -----
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

MANIFEST="${REPO}/${MANIFEST_REL}"
readonly MANIFEST_LABEL="${MANIFEST_REL}#${ANCHOR}"

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

# First line MUST be the exact TSV header; otherwise the output is unparseable.
# Check the FULL literal header (the exact string detect-stack.sh always emits,
# detect-stack.sh:353) — stricter than a prefix match AND identical to the pwsh
# twin's check, so the two twins cannot diverge on header strictness. Use
# parameter expansion (not head) so a pipefail/SIGPIPE cannot mask a real result.
HEADER="${DETECT_OUT%%$'\n'*}"
EXPECTED_HEADER="$(printf 'stack\tsignal\tconvention\tmanifestPin\tdomainSkills\tflag\tversionFile')"
if [ "$HEADER" != "$EXPECTED_HEADER" ]; then
  echo "ERROR: detect-stack.sh output could not be parsed (missing TSV header) — the drift check could not run." >&2
  exit 1
fi

# --- Classify rows: application stacks vs meta/sentinel rows ------------------
# Field extraction uses awk (-F'\t'), NOT `IFS=$'\t' read`: tab is a whitespace-
# class IFS char, so `read` collapses consecutive tabs and strips trailing empty
# fields — which would shift the flag column out of alignment on the sentinel row
# (it has an empty domainSkills field and a trailing empty versionFile). awk keeps
# every field positional. It emits one `kind<TAB>stack` line per data row; both
# fields are always non-empty, so the downstream `read` is collapse-safe.
CLASSIFIED="$(printf '%s\n' "$DETECT_OUT" | awk -F'\t' '
  NR == 1 { next }                         # skip header
  $1 == "" { next }
  {
    if ($6 == "human" && ($1 == "none" || $1 == "(multi-stack)"))
      printf "sentinel\t%s\n", $1
    else
      printf "app\t%s\n", $1
  }
')"

APP_STACKS=()
SENTINEL_NOTES=()
while IFS=$'\t' read -r kind stack; do
  [ -z "$kind" ] && continue
  case "$kind" in
    sentinel) SENTINEL_NOTES+=("sentinel row — skipped: ${stack}") ;;
    app)      APP_STACKS+=("$stack") ;;
  esac
done <<< "$CLASSIFIED"

# --- No application stack at all: nothing to compare (exit 0, even under --check)
# app-empty implies the solely-`none` sentinel (a `(multi-stack)` sentinel only
# ever appears alongside real app rows), so this is the legitimate none outcome —
# NOT the error path, and never conflated with a missing/uncaptured manifest.
if [ "${#APP_STACKS[@]}" -eq 0 ]; then
  echo "no application stack detected — nothing to compare (${MANIFEST_LABEL})."
  exit 0
fi

# --- There are stacks to compare: the manifest anchor is now required ---------
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: ${MANIFEST_REL} not found — run apply first." >&2
  exit 1
fi
# Read the manifest ONCE, normalizing CRLF -> LF up front (mirroring
# write-project-docs.sh:194's `sed $'s/\r$//'` convention). A CRLF-terminated
# manifest would otherwise let the anchor-existence check pass (POSIX
# `[[:space:]]` swallows the trailing CR) while the extraction's `[ \t]*$` did
# NOT match the heading, silently yielding an empty section and false drift on
# every detected stack. BOTH the anchor match and the extraction run against this
# normalized content.
MANIFEST_CONTENT="$(sed $'s/\r$//' "$MANIFEST")"

# Extract the anchor's section body in a SINGLE pass (found-flag + capture,
# mirroring the pwsh twin's shape): every line after the `## <ANCHOR>` heading up
# to (excluding) the next `## ` heading. The heading pattern is built FROM $ANCHOR
# so the anchor name has exactly one source of truth (not a second hardcoded
# literal). Read-only awk over the normalized content.
# NOTE: this anchor-walk deliberately duplicates the "track current `## ` heading"
# algorithm in write-project-docs.sh. Extracting a shared read-doc-section.sh
# helper (which does not exist in this repo yet) would touch write-project-docs.sh
# — out of #129's file scope — so the duplication is a deliberate scope decision;
# that helper is the natural follow-up if a third caller ever needs the pattern.
set +e
SECTION="$(printf '%s\n' "$MANIFEST_CONTENT" | awk -v anchor="$ANCHOR" '
  BEGIN { hdr = "^## " anchor "[ \t]*$" }
  /^## / {
    if (ins) { exit 0 }
    if ($0 ~ hdr) { found = 1; ins = 1; next }
  }
  ins { print }
  END { if (!found) exit 1 }
')"
AWK_RC=$?
set -e
if [ "$AWK_RC" -ne 0 ]; then
  echo "ERROR: anchor '## ${ANCHOR}' not found in ${MANIFEST_REL} — the drift check could not run." >&2
  exit 1
fi

# Informational notes (e.g. a (multi-stack) sentinel alongside the real rows).
if [ "${#SENTINEL_NOTES[@]}" -gt 0 ]; then
  for n in "${SENTINEL_NOTES[@]}"; do echo "$n"; done
fi

# --- [TBD] (never captured): skip the anchor entirely -------------------------
# The only in-scope anchor is uncaptured, so there is nothing to compare -> no
# drift (exit 0, even under --check). Neither drift nor no-drift; listed as such.
case "$SECTION" in
  *"$TBD_TOKEN"*)
    echo "skipped — ${MANIFEST_LABEL} not yet captured (${TBD_TOKEN}); nothing to compare."
    exit 0 ;;
esac

# --- Presence check: each detected stack's identifying name in the content ----
SECTION_LC="$(printf '%s' "$SECTION" | tr '[:upper:]' '[:lower:]')"
# One-line snippet for the drift report ("checked against").
SNIPPET="$(printf '%s' "$SECTION" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
if [ "${#SNIPPET}" -gt 140 ]; then SNIPPET="${SNIPPET:0:137}..."; fi

DRIFT_LINES=()
for stack in "${APP_STACKS[@]}"; do
  # Select the FRAMEWORK-SPECIFIC identifying source for this stack, structurally
  # (parse the `(...)` group), NOT by a hand-maintained word stoplist:
  #   - a `(...)` qualifier that names a real framework IS the identifying source
  #     (`Ruby (Rails)` -> Rails; `Python (FastAPI)` -> FastAPI);
  #   - a generic/placeholder qualifier (`generic`, `non...`, `[TBD]`, or the bare
  #     runtime `Node`) means the framework is in the BASE, so fall back to it
  #     (`React (Node)` -> React; `Node (generic)` -> Node; `.NET (non-MAUI)` ->
  #     .NET; `Node ([TBD])` -> Node);
  #   - no `(...)` at all -> the whole name is the source (`.NET MAUI` -> .NET
  #     MAUI; `Rust` -> Rust; `Claude Code plugin` -> that phrase).
  # This makes `React (Node)` require `React` (not be satisfied by a bare `Node`)
  # — the issue's worked example — and keeps both twins selecting identical tokens.
  case "$stack" in
    *"("*)
      base="${stack%%(*}"
      qual="${stack#*(}"; qual="${qual%%)*}"
      base="${base#"${base%%[![:space:]]*}"}"; base="${base%"${base##*[![:space:]]}"}"
      qual="${qual#"${qual%%[![:space:]]*}"}"; qual="${qual%"${qual##*[![:space:]]}"}"
      qual_lc="$(printf '%s' "$qual" | tr '[:upper:]' '[:lower:]')"
      case "$qual_lc" in
        generic|node) id_src="$base" ;;   # generic qualifier / bare runtime
        non*)         id_src="$base" ;;   # negation qualifier, e.g. non-MAUI
        *tbd*)        id_src="$base" ;;    # unresolved-framework placeholder
        *)            id_src="$qual" ;;    # a real framework name
      esac
      ;;
    *)
      id_src="$stack"
      ;;
  esac
  # Tokenize the identifying source: replace every non-[alnum . + #] byte with a
  # space, split on whitespace. Present if ANY token is a case-insensitive
  # substring of the captured content (per the issue's locked substring match).
  toks="$(printf '%s' "$id_src" | tr -c 'A-Za-z0-9.+#' ' ')"
  present=0
  for tok in $toks; do
    tok_lc="$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')"
    case "$tok_lc" in
      *[a-z0-9]*) ;;                    # must carry at least one alnum char
      *) continue ;;
    esac
    case "$SECTION_LC" in
      *"$tok_lc"*) present=1; break ;;
    esac
  done
  if [ "$present" -eq 0 ]; then
    DRIFT_LINES+=("DRIFT — ${MANIFEST_LABEL} does not mention detected stack '${stack}' (checked against: \"${SNIPPET}\")")
  fi
done

# --- Report + exit ------------------------------------------------------------
if [ "${#DRIFT_LINES[@]}" -eq 0 ]; then
  echo "no drift — every detected stack is recorded in ${MANIFEST_LABEL}."
  exit 0
fi

for l in "${DRIFT_LINES[@]}"; do echo "$l"; done
echo "drift: ${#DRIFT_LINES[@]} detected stack(s) not found in ${MANIFEST_LABEL}."
if [ "$CHECK" -eq 1 ]; then
  exit 2
fi
echo "(informational only — re-run with --check to make drift a CI failure.)"
exit 0
