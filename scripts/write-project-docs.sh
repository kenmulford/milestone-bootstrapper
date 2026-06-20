#!/usr/bin/env bash
#
# write-project-docs.sh — place resolved interview/detection content into a
# `.project/` doc template by replacing the `[TBD]` placeholder UNDER each stable
# `##` anchor. The deterministic placement primitive for Job 1 (project-docs
# population).
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
# docs/understanding-interview.md §2 and SPEC.md §5/§6. The caller is responsible
# for keying the input map by the correct anchor; this writer only verifies the
# anchor EXISTS in the template (and errors loudly if it does not — a renamed or
# missing heading is never silently skipped).
#
# Recording discipline (docs/understanding-interview.md §3, SPEC.md §4.3) — the
# three states are kept distinct and NEVER collapsed:
#   - captured : the caller supplied a real answer  -> replace the placeholder.
#   - none     : the caller recorded "None" / "not applicable" — a real, deliberate
#                answer that the thing does not exist -> replace the placeholder
#                with that answer (NO 🔴). "None" is captured, not unknown.
#   - tbd      : a genuine unknown the interview could not resolve -> LEAVE the
#                [TBD] placeholder in place and flag it 🔴. Never fabricate a value.
#   An anchor present in the template but NOT named by any input entry is left
#   untouched (still [TBD]) — partial population is legitimate; the template's own
#   header comment already documents that an untouched [TBD] reads as "not
#   specified". Only an input anchor MISSING from the template is an error.
#
# What it NEVER does (append-only anchor discipline, §3.1):
#   - never renames, rewords, or reorders a `##` heading (citation anchors);
#   - never invents a new heading;
#   - never touches the `[TBD]` tokens inside the leading <!-- ... --> header
#     comment (those sit BEFORE the first `##` heading, so they are never under a
#     current anchor and are structurally out of reach).
#
# Inputs:
#   --template <file>   path to the `.project/` doc template to populate (the file
#                       is edited in place). REQUIRED.
#   --map <file>        path to a JSON map keyed by exact `##` anchor heading text
#                       (WITHOUT the leading "## "). Each value is an object:
#                         { "state": "captured"|"none"|"tbd", "content": "<text>" }
#                       `content` may be multi-line (a full table body or bullet
#                       list); it replaces the WHOLE contiguous `[TBD]` placeholder
#                       block under that anchor. For state "tbd", `content` is
#                       ignored and the placeholder is left in place + flagged.
#                       REQUIRED (mutually exclusive with the single-anchor flags).
#   --anchor <text>     single-anchor mode: the exact `##` heading text (no "## ").
#   --state <s>         single-anchor mode: captured | none | tbd (default captured).
#   --content <text>    single-anchor mode: the replacement content.
#   --repo <dir>        unused placeholder for suite-flag parity; ignored.
#   Env fallbacks (args win): PROJECT_DOCS_TEMPLATE, PROJECT_DOCS_MAP.
#
# Behavior:
#   - Idempotent: re-running with the same map yields a byte-identical file (a
#     captured/none anchor whose placeholder is already replaced is a no-op for
#     that anchor — there is no [TBD] block left to match, which is reported, not
#     an error). A pure no-op run leaves the file untouched.
#   - Atomic: writes via a temp file; a failure never leaves a partial doc.
#   - BOM-free UTF-8 output (printf, never echo/`>` redirection quirks).
#
# Exit codes:
#   0  file populated (or already up to date — true no-op).
#   1  bad input / usage (missing flag, unreadable file, malformed map JSON).
#   2  write / serialize failure (unwritable path, temp-file failure).
#   3  unmatched anchor — an input anchor is NOT a `##` heading in the template
#      (a renamed/missing heading). Loud failure, never a silent skip. The file is
#      left UNCHANGED.
#
# Run it:
#   ./scripts/write-project-docs.sh --template .project/environment.md --map caps.json
#   ./scripts/write-project-docs.sh --template .project/environment.md \
#       --anchor "Caching" --state none --content "None — no cache layer."

set -euo pipefail

readonly FLAG='🔴'          # suite output-style human-attention marker
readonly TBD_TOKEN='[TBD]'

# --- Inputs (args override env) -----------------------------------------------
TEMPLATE="${PROJECT_DOCS_TEMPLATE:-}"
MAP_FILE="${PROJECT_DOCS_MAP:-}"
SINGLE_ANCHOR=""
SINGLE_STATE="captured"
SINGLE_CONTENT=""
HAVE_SINGLE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --template) TEMPLATE="${2:?--template needs a value}"; shift 2 ;;
    --map)      MAP_FILE="${2:?--map needs a value}"; shift 2 ;;
    --anchor)   SINGLE_ANCHOR="${2:?--anchor needs a value}"; HAVE_SINGLE=1; shift 2 ;;
    --state)    SINGLE_STATE="${2:?--state needs a value}"; HAVE_SINGLE=1; shift 2 ;;
    --content)  SINGLE_CONTENT="${2:?--content needs a value}"; HAVE_SINGLE=1; shift 2 ;;
    --repo)     shift 2 ;;   # accepted for suite-flag parity; unused
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1 ;;
  esac
done

# --- Validate inputs ----------------------------------------------------------
if [ -z "$TEMPLATE" ]; then
  echo "ERROR: --template is required." >&2
  exit 1
fi
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found or not a file: ${TEMPLATE}" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found on PATH." >&2; exit 2; }

# Single-anchor mode builds a one-entry map; otherwise --map is required. The two
# modes are mutually exclusive so the input is never ambiguous.
if [ "$HAVE_SINGLE" -eq 1 ] && [ -n "$MAP_FILE" ]; then
  echo "ERROR: use either --map OR the single-anchor flags (--anchor/--state/--content), not both." >&2
  exit 1
fi

if [ "$HAVE_SINGLE" -eq 1 ]; then
  if [ -z "$SINGLE_ANCHOR" ]; then
    echo "ERROR: single-anchor mode needs --anchor." >&2
    exit 1
  fi
  case "$SINGLE_STATE" in
    captured|none|tbd) ;;
    *) echo "ERROR: --state must be captured | none | tbd (got: ${SINGLE_STATE})." >&2; exit 1 ;;
  esac
  if ! MAP_JSON="$(jq -n \
        --arg a "$SINGLE_ANCHOR" --arg s "$SINGLE_STATE" --arg c "$SINGLE_CONTENT" \
        '{ ($a): { state: $s, content: $c } }' 2>&1)"; then
    echo "ERROR: failed to assemble single-anchor map: ${MAP_JSON}" >&2
    exit 1
  fi
else
  if [ -z "$MAP_FILE" ]; then
    echo "ERROR: provide --map <file> or the single-anchor flags." >&2
    exit 1
  fi
  if [ ! -f "$MAP_FILE" ]; then
    echo "ERROR: map file not found or not a file: ${MAP_FILE}" >&2
    exit 1
  fi
  if ! MAP_JSON="$(jq -e '.' "$MAP_FILE" 2>&1)"; then
    echo "ERROR: --map is not valid JSON: ${MAP_FILE}" >&2
    exit 1
  fi
fi

# Validate every map entry: object with a valid state.
if ! VALIDATION="$(printf '%s' "$MAP_JSON" | jq -r '
      to_entries[]
      | .key as $k
      | (.value | type) as $t
      | if $t != "object" then "BADSHAPE\t\($k)"
        elif (.value.state // "captured") as $s
             | ($s == "captured" or $s == "none" or $s == "tbd") | not
          then "BADSTATE\t\($k)\t\(.value.state)"
        else empty end
    ' 2>&1)"; then
  echo "ERROR: failed to validate map: ${VALIDATION}" >&2
  exit 1
fi
if [ -n "$VALIDATION" ]; then
  while IFS=$'\t' read -r kind anchor extra; do
    case "$kind" in
      BADSHAPE) echo "ERROR: map entry for anchor '${anchor}' must be an object { state, content }." >&2 ;;
      BADSTATE) echo "ERROR: map entry for anchor '${anchor}' has invalid state '${extra}' (want captured|none|tbd)." >&2 ;;
    esac
  done <<< "$VALIDATION"
  exit 1
fi

# --- Read + normalize the template once (CRLF -> LF) ---------------------------
# A CRLF-line-ended template must populate identically to an LF one (cross-platform
# parity with the pwsh twin, which normalizes `\r\n` -> `\n`). `sed 's/\r$//'`
# strips a CR only where it precedes the LF sed splits on — i.e. exactly the
# `\r\n` pairs — leaving any lone `\r` untouched, matching the pwsh `-replace`.
# Command substitution then strips ALL trailing newlines; the final write re-adds
# exactly one, so a template ending in `\n\n\n` collapses to a single trailing `\n`
# (this is the long-standing bash behavior; the pwsh twin is matched to it). Every
# downstream read of the template uses this normalized value, never the raw file.
TEMPLATE_CONTENT="$(sed $'s/\r$//' "$TEMPLATE")"

# --- Pre-flight: every input anchor MUST be a `##` heading in the template ------
# Collect the template's `##` heading texts (the anchor names, sans "## ") and
# diff the input anchors against them. An input anchor with no matching heading is
# an unmatched-anchor error (exit 3) — the file is left UNCHANGED.
TEMPLATE_ANCHORS="$(printf '%s\n' "$TEMPLATE_CONTENT" | grep -E '^## ' | sed -E 's/^## //' || true)"

MISSING=""
while IFS= read -r want; do
  [ -z "$want" ] && continue
  if ! printf '%s\n' "$TEMPLATE_ANCHORS" | grep -qxF "$want"; then
    MISSING="${MISSING}${want}"$'\n'
  fi
done < <(printf '%s' "$MAP_JSON" | jq -r 'keys_unsorted[]')

if [ -n "$MISSING" ]; then
  echo "ERROR: unmatched anchor(s) — not a '## ' heading in ${TEMPLATE}:" >&2
  printf '%s' "$MISSING" | while IFS= read -r m; do [ -n "$m" ] && echo "  - ${m}" >&2; done
  echo "  (a renamed/missing heading breaks citations; the template was NOT modified.)" >&2
  exit 3
fi

# --- Place content under each anchor, one anchor per pass ----------------------
# Each anchor is placed by its OWN awk pass over the working copy. Per pass, awk
# needs only ASCII scalars via -v (anchor, state, the [TBD] token, the 🔴 marker)
# plus the replacement content, which is read from a per-anchor temp FILE in
# BEGIN as a single opaque value — so multi-line markdown (tables, bullet lists)
# never has to survive shell quoting or a field-separator encoding. Looping one
# anchor at a time keeps the per-pass data trivially simple and order-independent.
#
# The pass walks the file tracking the current `## ` heading. Within the target
# anchor's section, the FIRST contiguous run of [TBD]-bearing lines is the
# placeholder block:
#   - captured / none : replace the whole block with the content (once).
#   - tbd             : keep each placeholder line, append the 🔴 marker.
# Lines in the leading <!-- --> comment precede the first heading, so they are
# never under a current anchor and are never touched.
#
# awk runs under LC_ALL=C (byte mode): the 🔴 marker and template glyphs (→ — “”)
# are multibyte UTF-8 and some awk builds abort classifying them in a UTF-8
# locale; byte mode copies them through untouched, and the logic only does
# index()/substr() on ASCII markers, so byte semantics are exactly correct.

WORKING="$TEMPLATE_CONTENT"

CONTENT_FILE="$(mktemp "${TMPDIR:-/tmp}/.write-project-docs-content.XXXXXX" 2>/dev/null)" || {
  echo "ERROR: cannot create a temp file for placement." >&2
  exit 2
}
trap 'rm -f "$CONTENT_FILE"' EXIT

while IFS= read -r anchor; do
  [ -z "$anchor" ] && continue
  state="$(printf '%s' "$MAP_JSON" | jq -r --arg a "$anchor" '.[$a].state // "captured"')"
  # Write this anchor's content to the temp file (empty for tbd; unused there).
  printf '%s' "$MAP_JSON" | jq -j --arg a "$anchor" '.[$a].content // ""' > "$CONTENT_FILE"

  WORKING="$(
    printf '%s\n' "$WORKING" | LC_ALL=C awk \
      -v anchor="$anchor" -v state="$state" -v tbd="$TBD_TOKEN" \
      -v flag="$FLAG" -v contentfile="$CONTENT_FILE" '
      BEGIN {
        # Load the replacement content as one opaque string, preserving its own
        # internal newlines. nread guards the first line so an empty first line
        # does not get a spurious leading newline.
        content = ""
        nread = 0
        while ((getline ln < contentfile) > 0) {
          content = (nread == 0) ? ln : content "\n" ln
          nread++
        }
        close(contentfile)
        cur = ""
        inblock = 0
        done = 0       # the target placeholder block has been consumed
      }
      {
        line = $0
        if (line ~ /^## /) { cur = substr(line, 4); inblock = 0; print line; next }
        if (cur == anchor && done == 0) {
          if (index(line, tbd) > 0) {
            if (inblock == 0) {
              inblock = 1
              if (state == "tbd") {
                if (index(line, flag) == 0) print line " " flag; else print line
              } else {
                printf "%s\n", content
              }
            } else {
              if (state == "tbd") {
                if (index(line, flag) == 0) print line " " flag; else print line
              }
              # captured/none: drop extra placeholder lines (already replaced).
            }
            next
          } else {
            if (inblock == 1) { inblock = 0; done = 1 }
            print line
            next
          }
        }
        print line
      }
    '
  )" || { echo "ERROR: placement pass failed for anchor '${anchor}' in ${TEMPLATE}." >&2; exit 2; }
done < <(printf '%s' "$MAP_JSON" | jq -r 'keys_unsorted[]')

rm -f "$CONTENT_FILE"
trap - EXIT

# --- Idempotent no-op: identical content is left byte-identical ----------------
# Compare against the normalized template content (CRLF/trailing-newline already
# folded), not the raw file — so a no-change run leaves the file untouched even if
# the only "difference" would have been line endings or extra trailing blank lines.
if [ "$TEMPLATE_CONTENT" = "$WORKING" ]; then
  echo "${TEMPLATE} already up to date (no change)."
  exit 0
fi

# --- Atomic write -------------------------------------------------------------
DEST_DIR="$(dirname "$TEMPLATE")"
TMP_FILE="$(mktemp "${DEST_DIR}/.write-project-docs.XXXXXX" 2>/dev/null)" || {
  echo "ERROR: cannot write to: ${DEST_DIR} (path not writable)." >&2
  exit 2
}
trap 'rm -f "$TMP_FILE"' EXIT

if ! printf '%s\n' "$WORKING" > "$TMP_FILE" 2>/dev/null; then
  echo "ERROR: failed to write populated doc to: ${DEST_DIR}" >&2
  exit 2
fi

if ! mv "$TMP_FILE" "$TEMPLATE" 2>/dev/null; then
  echo "ERROR: failed to move populated doc into place: ${TEMPLATE}" >&2
  exit 2
fi
trap - EXIT

echo "${TEMPLATE} populated."
exit 0
