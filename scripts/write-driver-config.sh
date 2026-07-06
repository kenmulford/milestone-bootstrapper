#!/usr/bin/env bash
#
# write-driver-config.sh — write the target repo's `.milestone-config/driver.json`
# config slice (the driver profile the mechanical gates and skills read).
#
# What this does, in plain terms:
#   The bootstrapper's `apply` skill leaves the TARGET repo with a valid driver
#   profile so `milestone-driver` (and `milestone-feeder`, which reads shared
#   keys from it) run with no further setup (Job 2 "Configs", BRIEF.md:47).
#   `apply` is plan-driven and non-interactive — the approved plan file is the
#   contract (preview-then-execute; BRIEF.md:22-26,64) — so this is a
#   deterministic, reusable writer it calls. It deliberately does NOT invoke
#   `milestone-driver:setup`: that skill's only entry contract is an interactive,
#   tier-by-tier interview (milestone-driver/skills/setup/SKILL.md:50-57) with no
#   non-interactive value-injection entry point; invoking it from `apply` would
#   re-interview the user mid-run, violating the plan-is-the-contract model.
#   Composability and "never keep a second, drifting definition" (BRIEF.md:52,68)
#   are honored by REUSING setup's canonical PATH + KEY SCHEMA as the single
#   source of truth — not by invoking the interview. The PowerShell 7+ twin is
#   write-driver-config.ps1 (suite cross-platform convention).
#
# Authoritative schema (DRIFT GUARDRAIL — do not widen without updating both):
#   The driver key set, types, the canonical path, and the absent-means-default
#   discipline are defined by the canonical schema doc — the SINGLE source of
#   truth this writer mirrors (never re-defines):
#     milestone-driver/docs/profile-schema.md
#       - "Location"          -> <repo-root>/.milestone-config/driver.json
#                                (profile-schema.md:12-16)
#       - "Keys" table        -> key names + types (profile-schema.md:91-112)
#       - "Minimal example"   -> the 3 Core keys alone is a valid profile
#                                (profile-schema.md:134-142)
#       - "Design principle"  -> implementerAgent is default-filled and OMITTED;
#                                absent-means-default — omit, never null/empty
#                                (profile-schema.md:68, 87, 144)
#   This slice writes ONLY the keys the approved plan supplies (see Inputs). It
#   does NOT emit speculative keys (triageAgent, designReviewAgent, e2eTestCmd,
#   integrationGranularity, integrations.trello) — they are not
#   in this writer's plan-driven input set. If the driver schema gains or renames
#   a key this writer emits, update this script in lockstep.
#
#   GUARDRAIL EXEMPTION — projectDocs: `projectDocs` is an INTENTIONALLY-emitted
#   additive key that ships AHEAD of the sibling driver schema
#   (milestone-driver/docs/profile-schema.md) and its consumer. This is a
#   recorded, deliberate widening — not drift — per docs/efficiency-grounding-plan.md
#   "Dependencies & sequence" ("Safe to ship independently and first", line 52)
#   and the tracking issue bootstrapper #38. It mirrors write-feeder-config's
#   projectDocs (default ".project/", omit-when-default) so the pointer never
#   drifts between feeder.json and driver.json. The guardrail above still governs
#   EVERY OTHER key against schema parity; do NOT "un-widen" projectDocs back to
#   schema parity — that would re-introduce the drift this key exists to prevent.
#
#   GUARDRAIL EXEMPTION — stack / stackVersionFile (PERMANENT, by design): `stack`
#   and `stackVersionFile` are INTENTIONALLY-emitted additive keys that are
#   PERMANENTLY exempt from the sibling driver schema (milestone-driver/docs/
#   profile-schema.md) — NOT a temporary ship-ahead. The milestone-driver plugin
#   never consumes these keys; only THIS bootstrapper's emit-ci-workflow reads them
#   back. A schema documents what its plugin consumes, so these bootstrapper-owned
#   keys are canonically documented in this repo's SPEC §6.1 and deliberately kept
#   OUT of the driver's schema (profile-schema.md carries a one-line pointer to
#   SPEC §6.1 for file-completeness, with no per-key lockstep). The guardrail still
#   governs EVERY OTHER key against schema parity; do NOT "un-widen" these keys back
#   to schema parity — that would re-introduce the drift this exemption prevents.
#   Resolves #66 (schema convergence — decided: permanent exemption, not converge).
#
# Inputs (RESOLVED values from the approved plan — this writer does NOT
# re-detect them; detection happened in `plan`):
#   --repo <dir>              target repo root (default: current directory)
#   Core (required — all three or the writer refuses with exit 1):
#     --integration-branch <str>  e.g. "develop"
#     --protected-branch   <str>  e.g. "main"
#     --source-globs       <json> JSON string[] e.g. '["src/**","tests/**"]'
#   Optional (OMITTED when not passed — never written as null/empty):
#     --project-docs       <str>  the resolved `.project/` path (default
#                                 ".project/"; OMITTED from the file when equal to
#                                 the bundled default — the omit test is against
#                                 the BUNDLED default, mirroring write-feeder-config).
#     --domain-skills      <json> JSON string[]  (#3 stack->domainSkills)
#     --non-negotiables    <json> JSON string[]  hard constraints the implementer
#                                 must honour (framework versions, platform targets).
#     --ui-surface-globs   <json> JSON string[]
#     --unit-test-cmd      <str>
#     --preflight-cmd      <str>
#     --e2e-env            <json> JSON object
#     --versioning <true|false>   #4 versioning policy. absent-means-versioned:
#                                 `true` (or omitted) => OMIT the key;
#                                 `false` => write `versioning: false` (the ONLY
#                                 value ever written for this key).
#     --stack <enum>              the runtime family the emitter will scaffold setup
#                                 for, one of
#                                 node|python|dotnet|maui|rust|plugin|ruby|none.
#                                 absent-means-default: `none` (or omitted) => OMIT
#                                 the key; any other member => write it. An unknown
#                                 value is a bad input (exit 1).
#     --stack-version-file <str> the detected version-file path (e.g. ".nvmrc",
#                                 ".python-version", "global.json"). OMITTED when not
#                                 passed — never written as null/empty.
#   Env fallbacks (args win): DRIVER_REPO, DRIVER_INTEGRATION_BRANCH,
#     DRIVER_PROTECTED_BRANCH, DRIVER_SOURCE_GLOBS, DRIVER_PROJECT_DOCS,
#     DRIVER_DOMAIN_SKILLS, DRIVER_NON_NEGOTIABLES, DRIVER_UI_SURFACE_GLOBS,
#     DRIVER_UNIT_TEST_CMD, DRIVER_PREFLIGHT_CMD, DRIVER_E2E_ENV, DRIVER_VERSIONING,
#     DRIVER_STACK, DRIVER_STACK_VERSION_FILE.
#
# Behavior:
#   - The minimal valid output is the three Core keys alone (schema:134-142).
#   - Keys the plan does not supply are OMITTED — never written as null/empty.
#     `implementerAgent` is OMITTED (default-filled; schema:68,144). `versioning`
#     is OMITTED when versioned, written `false` only for explicit version-free.
#     `projectDocs` is OMITTED when left at the bundled default ".project/" and
#     written only for a divergent value (omit-when-default, against the BUNDLED
#     default — mirroring write-feeder-config.sh:95-98).
#   - Idempotent / non-destructive: when the assembled object is byte-identical
#     to the existing file, it is left untouched (true no-op); re-runs never
#     duplicate. It never deletes a leftover legacy root milestone-driver.json
#     and never clobbers human edits beyond the plan's scope (reconciling a
#     changed plan onto a bootstrapped repo is `update`'s job, not this writer's).
#   - Errors (missing Core key, bad JSON, unwritable path) surface a clear
#     message on stderr and exit non-zero — never leaving a partial/invalid file.
#
# Run it:  ./scripts/write-driver-config.sh --repo /path/to/target \
#            --integration-branch develop --protected-branch main \
#            --source-globs '["src/**","tests/**"]' [optional keys...]
# Exit 0 = file is present and correct. Exit 1 = bad input. Exit 2 = write/serialize failure.

set -euo pipefail

# --- Bundled default (mirror milestone-feeder/docs/profile-schema.md; the shared
# projectDocs pointer's default — see write-feeder-config.sh:58) -----------------
readonly DEFAULT_PROJECT_DOCS=".project/"

# --- Inputs (args override env; env overrides unset) ---------------------------
REPO="${DRIVER_REPO:-.}"
INTEGRATION_BRANCH="${DRIVER_INTEGRATION_BRANCH:-}"
PROTECTED_BRANCH="${DRIVER_PROTECTED_BRANCH:-}"
SOURCE_GLOBS="${DRIVER_SOURCE_GLOBS:-}"
# projectDocs resolves to its bundled default when unset (it has a real default,
# unlike the UNSET-sentinel optional keys below); the omit-when-default test in the
# filter assembly drops it when still equal to the default (write-feeder-config.sh:63).
PROJECT_DOCS="${DRIVER_PROJECT_DOCS:-$DEFAULT_PROJECT_DOCS}"
DOMAIN_SKILLS="${DRIVER_DOMAIN_SKILLS:-}"
NON_NEGOTIABLES="${DRIVER_NON_NEGOTIABLES:-}"
UI_SURFACE_GLOBS="${DRIVER_UI_SURFACE_GLOBS:-}"
UNIT_TEST_CMD="${DRIVER_UNIT_TEST_CMD:-}"
PREFLIGHT_CMD="${DRIVER_PREFLIGHT_CMD:-}"
E2E_ENV="${DRIVER_E2E_ENV:-}"
VERSIONING="${DRIVER_VERSIONING:-}"
# stack resolves to empty when unset (omit-when-`none`; empty is treated as `none`).
STACK="${DRIVER_STACK:-}"
STACK_VERSION_FILE="${DRIVER_STACK_VERSION_FILE:-}"

# Sentinels so an explicitly-passed empty string is distinguishable from "unset".
# Optional string keys use this to tell "--unit-test-cmd ''" (invalid) apart from
# "not passed" (omit). Core keys are validated as non-empty regardless.
UNSET=$'\x00UNSET\x00'
[ -n "${DRIVER_UNIT_TEST_CMD+x}" ] || UNIT_TEST_CMD="$UNSET"
[ -n "${DRIVER_PREFLIGHT_CMD+x}" ]  || PREFLIGHT_CMD="$UNSET"
[ -n "${DRIVER_DOMAIN_SKILLS+x}" ]  || DOMAIN_SKILLS="$UNSET"
[ -n "${DRIVER_NON_NEGOTIABLES+x}" ] || NON_NEGOTIABLES="$UNSET"
[ -n "${DRIVER_UI_SURFACE_GLOBS+x}" ] || UI_SURFACE_GLOBS="$UNSET"
[ -n "${DRIVER_E2E_ENV+x}" ]        || E2E_ENV="$UNSET"
[ -n "${DRIVER_VERSIONING+x}" ]     || VERSIONING="$UNSET"
[ -n "${DRIVER_STACK_VERSION_FILE+x}" ] || STACK_VERSION_FILE="$UNSET"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)               REPO="${2:?--repo needs a value}"; shift 2 ;;
    --integration-branch) INTEGRATION_BRANCH="${2:?--integration-branch needs a value}"; shift 2 ;;
    --protected-branch)   PROTECTED_BRANCH="${2:?--protected-branch needs a value}"; shift 2 ;;
    --source-globs)       SOURCE_GLOBS="${2:?--source-globs needs a value}"; shift 2 ;;
    --project-docs)       PROJECT_DOCS="${2:?--project-docs needs a value}"; shift 2 ;;
    --domain-skills)      DOMAIN_SKILLS="${2:?--domain-skills needs a value}"; shift 2 ;;
    --non-negotiables)    NON_NEGOTIABLES="${2:?--non-negotiables needs a value}"; shift 2 ;;
    --ui-surface-globs)   UI_SURFACE_GLOBS="${2:?--ui-surface-globs needs a value}"; shift 2 ;;
    --unit-test-cmd)      UNIT_TEST_CMD="${2?--unit-test-cmd needs a value}"; shift 2 ;;
    --preflight-cmd)      PREFLIGHT_CMD="${2?--preflight-cmd needs a value}"; shift 2 ;;
    --e2e-env)            E2E_ENV="${2:?--e2e-env needs a value}"; shift 2 ;;
    --versioning)         VERSIONING="${2:?--versioning needs a value}"; shift 2 ;;
    --stack)              STACK="${2:?--stack needs a value}"; shift 2 ;;
    --stack-version-file) STACK_VERSION_FILE="${2?--stack-version-file needs a value}"; shift 2 ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found on PATH." >&2; exit 2; }

# --- Validate the three Core keys (all-or-refuse; no partial profile) ----------
# Schema:91-95,134-142 — the three Core keys are required in the file. If any are
# absent, write NO file and name the missing key(s) (acceptance: error path).
missing=()
[ -n "$INTEGRATION_BRANCH" ] || missing+=("--integration-branch")
[ -n "$PROTECTED_BRANCH" ]   || missing+=("--protected-branch")
[ -n "$SOURCE_GLOBS" ]       || missing+=("--source-globs")
if [ "${#missing[@]}" -gt 0 ]; then
  echo "ERROR: missing required Core key(s): ${missing[*]}." >&2
  echo "       The three Core keys (integrationBranch, protectedBranch, sourceGlobs) are required; no file written." >&2
  exit 1
fi

# --- Validate JSON-shaped inputs before assembly (fail with a clear message) ---
# Each array key must parse as a JSON array; e2eEnv as a JSON object. This keeps
# a malformed plan value from producing an invalid driver.json.
validate_json_array() {  # $1=flag-name $2=value
  if ! printf '%s' "$2" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "ERROR: $1 must be a JSON array (got: $2)." >&2
    exit 1
  fi
}
validate_json_object() { # $1=flag-name $2=value
  if ! printf '%s' "$2" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "ERROR: $1 must be a JSON object (got: $2)." >&2
    exit 1
  fi
}

validate_json_array "--source-globs" "$SOURCE_GLOBS"
[ "$DOMAIN_SKILLS" = "$UNSET" ]    || validate_json_array  "--domain-skills"    "$DOMAIN_SKILLS"
[ "$NON_NEGOTIABLES" = "$UNSET" ]  || validate_json_array  "--non-negotiables"  "$NON_NEGOTIABLES"
[ "$UI_SURFACE_GLOBS" = "$UNSET" ] || validate_json_array  "--ui-surface-globs" "$UI_SURFACE_GLOBS"
[ "$E2E_ENV" = "$UNSET" ]          || validate_json_object "--e2e-env"          "$E2E_ENV"

# --- Validate versioning (absent-means-versioned; only `false` is ever written) -
# Schema:105,118 — absent/true => versioned (omit). false => version-free (write).
WRITE_VERSIONING_FALSE=0
if [ "$VERSIONING" != "$UNSET" ]; then
  case "$VERSIONING" in
    false) WRITE_VERSIONING_FALSE=1 ;;
    true)  WRITE_VERSIONING_FALSE=0 ;;  # versioned => omit
    *)
      echo "ERROR: --versioning must be \"true\" or \"false\" (got: $VERSIONING)." >&2
      exit 1 ;;
  esac
fi

# --- Validate stack (omit-when-default; `none`/empty => OMIT, else write) -------
# The enum is node|python|dotnet|maui|rust|plugin|ruby|none. `none` (and an
# unset/empty value) means "omit the key", so it is VALID input. Any other value
# is rejected with a clear message naming the allowed set + exit 1 (mirrors the
# --versioning reject-unknown shape above). The descriptive->enum mapping (e.g.
# angular collapses to node) is issue #65's job — this writer only validates the
# resolved enum. `ruby` covers both Rails and plain Ruby (parity with `python`
# covering FastAPI/Django/Flask/unresolved as one enum member; issue #104).
WRITE_STACK=0
if [ -n "$STACK" ]; then
  case "$STACK" in
    node|python|dotnet|maui|rust|plugin|ruby) WRITE_STACK=1 ;;
    none) WRITE_STACK=0 ;;  # default => omit
    *)
      echo "ERROR: --stack must be one of node|python|dotnet|maui|rust|plugin|ruby|none (got: $STACK)." >&2
      exit 1 ;;
  esac
fi

# --- Assemble the object in canonical key order (Core first, then optional) -----
# Build the jq filter incrementally, adding only keys the plan supplied. Core
# keys are always present. implementerAgent is intentionally never added.
filter='.'
args=(--arg integrationBranch "$INTEGRATION_BRANCH"
      --arg protectedBranch   "$PROTECTED_BRANCH"
      --argjson sourceGlobs   "$SOURCE_GLOBS")
filter="${filter} | .integrationBranch = \$integrationBranch"
filter="${filter} | .protectedBranch = \$protectedBranch"
filter="${filter} | .sourceGlobs = \$sourceGlobs"

# projectDocs is the FIRST optional key (slot immediately after the Core keys),
# emitted ONLY when it diverges from the bundled default — omit-when-default
# against the BUNDLED default (mirror of write-feeder-config.sh:95-98). Same slot
# in the .ps1 twin so output stays byte-identical.
if [ "$PROJECT_DOCS" != "$DEFAULT_PROJECT_DOCS" ]; then
  filter="${filter} | .projectDocs = \$projectDocs"
  args+=(--arg projectDocs "$PROJECT_DOCS")
fi
if [ "$UI_SURFACE_GLOBS" != "$UNSET" ]; then
  filter="${filter} | .uiSurfaceGlobs = \$uiSurfaceGlobs"
  args+=(--argjson uiSurfaceGlobs "$UI_SURFACE_GLOBS")
fi
if [ "$WRITE_VERSIONING_FALSE" -eq 1 ]; then
  filter="${filter} | .versioning = false"
fi
if [ "$UNIT_TEST_CMD" != "$UNSET" ]; then
  filter="${filter} | .unitTestCmd = \$unitTestCmd"
  args+=(--arg unitTestCmd "$UNIT_TEST_CMD")
fi
if [ "$PREFLIGHT_CMD" != "$UNSET" ]; then
  filter="${filter} | .preflightCmd = \$preflightCmd"
  args+=(--arg preflightCmd "$PREFLIGHT_CMD")
fi
if [ "$DOMAIN_SKILLS" != "$UNSET" ]; then
  filter="${filter} | .domainSkills = \$domainSkills"
  args+=(--argjson domainSkills "$DOMAIN_SKILLS")
fi
# nonNegotiables sits immediately after domainSkills so the two Enrichment array
# keys stay adjacent (schema relative order; profile-schema.md:117). Same slot in
# the .ps1 twin so output stays byte-identical.
if [ "$NON_NEGOTIABLES" != "$UNSET" ]; then
  filter="${filter} | .nonNegotiables = \$nonNegotiables"
  args+=(--argjson nonNegotiables "$NON_NEGOTIABLES")
fi
if [ "$E2E_ENV" != "$UNSET" ]; then
  # Canonicalize e2eEnv key order so output is byte-identical to the pwsh twin on
  # EVERY PowerShell 7.x. jq preserves input key order, but the pwsh twin's
  # `ConvertFrom-Json -AsHashtable` returns an UNORDERED [hashtable] on PS 7.0-7.2
  # (only OrderedHashtable on 7.3+). Sorting the object's keys in BOTH writers
  # makes a single canonical order the only possible output regardless of version.
  filter="${filter} | .e2eEnv = (\$e2eEnv | to_entries | sort_by(.key) | from_entries)"
  args+=(--argjson e2eEnv "$E2E_ENV")
fi
# stack / stackVersionFile: additive keys shipping ahead of the canonical schema
# (see GUARDRAIL EXEMPTION above). stack written only for a non-`none` enum member;
# stackVersionFile written only when passed (not the UNSET sentinel). Same slot in
# the .ps1 twin so output stays byte-identical.
if [ "$WRITE_STACK" -eq 1 ]; then
  filter="${filter} | .stack = \$stack"
  args+=(--arg stack "$STACK")
fi
if [ "$STACK_VERSION_FILE" != "$UNSET" ]; then
  filter="${filter} | .stackVersionFile = \$stackVersionFile"
  args+=(--arg stackVersionFile "$STACK_VERSION_FILE")
fi

if ! NEW_CONTENT="$(jq -n "${args[@]}" "{} | ${filter}" 2>&1)"; then
  echo "ERROR: failed to serialize driver.json: ${NEW_CONTENT}" >&2
  exit 2
fi

# --- Resolve the destination path ----------------------------------------------
CONFIG_DIR="${REPO%/}/.milestone-config"
CONFIG_FILE="${CONFIG_DIR}/driver.json"

# Guard: if the config path is an existing DIRECTORY, a later `mv` would silently
# move the temp file INTO it (driver.json/<tmp>) and falsely report success — the
# real file would never be written. Refuse up front with a clear message.
if [ -d "$CONFIG_FILE" ]; then
  echo "ERROR: cannot write driver.json: ${CONFIG_FILE} exists and is a directory." >&2
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
# driver.json in place. printf (not echo) for portable, BOM-free UTF-8 output.
TMP_FILE="$(mktemp "${CONFIG_DIR}/.driver.json.XXXXXX" 2>/dev/null)" || {
  echo "ERROR: cannot write to: ${CONFIG_DIR} (path not writable)." >&2
  exit 2
}
trap 'rm -f "$TMP_FILE"' EXIT

if ! printf '%s\n' "$NEW_CONTENT" > "$TMP_FILE" 2>/dev/null; then
  echo "ERROR: failed to write driver.json to: ${CONFIG_DIR}" >&2
  exit 2
fi

if ! mv "$TMP_FILE" "$CONFIG_FILE" 2>/dev/null; then
  echo "ERROR: failed to write driver.json to: ${CONFIG_DIR}" >&2
  exit 2
fi
trap - EXIT

echo "${CONFIG_FILE} written."
echo "$NEW_CONTENT"
exit 0
