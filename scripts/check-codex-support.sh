#!/usr/bin/env bash
#
# check-codex-support.sh — the CI gate for the Codex manifest and the
# plugin-root script-invocation rule.
#
# What this checks:
#   1. .codex-plugin/plugin.json parses as JSON.
#   2. Its name, version, and description equal .claude-plugin/plugin.json's.
#   3. Every "./"-relative path it references exists in the repo.
#   4. No skill text invokes a script CWD-relative: no `./scripts/<x>` or
#      `.\scripts\<x>` anywhere under skills/, and no bare `scripts/<x>` in a
#      fenced code block. In a consumer repo ./scripts/ does not exist, on
#      Claude Code or Codex. The invocation form is
#      "${CLAUDE_PLUGIN_ROOT}/scripts/<x>" (`& "..."` for .ps1). A prose
#      `scripts/<x>` citation, or one in a `#` comment, is allowed.
#   5. Every skills/*/SKILL.md carries the ${CLAUDE_PLUGIN_ROOT} resolution
#      line and its ../runtime-codex.md pointer.
#
# Bash-only, no PowerShell twin: CI-only tooling, same exception as
# scripts/check-skill-size.sh. Needs jq (preinstalled on ubuntu-latest).
#
# Run it locally from the repo root: ./scripts/check-codex-support.sh
# Exit 0 = every check passed. Exit 1 = at least one failed; each failure is
# printed to stderr.

set -euo pipefail

cd "$(dirname "$0")/.."

CODEX=.codex-plugin/plugin.json
CLAUDE=.claude-plugin/plugin.json
RESOLUTION_LINE='If `${CLAUDE_PLUGIN_ROOT}` appears unexpanded, it is the parent of the `skills/` directory that holds this file.'

fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is not installed; this check needs it." >&2
  exit 1
fi

for manifest in "$CODEX" "$CLAUDE"; do
  if ! jq -e . "$manifest" >/dev/null 2>&1; then
    echo "FAIL: ${manifest} is missing or not valid JSON." >&2
    exit 1
  fi
done

for key in name version description; do
  codex_val="$(jq -r ".${key}" "$CODEX")"
  claude_val="$(jq -r ".${key}" "$CLAUDE")"
  if [ "$codex_val" != "$claude_val" ]; then
    echo "FAIL: ${key} differs — ${CODEX} has '${codex_val}', ${CLAUDE} has '${claude_val}'." >&2
    fail=1
  fi
done

while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  if [ ! -e "$ref" ]; then
    echo "FAIL: ${CODEX} references '${ref}', which does not exist." >&2
    fail=1
  fi
done <<EOF
$(jq -r '.. | strings | select(startswith("./"))' "$CODEX")
EOF

# Anywhere: `./scripts/` (not `../scripts/`) or `.\scripts\`. Inside a fenced
# code block, after dropping a trailing `#` comment: any `scripts/` not
# preceded by `/`, which catches `bash scripts/x.sh` and `$ scripts/x`.
cwd_relative="$(find skills -name '*.md' -print0 | xargs -0 awk '
  FNR == 1 { fence = 0 }
  /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
  {
    line = $0
    if (line ~ /(^|[^.])\.\/scripts\// || line ~ /\.\\scripts\\/) { print FILENAME ":" FNR ":" $0; next }
    if (fence) {
      sub(/(^|[[:space:]])#.*/, "", line)
      if (line ~ /(^|[^\/])scripts\//) print FILENAME ":" FNR ":" $0
    }
  }')"
if [ -n "$cwd_relative" ]; then
  echo "FAIL: CWD-relative script invocation in skills/; use \"\${CLAUDE_PLUGIN_ROOT}/scripts/<x>\":" >&2
  echo "$cwd_relative" >&2
  fail=1
fi

for f in skills/*/SKILL.md; do
  [ -e "$f" ] || continue
  if ! grep -qF "$RESOLUTION_LINE" "$f" || ! grep -qF '../runtime-codex.md' "$f"; then
    echo "FAIL: ${f} is missing the \${CLAUDE_PLUGIN_ROOT} resolution line or its ../runtime-codex.md pointer." >&2
    fail=1
  fi
done

if [ "$fail" -eq 1 ]; then
  exit 1
fi

echo "PASS: ${CODEX} matches ${CLAUDE} (name, version, description), its paths exist, no skill invokes a script CWD-relative, and every SKILL.md carries the resolution line."
exit 0
