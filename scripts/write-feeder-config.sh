#!/usr/bin/env bash
#
# write-feeder-config.sh — write the target repo's `.milestone-config/feeder.json`
# config slice (the feeder-owned keys: `projectDocs`, `versioning`).
#
# What this does, in plain terms:
#   The bootstrapper's `apply` skill (#13) leaves the TARGET repo with the correct
#   feeder-config SIGNAL — a present, non-empty `feeder.json` when any key diverges
#   from its default, or NO `feeder.json` at all when every key is at its default —
#   so `milestone-feeder`'s first-run `setup` runs exactly when it should (it
#   auto-invokes on an ABSENT file). `apply` is non-interactive, so this is a
#   deterministic, reusable writer it calls — NOT the interactive
#   `milestone-feeder:setup` interview (that path is interview-only, with no
#   non-interactive entry, so it cannot run unattended). Recorded decision: issue
#   #5 "✅ Design decision — Option A". For the non-default case this writer
#   produces the identical file `setup`'s Phase 3 would, to the same schema and the
#   same absent-means-default discipline; when every key is at its default the
#   assembled object is `{}` and the file is deliberately left ABSENT rather than
#   emitted as `{}` (issue #77) — see Behavior below.
#
# Authoritative schema (DRIFT GUARDRAIL — do not widen without updating both):
#   The feeder-owned key set and the absent-means-default discipline are defined
#   by the canonical schema doc:
#     milestone-feeder/docs/profile-schema.md
#       - "Own keys" table          -> projectDocs (default ".project/"),
#                                       versioning  ("semver"|"none"; NO bundled
#                                                    default — absent = infer-or-ask;
#                                                    profile-schema.md:52,115-133)
#       - "Absent-means-default discipline" -> omit a key left at its BUNDLED
#                                       default; an empty `{}` remains a valid
#                                       profile to READ, but this writer no longer
#                                       EMITS it — an all-default slice is left
#                                       ABSENT (issue #77, see Behavior).
#   This slice writes the feeder-OWNED keys `projectDocs` and `versioning`. The
#   two `versioning` keys are DISTINCT: this writes
#   `feeder.json#versioning` — the feeder's own STRING enum "semver"|"none" (its
#   read-contract key, profile-schema.md:52), which is NOT the driver's BOOLEAN
#   `driver.json#versioning` (owned by the driver-config slice #8, ever only
#   written as `false`). A single Tier-6 answer maps to BOTH keys (dual-write):
#   versioned => driver OMITS / feeder "semver"; non-versioned => driver `false` /
#   feeder "none"; skipped/[TBD] => BOTH omit. This slice deliberately does NOT
#   write the shared/driver keys (uiSurfaceGlobs, integrationBranch, the consumer's
#   sourceGlobs, domainSkills, nonNegotiables, and the driver's BOOLEAN versioning)
#   — those are read from the driver config and owned by the driver-config slice
#   (#8). The feeder retired its `reviewer` own-key, so this writer no longer emits
#   it. If the feeder's schema gains or renames an own-key, update this script in
#   lockstep.
#
# Inputs (resolved values — this writer does NOT re-derive them):
#   --repo <dir>          target repo root (default: current directory)
#   --project-docs <str>  the resolved `.project/` path from Job 1
#                         (default ".project/"; omitted from the file when equal
#                          to the bundled default)
#   --versioning <val>    "semver" | "none" — the Tier-6 versioning policy as the
#                         feeder's STRING enum. Three-way UNSET-sentinel (NOT the
#                         omit-when-equals-default rule `--project-docs` uses,
#                         because feeder#versioning has NO bundled default):
#                         "semver" => emit "versioning":"semver"; "none" => emit
#                         "versioning":"none"; UNSET/not-passed => OMIT the key
#                         entirely (never a placeholder — absent = infer-or-ask).
#                         Any other value is bad input (exit 1).
#   Env fallbacks (args win): FEEDER_PROJECT_DOCS, FEEDER_VERSIONING, FEEDER_REPO.
#
# Behavior:
#   - Writes the file ONLY when the assembled config DIVERGES from the bundled
#     defaults. When every key is at its default the assembled object is `{}` and
#     the file is deliberately left ABSENT rather than emitted as `{}`, so
#     milestone-feeder's absent-only first-run `setup` trigger fires (issue #77).
#     Non-destructive: an all-default run never writes AND never deletes an
#     existing file.
#   - Idempotent / non-destructive: when the assembled object is byte-identical
#     to an existing file's content, the file is left untouched (true no-op);
#     re-runs never duplicate. (Key-level diff+patch of human edits is the
#     future `update` skill's job, not this primitive writer's.)
#   - Errors (unwritable path, jq failure) surface a clear message on stderr and
#     exit non-zero — never leaving a partially-written / invalid file in place.
#
# Run it:  ./scripts/write-feeder-config.sh --repo /path/to/target [--project-docs ...] [--versioning ...]
# Exit 0 = feeder.json is present-and-correct OR deliberately left absent (all keys at default).
# Exit 1 = bad input. Exit 2 = write/serialize failure.

set -euo pipefail

# --- jq output normalization (Windows text-mode stdout) ------------------------
# A native-Windows jq opens stdout in TEXT mode, so every `\n` it writes becomes
# `\r\n` and any jq value the shell consumes as TEXT carries a stray `\r`. Cause,
# mechanism, and the `s/\r$//` rationale are documented once in the canonical
# block at scripts/write-project-docs.sh:87-121 — not restated here.
# Exactly ONE stream here needs it: NEW_CONTENT, the serialized feeder.json. It is
# never re-parsed as JSON in-script — it is consumed as TEXT, and whenever the
# assembled object is MULTI-line the usual msys accident does not save it:
# `$(...)` strips only the TRAILING newline, so every interior CR survives. That
# case is LIVE, not latent (measured on jq-1.8.1: 3 CR bytes in the emitted
# feeder.json). It costs:
#   - the write itself. `printf '%s\n' "$NEW_CONTENT" > "$TMP_FILE"` persists CRLF
#     into feeder.json, breaking the byte-identical-with-the-.ps1-twin contract
#     these writers maintain (the twin uses ConvertTo-Json and emits LF).
#   - the idempotency compare `[ "$(cat "$CONFIG_FILE")" = "$NEW_CONTENT" ]`
#     whenever the on-disk file is LF — one written by the .ps1 twin, by a POSIX
#     run, or checked out by git. `cat` yields LF, the CRLF NEW_CONTENT never
#     matches, and the script rewrites an already-correct file as CRLF.
#   - the trailing `echo "$NEW_CONTENT"` display.
# LATENT, and folded by the same seam: the empty-object guard
# `[ "$NEW_CONTENT" = "{}" ]` (issue #77). `{}` is SINGLE-line, and on the msys
# toolchain this script was developed against `$(...)` strips a trailing CRLF
# WHOLE, so the guard fires correctly today (measured). That is a TOOLCHAIN
# behavior, not a guarantee. If a CR ever did survive, an all-default run would
# WRITE `{}` instead of leaving the file absent — defeating milestone-feeder's
# absent-only first-run `setup` trigger, the exact regression #77 exists to
# prevent, and doing it silently: exit 0, success message, wrong outcome.
# On a POSIX jq (LF stdout) the seam is a no-op, so applying it unconditionally
# is safe.
#
# EXEMPT — do NOT "fix" the `command -v jq` presence check below.
#
# `set -o pipefail` is in force above, so making the NEW_CONTENT capture a
# PIPELINE does not swallow a jq failure: jq's non-zero status still propagates
# to the `if !` error branch. Same shape as write-project-docs.sh:211.
strip_cr() { sed $'s/\r$//'; }

# --- Bundled defaults (mirror milestone-feeder/docs/profile-schema.md) ---------
readonly DEFAULT_PROJECT_DOCS=".project/"

# --- Inputs (args override env; env overrides default) -------------------------
REPO="${FEEDER_REPO:-.}"
PROJECT_DOCS="${FEEDER_PROJECT_DOCS:-$DEFAULT_PROJECT_DOCS}"
VERSIONING="${FEEDER_VERSIONING:-}"

# UNSET sentinel so an unpassed --versioning is OMITTED (three-way) — distinct from
# a passed value — because feeder#versioning has NO bundled default (absent =
# infer-or-ask). Mirrors the UNSET-sentinel pattern write-driver-config.sh:146-156
# uses for its own optional keys. versioning is the ONLY feeder own-key with no
# default, so it is the only key here that needs the sentinel (projectDocs uses
# omit-when-equals-bundled-default instead).
UNSET=$'\x00UNSET\x00'
[ -n "${FEEDER_VERSIONING+x}" ] || VERSIONING="$UNSET"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)          REPO="${2:?--repo needs a value}"; shift 2 ;;
    --project-docs)  PROJECT_DOCS="${2:?--project-docs needs a value}"; shift 2 ;;
    --versioning)    VERSIONING="${2:?--versioning needs a value}"; shift 2 ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1 ;;
  esac
done

# --- Validate versioning against the feeder schema's enum (UNSET => omit) -------
# Only "semver"|"none" are valid (profile-schema.md:52); any other PASSED value is
# bad input. UNSET (not passed) is valid and means OMIT (absent = infer-or-ask).
# Mirrors write-driver-config.sh:221-229.
if [ "$VERSIONING" != "$UNSET" ]; then
  case "$VERSIONING" in
    "semver"|"none") ;;
    *)
      echo "ERROR: --versioning must be \"semver\" or \"none\" (got: ${VERSIONING})." >&2
      exit 1 ;;
  esac
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found on PATH." >&2; exit 2; }

# --- Assemble the minimal object (absent-means-default: omit bundled defaults) --
# Start from {} and add only keys whose resolved value DIVERGES from the bundled
# default. Build the jq filter incrementally so an all-default run yields `{}`
# (which is then NOT written — see the empty-object guard below, issue #77).
filter='.'
args=()
if [ "$PROJECT_DOCS" != "$DEFAULT_PROJECT_DOCS" ]; then
  filter="${filter} | .projectDocs = \$projectDocs"
  args+=(--arg projectDocs "$PROJECT_DOCS")
fi
if [ "$VERSIONING" != "$UNSET" ]; then
  # feeder#versioning is a three-way UNSET-sentinel key (no bundled default): emit
  # the resolved string enum, or OMIT when unset. Adding it makes the assembled
  # object non-empty, so the empty-object guard below (issue #77) correctly WRITES
  # the file; an all-default run with no versioning still assembles `{}` and stays
  # ABSENT (unchanged #77 behavior).
  filter="${filter} | .versioning = \$versioning"
  args+=(--arg versioning "$VERSIONING")
fi

if ! NEW_CONTENT="$(jq -n "${args[@]}" "{} | ${filter}" 2>&1 | strip_cr)"; then
  echo "ERROR: failed to serialize feeder.json: ${NEW_CONTENT}" >&2
  exit 2
fi

# --- Resolve the destination path ---------------------------------------------
CONFIG_DIR="${REPO%/}/.milestone-config"
CONFIG_FILE="${CONFIG_DIR}/feeder.json"

# --- Never emit an empty {} — leave feeder.json ABSENT (issue #77) --------------
# When every feeder key is at its bundled default the assembled object is `{}`.
# Emitting that as a present file would DEFEAT milestone-feeder's absent-only
# first-run `setup` trigger (its `plan` auto-invokes setup only when feeder.json
# is ABSENT). So leave the file absent rather than writing `{}`. Non-destructive:
# an all-default run never writes AND never deletes an existing file here
# (stale-`{}` remediation of already-bootstrapped repos is a separate,
# out-of-scope concern — issue #77).
if [ "$NEW_CONTENT" = "{}" ]; then
  echo "All feeder keys at bundled defaults — leaving ${CONFIG_FILE} absent so milestone-feeder's first-run setup fires."
  exit 0
fi

# Guard: if the config path is an existing DIRECTORY, a later `mv` would silently
# move the temp file INTO it (feeder.json/<tmp>) and falsely report success — the
# real file would never be written. Refuse up front with a clear message.
if [ -d "$CONFIG_FILE" ]; then
  echo "ERROR: cannot write feeder.json: ${CONFIG_FILE} exists and is a directory." >&2
  exit 2
fi

# --- Idempotent no-op: identical existing content is left byte-identical --------
if [ -f "$CONFIG_FILE" ] && [ "$(cat "$CONFIG_FILE")" = "$NEW_CONTENT" ]; then
  echo "${CONFIG_FILE} already up to date (no change)."
  exit 0
fi

# --- Write (create .milestone-config/ if absent) -------------------------------
if ! mkdir -p "$CONFIG_DIR" 2>/dev/null; then
  echo "ERROR: cannot create directory: ${CONFIG_DIR}" >&2
  exit 2
fi

# Write atomically via a temp file so a failure never leaves a partial/invalid
# feeder.json in place. printf (not echo) for portable, BOM-free UTF-8 output.
TMP_FILE="$(mktemp "${CONFIG_DIR}/.feeder.json.XXXXXX" 2>/dev/null)" || {
  echo "ERROR: cannot write to: ${CONFIG_DIR} (path not writable)." >&2
  exit 2
}
trap 'rm -f "$TMP_FILE"' EXIT

if ! printf '%s\n' "$NEW_CONTENT" > "$TMP_FILE" 2>/dev/null; then
  echo "ERROR: failed to write feeder.json to: ${CONFIG_DIR}" >&2
  exit 2
fi

if ! mv "$TMP_FILE" "$CONFIG_FILE" 2>/dev/null; then
  echo "ERROR: failed to write feeder.json to: ${CONFIG_DIR}" >&2
  exit 2
fi
trap - EXIT

echo "${CONFIG_FILE} written."
echo "$NEW_CONTENT"
exit 0
