#!/usr/bin/env bash
#
# write-feeder-config.sh — write the target repo's `.milestone-config/feeder.json`
# config slice (the feeder-owned keys: `projectDocs`, `reviewer`).
#
# What this does, in plain terms:
#   The bootstrapper's `apply` skill (#13) leaves the TARGET repo with a valid
#   feeder profile so `milestone-feeder` runs with no further setup. `apply` is
#   non-interactive, so this is a deterministic, reusable writer it calls — NOT
#   the interactive `milestone-feeder:setup` interview (that path is interview-
#   only, with no non-interactive entry, so it cannot run unattended). Recorded
#   decision: issue #5 "✅ Design decision — Option A". This writer produces the
#   identical file `setup`'s Phase 3 would, to the same schema and the same
#   absent-means-default discipline.
#
# Authoritative schema (DRIFT GUARDRAIL — do not widen without updating both):
#   The feeder-owned key set and the absent-means-default discipline are defined
#   by the canonical schema doc:
#     milestone-feeder/docs/profile-schema.md
#       - "Own keys" table          -> projectDocs (default ".project/"),
#                                       reviewer    (default "milestone-driver")
#       - "Absent-means-default discipline" -> omit a key left at its BUNDLED
#                                       default; an empty `{}` is a valid profile.
#   This slice writes ONLY `projectDocs` and `reviewer`. It deliberately does NOT
#   write the shared/driver keys (uiSurfaceGlobs, integrationBranch, the
#   consumer's sourceGlobs, domainSkills, versioning, nonNegotiables) — those are
#   read from the driver config and owned by the driver-config slice (#8). If the
#   feeder's schema gains or renames an own-key, update this script in lockstep.
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
#   Env fallbacks (args win): FEEDER_PROJECT_DOCS, FEEDER_REVIEWER, FEEDER_REPO.
#
# Behavior:
#   - ALWAYS writes the file (even `{}`) so config-presence is unambiguous: an
#     absent file and an empty `{}` are deliberately distinct signals.
#   - Idempotent / non-destructive: when the assembled object is byte-identical
#     to an existing file's content, the file is left untouched (true no-op);
#     re-runs never duplicate. (Key-level diff+patch of human edits is the
#     future `update` skill's job, not this primitive writer's.)
#   - Errors (unwritable path, jq failure) surface a clear message on stderr and
#     exit non-zero — never leaving a partially-written / invalid file in place.
#
# Run it:  ./scripts/write-feeder-config.sh --repo /path/to/target [--project-docs ...] [--reviewer ...]
# Exit 0 = file is present and correct. Exit 1 = bad input. Exit 2 = write/serialize failure.

set -euo pipefail

# --- Bundled defaults (mirror milestone-feeder/docs/profile-schema.md) ---------
readonly DEFAULT_PROJECT_DOCS=".project/"
readonly DEFAULT_REVIEWER="milestone-driver"

# --- Inputs (args override env; env overrides default) -------------------------
REPO="${FEEDER_REPO:-.}"
PROJECT_DOCS="${FEEDER_PROJECT_DOCS:-$DEFAULT_PROJECT_DOCS}"
REVIEWER="${FEEDER_REVIEWER:-$DEFAULT_REVIEWER}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)          REPO="${2:?--repo needs a value}"; shift 2 ;;
    --project-docs)  PROJECT_DOCS="${2:?--project-docs needs a value}"; shift 2 ;;
    --reviewer)      REVIEWER="${2:?--reviewer needs a value}"; shift 2 ;;
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

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found on PATH." >&2; exit 2; }

# --- Assemble the minimal object (absent-means-default: omit bundled defaults) --
# Start from {} and add only keys whose resolved value DIVERGES from the bundled
# default. Build the jq filter incrementally so an all-default run yields `{}`.
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

if ! NEW_CONTENT="$(jq -n "${args[@]}" "{} | ${filter}" 2>&1)"; then
  echo "ERROR: failed to serialize feeder.json: ${NEW_CONTENT}" >&2
  exit 2
fi

# --- Resolve the destination path ---------------------------------------------
CONFIG_DIR="${REPO%/}/.milestone-config"
CONFIG_FILE="${CONFIG_DIR}/feeder.json"

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
