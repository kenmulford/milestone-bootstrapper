#!/usr/bin/env bash
#
# write-feeder-config.sh — write the target repo's `.milestone-config/feeder.json`
# config slice (the feeder-owned keys: `projectDocs`, `reviewer`, `versioning`).
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
#                                       reviewer    (default "milestone-driver"),
#                                       versioning  ("semver"|"none"; NO bundled
#                                                    default — absent = infer-or-ask;
#                                                    profile-schema.md:52,115-133)
#       - "Absent-means-default discipline" -> omit a key left at its BUNDLED
#                                       default; an empty `{}` remains a valid
#                                       profile to READ, but this writer no longer
#                                       EMITS it — an all-default slice is left
#                                       ABSENT (issue #77, see Behavior).
#   This slice writes the feeder-OWNED keys `projectDocs`, `reviewer`, and
#   `versioning`. The two `versioning` keys are DISTINCT: this writes
#   `feeder.json#versioning` — the feeder's own STRING enum "semver"|"none" (its
#   read-contract key, profile-schema.md:52), which is NOT the driver's BOOLEAN
#   `driver.json#versioning` (owned by the driver-config slice #8, ever only
#   written as `false`). A single Tier-6 answer maps to BOTH keys (dual-write):
#   versioned => driver OMITS / feeder "semver"; non-versioned => driver `false` /
#   feeder "none"; skipped/[TBD] => BOTH omit. This slice deliberately does NOT
#   write the shared/driver keys (uiSurfaceGlobs, integrationBranch, the consumer's
#   sourceGlobs, domainSkills, nonNegotiables, and the driver's BOOLEAN versioning)
#   — those are read from the driver config and owned by the driver-config slice
#   (#8). If the feeder's schema gains or renames an own-key, update this script in
#   lockstep.
#
# Inputs (resolved values — this writer does NOT re-derive them):
#   --repo <dir>          target repo root (default: current directory)
#   --project-docs <str>  the resolved `.project/` path from Job 1
#                         (default ".project/"; omitted from the file when equal
#                          to the bundled default)
#   --reviewer <val>      "milestone-driver" | "internal" | false
#                         (default "milestone-driver"; omitted when equal to the
#                          bundled default — the omit test is against the BUNDLED
#                          default, not the detected value, so a resolved
#                          "internal" IS written)
#   --versioning <val>    "semver" | "none" — the Tier-6 versioning policy as the
#                         feeder's STRING enum. Three-way UNSET-sentinel (NOT the
#                         omit-when-equals-default rule the two keys above use,
#                         because feeder#versioning has NO bundled default):
#                         "semver" => emit "versioning":"semver"; "none" => emit
#                         "versioning":"none"; UNSET/not-passed => OMIT the key
#                         entirely (never a placeholder — absent = infer-or-ask).
#                         Any other value is bad input (exit 1).
#   Env fallbacks (args win): FEEDER_PROJECT_DOCS, FEEDER_REVIEWER,
#                             FEEDER_VERSIONING, FEEDER_REPO.
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
# Run it:  ./scripts/write-feeder-config.sh --repo /path/to/target [--project-docs ...] [--reviewer ...] [--versioning ...]
# Exit 0 = feeder.json is present-and-correct OR deliberately left absent (all keys at default).
# Exit 1 = bad input. Exit 2 = write/serialize failure.

set -euo pipefail

# --- Bundled defaults (mirror milestone-feeder/docs/profile-schema.md) ---------
readonly DEFAULT_PROJECT_DOCS=".project/"
readonly DEFAULT_REVIEWER="milestone-driver"

# --- Inputs (args override env; env overrides default) -------------------------
REPO="${FEEDER_REPO:-.}"
PROJECT_DOCS="${FEEDER_PROJECT_DOCS:-$DEFAULT_PROJECT_DOCS}"
REVIEWER="${FEEDER_REVIEWER:-$DEFAULT_REVIEWER}"
VERSIONING="${FEEDER_VERSIONING:-}"

# UNSET sentinel so an unpassed --versioning is OMITTED (three-way) — distinct from
# a passed value — because feeder#versioning has NO bundled default (absent =
# infer-or-ask). Mirrors the UNSET-sentinel pattern write-driver-config.sh:146-156
# uses for its own optional keys. versioning is the ONLY feeder own-key with no
# default, so it is the only key here that needs the sentinel (projectDocs/reviewer
# use omit-when-equals-bundled-default instead).
UNSET=$'\x00UNSET\x00'
[ -n "${FEEDER_VERSIONING+x}" ] || VERSIONING="$UNSET"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)          REPO="${2:?--repo needs a value}"; shift 2 ;;
    --project-docs)  PROJECT_DOCS="${2:?--project-docs needs a value}"; shift 2 ;;
    --reviewer)      REVIEWER="${2:?--reviewer needs a value}"; shift 2 ;;
    --versioning)    VERSIONING="${2:?--versioning needs a value}"; shift 2 ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1 ;;
  esac
done

# --- Validate reviewer against the schema's enum -------------------------------
case "$REVIEWER" in
  "milestone-driver"|"internal"|false) ;;
  *)
    echo "ERROR: --reviewer must be \"milestone-driver\", \"internal\", or false (got: ${REVIEWER})." >&2
    exit 1 ;;
esac

# --- Validate versioning against the feeder schema's enum (UNSET => omit) -------
# Only "semver"|"none" are valid (profile-schema.md:52); any other PASSED value is
# bad input. UNSET (not passed) is valid and means OMIT (absent = infer-or-ask).
# Mirrors the --reviewer enum block above and write-driver-config.sh:221-229.
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
if [ "$REVIEWER" != "$DEFAULT_REVIEWER" ]; then
  if [ "$REVIEWER" = "false" ]; then
    # reviewer is the only key whose non-default value can be a JSON boolean.
    filter="${filter} | .reviewer = false"
  else
    filter="${filter} | .reviewer = \$reviewer"
    args+=(--arg reviewer "$REVIEWER")
  fi
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

if ! NEW_CONTENT="$(jq -n "${args[@]}" "{} | ${filter}" 2>&1)"; then
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
