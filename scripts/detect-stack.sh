#!/usr/bin/env bash
# milestone-bootstrapper — stack detector (Job 1 detection-and-mapping core).
#
# Detects the project's stack from repo signals and maps each detected stack to
# (a) the best-practice convention note (-> conventions.md), (b) the framework +
# version pin (-> library-manifest.md), and (c) the milestone-driver domainSkills
# candidate (-> driver.json). It REPORTS findings; it never writes docs or config
# (#7/#8/#9 consume this output). The Stack->domainSkills mapping is the driver
# setup table VERBATIM (milestone-driver/skills/setup/SKILL.md:39-49) — the single
# source; this script does not invent a drifting copy.
#
# GUARDRAIL EXEMPTION — ruby domainSkills (tracked divergence): the `Ruby (Rails)`
# and `Ruby (generic)` findings' domainSkills value (`["ruby-lsp",
# "superpowers:test-driven-development","superpowers:systematic-debugging"]`) is a
# deliberate, tracked divergence from the VERBATIM-mirror invariant above — this
# value is CONFIRMED ABSENT from the driver's own Stack->domainSkills table today
# (milestone-driver/skills/setup/SKILL.md:39-49). The reason is a source-repo
# boundary: updating milestone-driver's own table is out of scope for a
# milestone-bootstrapper PR. Reconcile by adding the Ruby row to milestone-driver's
# skills/setup/SKILL.md Stack->domainSkills table in a follow-up PR against that
# repo. The invariant above still governs EVERY OTHER stack's domainSkills value
# against table parity; do NOT extend this exemption to any other stack.
# Resolves #104 (ruby detection — decided: exempt + track, not cross-repo edit).
#
# Contract:
#   - One TSV row per finding (flat/tabular suite output style).
#   - Genuine unknowns -> [TBD] + flagged for a human (suite DNA: prefix the
#     finding's note with the 🔴 marker). "none"/"not yet" is a valid value.
#   - Never fabricates a stack value or a skill mapping; emits an EMPTY
#     domainSkills field for an unmapped stack (per the table's omit rows).
#   - A malformed signal file is REPORTED and flagged, the pass CONTINUES; one
#     bad file never aborts the whole detection.
#   - Multi-signal repo: reports every detected stack; an ambiguous primary
#     stack (>1 distinct app stack) is flagged for the human.
#
# Usage:   detect-stack.sh [REPO_DIR]   (default: $PWD)
# Output:  TSV on stdout — header then one finding per line. Columns:
#            stack  signal  convention  manifestPin  domainSkills  flag  versionFile
#          domainSkills is a JSON array literal (e.g. ["maui-skills:*"]) or empty.
#          flag is the literal string "human" for rows needing a human, else "".
#          versionFile is the repo-relative version-file PATH actually found for
#          this stack (node -> .nvmrc else .node-version; python -> .python-version;
#          ruby -> .ruby-version; .NET / MAUI -> global.json), or EMPTY when no such
#          file exists or the stack has no version-file concept. Never a resolved
#          concrete version — setup-* actions read the version from the file on
#          the runner. Never a fabricated path (flag-don't-guess): empty when the
#          file is absent.
# Requires: jq preferred for package.json parsing. When jq is absent, the Node
#          block falls back to a grep-based Angular check (parity with the pwsh
#          twin's built-in JSON parse) — jq-absent is NOT treated as malformed
#          JSON. A genuinely malformed package.json (jq present, parse fails) is
#          still reported and flagged.
# Escape:  none — read-only, side-effect-free.
set -u

FLAG='🔴'                 # suite output-style human-attention marker
TBD='[TBD]'

repo="${1:-$PWD}"
repo="${repo%/}"
[ -d "$repo" ] || { printf 'detect-stack: not a directory: %s\n' "$repo" >&2; exit 1; }

have_jq=1
command -v jq >/dev/null 2>&1 || have_jq=0

# Findings accumulate as TSV lines; ambiguity flag is decided after the pass.
findings=()
app_stacks=()             # distinct application stacks, for primary-ambiguity check

# emit_finding STACK SIGNAL CONVENTION MANIFEST DOMAINSKILLS FLAG [VERSIONFILE]
emit_finding() {
  # Tabs separate columns; guard against embedded tabs/newlines in inputs. The 7th
  # column (versionFile) is APPENDED after flag; it defaults to empty so the six
  # existing call sites that pass only six args keep their established output.
  local stack="$1" signal="$2" conv="$3" pin="$4" skills="$5" flag="$6" verfile="${7:-}"
  findings+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$stack" "$signal" "$conv" "$pin" "$skills" "$flag" "$verfile")")
}

# first existing match of a glob under repo (NUL-safe-ish; globs are simple here)
first_match() {
  local pat="$1" f
  for f in $repo/$pat; do [ -e "$f" ] && { printf '%s' "$f"; return 0; }; done
  return 1
}

# version_file CANDIDATE...: print the first candidate that exists as a regular
# file under repo (the version-file PATH actually present), else print nothing.
# Reuses the same presence test (`-f`) the per-stack signal blocks already use —
# flag-don't-guess: an absent file yields an EMPTY column, never a fabricated path.
version_file() {
  local c
  for c in "$@"; do [ -f "$repo/$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}

# ---------------------------------------------------------------------------
# Python — pyproject.toml
# ---------------------------------------------------------------------------
if [ -f "$repo/pyproject.toml" ]; then
  app_stacks+=("python")
  py_verfile="$(version_file '.python-version')" || py_verfile=""
  # Framework hint from a dependency line (best-effort, grep — toml has no jq).
  fw=""
  if grep -qiE '(^|[^a-z])fastapi([^a-z]|$)' "$repo/pyproject.toml" 2>/dev/null; then fw="FastAPI"
  elif grep -qiE '(^|[^a-z])django([^a-z]|$)' "$repo/pyproject.toml" 2>/dev/null; then fw="Django"
  elif grep -qiE '(^|[^a-z])flask([^a-z]|$)' "$repo/pyproject.toml" 2>/dev/null; then fw="Flask"
  fi
  case "$fw" in
    FastAPI) conv="FastAPI: Pydantic models, dependency-injection pattern, async I/O, router/layout structure" ;;
    Django)  conv="Django: apps/models/views layout, ORM migrations, settings split" ;;
    Flask)   conv="Flask: blueprint layout, app factory, explicit extensions" ;;
    *)       fw="$TBD"; conv="$FLAG framework not resolved from pyproject.toml — confirm framework + conventions" ;;
  esac
  if [ "$fw" = "$TBD" ]; then
    # Genuine unknown — framework signal present but unresolved. [TBD] + flag for
    # the human. Per the omit rows, Python still maps to NO domainSkills (never
    # fabricated). flag=human marks the unresolved field, not the version pin.
    emit_finding "Python" "pyproject.toml" "$conv" "Python $TBD; framework $TBD" "" "human" "$py_verfile"
  else
    # Framework resolved -> omit domainSkills (Python omit row). The version pin
    # stays [TBD] for the interview to confirm; that is an expected state, not a
    # genuine unknown, so it is NOT flagged (parity with Node/.NET pins).
    emit_finding "Python ($fw)" "pyproject.toml" "$conv" "Python $TBD; $fw $TBD (pin version)" "" "" "$py_verfile"
  fi
fi

# ---------------------------------------------------------------------------
# Node — package.json (+ Angular discrimination)
# ---------------------------------------------------------------------------
# emit_node_angular / emit_node_next / emit_node_react / emit_node_vue /
# emit_node_svelte / emit_node_generic: the per-framework Node findings, factored
# so both the jq path and the jq-absent grep fallback emit identically (single
# source for the Stack->domainSkills mapping; no drift between paths). React /
# Vue / Svelte / Next are ABSENT from the setup Stack->domainSkills table, so they
# omit domainSkills (empty field) — the same never-fabricate-a-skill-mapping
# convention as generic Node (:16-17 contract), NOT [TBD].
emit_node_angular() {
  app_stacks+=("angular")
  emit_finding "Angular (Node)" "package.json" \
    "Angular: standalone components, typed reactive forms, OnPush change detection, feature-module/route layout" \
    "Node $TBD; Angular $TBD (pin @angular/core version)" \
    '["angular-skills:angular-developer"]' "" "$node_verfile"
}
emit_node_next() {
  app_stacks+=("next")
  emit_finding "Next.js (Node)" "package.json" \
    "Next.js: app-router/file-based routing, server components by default, colocated data fetching, API route handlers" \
    "Node $TBD; Next.js $TBD (pin next version)" \
    "" "" "$node_verfile"
}
emit_node_react() {
  app_stacks+=("react")
  emit_finding "React (Node)" "package.json" \
    "React: function components with hooks, unidirectional data flow, composition over inheritance, stable keys on lists" \
    "Node $TBD; React $TBD (pin react version)" \
    "" "" "$node_verfile"
}
emit_node_vue() {
  app_stacks+=("vue")
  emit_finding "Vue (Node)" "package.json" \
    "Vue: single-file components, Composition API, reactive refs/computed, scoped styles" \
    "Node $TBD; Vue $TBD (pin vue version)" \
    "" "" "$node_verfile"
}
emit_node_svelte() {
  app_stacks+=("svelte")
  emit_finding "Svelte (Node)" "package.json" \
    "Svelte: single-file components, reactive declarations, stores for shared state, compile-time minimal runtime" \
    "Node $TBD; Svelte $TBD (pin svelte version)" \
    "" "" "$node_verfile"
}
emit_node_generic() {
  app_stacks+=("node")
  # Generic Node -> omit (no mapped skill); NOT fabricated, NOT [TBD].
  emit_finding "Node (generic)" "package.json" \
    "Node: ESM modules, package scripts as task entrypoints, lockfile committed" \
    "Node $TBD (pin engines.node / runtime)" \
    "" "" "$node_verfile"
}

if [ -f "$repo/package.json" ]; then
  # Node version-file PATH: .nvmrc takes precedence over .node-version (the order
  # the candidates are passed). Empty when neither exists. Same presence fact
  # whether or not package.json parses, so it is computed once for all node rows.
  node_verfile="$(version_file '.nvmrc' '.node-version')" || node_verfile=""
  if [ "$have_jq" = "1" ]; then
    if jq -e . "$repo/package.json" >/dev/null 2>&1; then
      # Valid JSON, jq present: precise dependency-key framework discrimination,
      # MOST-SPECIFIC-FIRST (exactly one branch fires -> one node-family finding).
      # Next MUST precede React: a Next app carries BOTH `next` and `react`.
      if jq -e '((.dependencies // {}) + (.devDependencies // {})) | keys[] | select(startswith("@angular/"))' \
           "$repo/package.json" >/dev/null 2>&1; then
        emit_node_angular
      elif jq -e '((.dependencies // {}) + (.devDependencies // {})) | has("next")' \
           "$repo/package.json" >/dev/null 2>&1; then
        emit_node_next
      elif jq -e '((.dependencies // {}) + (.devDependencies // {})) | has("react")' \
           "$repo/package.json" >/dev/null 2>&1; then
        emit_node_react
      elif jq -e '((.dependencies // {}) + (.devDependencies // {})) | has("vue")' \
           "$repo/package.json" >/dev/null 2>&1; then
        emit_node_vue
      elif jq -e '((.dependencies // {}) + (.devDependencies // {})) | has("svelte")' \
           "$repo/package.json" >/dev/null 2>&1; then
        emit_node_svelte
      else
        emit_node_generic
      fi
    else
      # Genuinely malformed JSON (jq present, parse FAILED): report + flag,
      # CONTINUE the pass. This is the ONLY path that asserts the file is broken.
      app_stacks+=("node")
      emit_finding "Node ($TBD)" "package.json" \
        "$FLAG package.json present but failed to parse — fix JSON, then re-detect" \
        "$TBD" "" "human" "$node_verfile"
    fi
  else
    # jq absent: do NOT claim the JSON is malformed (the file may be fine). Fall
    # back to a grep-based Angular check on the raw file so the Angular mapping
    # and generic-Node classification still work — parity with the pwsh twin,
    # which parses with built-in ConvertFrom-Json and needs no external tool.
    # Mirrors the Python block's grep-on-signal-file convention above. Same
    # most-specific-first order as the jq path (Next before React). Each new
    # pattern anchors to a dependency KEY followed by a colon to avoid array-value
    # false positives; a script-KEY false positive (e.g. a "react" npm script) is
    # an accepted known limitation of the jq-ABSENT fallback, consistent with the
    # existing Angular fallback — the jq path and the pwsh twin are precise.
    if grep -qE '"@angular/' "$repo/package.json" 2>/dev/null; then
      emit_node_angular
    elif grep -qE '"next"[[:space:]]*:' "$repo/package.json" 2>/dev/null; then
      emit_node_next
    elif grep -qE '"react"[[:space:]]*:' "$repo/package.json" 2>/dev/null; then
      emit_node_react
    elif grep -qE '"vue"[[:space:]]*:' "$repo/package.json" 2>/dev/null; then
      emit_node_vue
    elif grep -qE '"svelte"[[:space:]]*:' "$repo/package.json" 2>/dev/null; then
      emit_node_svelte
    else
      emit_node_generic
    fi
  fi
fi

# ---------------------------------------------------------------------------
# .NET — *.csproj / *.sln (+ MAUI discrimination)
# ---------------------------------------------------------------------------
dotnet_file=""
dotnet_file="$(first_match '*.csproj')" || dotnet_file="$(first_match '*.sln')" || dotnet_file=""
if [ -n "$dotnet_file" ]; then
  # .NET version-file PATH: global.json (pins the SDK band) for both MAUI and
  # non-MAUI. Empty when absent.
  dotnet_verfile="$(version_file 'global.json')" || dotnet_verfile=""
  # MAUI if any csproj declares the maui workload / UseMaui, or references Maui.
  is_maui=0
  # Scan every csproj in the tree (root and nested) for a MAUI marker. find is
  # portable and avoids depending on bash globstar (off by default), which would
  # leave a literal `**` unexpanded and miss nested projects.
  while IFS= read -r cs; do
    [ -e "$cs" ] || continue
    if grep -qiE 'UseMaui|net[0-9]+\.[0-9]+-(android|ios|maccatalyst)|Microsoft\.Maui' "$cs" 2>/dev/null; then
      is_maui=1; break
    fi
  done < <(find "$repo" -type f -name '*.csproj' 2>/dev/null)
  if [ "$is_maui" = "1" ]; then
    app_stacks+=("maui")
    emit_finding ".NET MAUI" "$(basename "$dotnet_file")" \
      "MAUI: MVVM, XAML resource dictionaries, handlers over renderers, current-API adherence (no obsolete APIs)" \
      ".NET $TBD; MAUI $TBD (pin TFM + workload)" \
      '["maui-skills:*","maui-current-apis"]' "" "$dotnet_verfile"
  else
    app_stacks+=("dotnet")
    # Non-MAUI .NET -> omit (no bundled domain skill). NOT [TBD] — a known omit.
    emit_finding ".NET (non-MAUI)" "$(basename "$dotnet_file")" \
      ".NET: DI via host builder, async/await, options pattern, layered project structure" \
      ".NET $TBD (pin TargetFramework)" \
      "" "" "$dotnet_verfile"
  fi
fi

# ---------------------------------------------------------------------------
# Rust — Cargo.toml
# ---------------------------------------------------------------------------
if [ -f "$repo/Cargo.toml" ]; then
  app_stacks+=("rust")
  emit_finding "Rust" "Cargo.toml" \
    "Rust: edition pinned, modules over files, Result/error-enum conventions, clippy clean" \
    "Rust $TBD (pin edition / toolchain)" \
    "" ""
fi

# ---------------------------------------------------------------------------
# Ruby — Gemfile (+ Rails discrimination)
# ---------------------------------------------------------------------------
if [ -f "$repo/Gemfile" ]; then
  app_stacks+=("ruby")
  ruby_verfile="$(version_file '.ruby-version')" || ruby_verfile=""
  # domainSkills is the SAME bundle for both Rails and generic Ruby — language-
  # level tooling, not Rails-specific. See the GUARDRAIL EXEMPTION above (header)
  # for why this value diverges from the driver's own Stack->domainSkills table.
  ruby_skills='["ruby-lsp","superpowers:test-driven-development","superpowers:systematic-debugging"]'
  # Framework hint from a dependency line (best-effort, grep — Gemfile has no
  # jq). Mirrors the Python block's grep-based framework-discrimination idiom
  # above; case-insensitivity is handled entirely by grep -i on the file
  # content, so no shell-level case folding is used (bash-3.2 safe).
  if grep -qiE '(^|[^a-z])rails([^a-z]|$)' "$repo/Gemfile" 2>/dev/null; then
    # Rails resolved -> the version pin stays [TBD] for the interview to
    # confirm; that is an expected state, not a genuine unknown, so it is NOT
    # flagged (parity with Node/.NET/Python pins).
    emit_finding "Ruby (Rails)" "Gemfile" \
      "Rails: MVC layout (app/models, app/controllers, app/views), ActiveRecord migrations, config/routes.rb, convention over configuration" \
      "Ruby $TBD; Rails $TBD (pin version)" \
      "$ruby_skills" "" "$ruby_verfile"
  else
    # Plain Ruby is itself a valid, fully-resolved answer, not a genuine unknown
    # (per .project/design-philosophy.md#Error & failure philosophy) — NOT
    # flagged/[TBD]-as-unresolved, mirroring generic Node's plain blurb.
    emit_finding "Ruby (generic)" "Gemfile" \
      "Ruby: Bundler-managed Gemfile, RuboCop-style formatting conventions" \
      "Ruby $TBD (pin version)" \
      "$ruby_skills" "" "$ruby_verfile"
  fi
fi

# ---------------------------------------------------------------------------
# Claude Code plugin — skills/** + agents/** + hooks/**
# ---------------------------------------------------------------------------
has_skills=0; has_agents=0; has_hooks=0
[ -d "$repo/skills" ] && has_skills=1
[ -d "$repo/agents" ] && has_agents=1
[ -d "$repo/hooks" ]  && has_hooks=1
# Plugin manifest is a stronger signal; treat it as confirming the plugin stack.
[ -f "$repo/.claude-plugin/plugin.json" ] && { has_skills=1; }
if [ "$has_skills" = "1" ] && [ "$has_agents" = "1" ] && [ "$has_hooks" = "1" ]; then
  app_stacks+=("plugin")
  emit_finding "Claude Code plugin" "skills/+agents/+hooks/" \
    "Plugin: skill-per-capability, frontmatter triggers, cross-platform bash+pwsh hooks, no-BOM LF scripts" \
    "Claude Code plugin schema $TBD (pin .claude-plugin/plugin.json version)" \
    '["plugin-dev:*","superpowers:writing-skills"]' ""
fi

# ---------------------------------------------------------------------------
# Resolve / emit
# ---------------------------------------------------------------------------
# Distinct application stacks (dedupe).
uniq_stacks=()
for s in "${app_stacks[@]:-}"; do
  [ -z "$s" ] && continue
  dup=0; for u in "${uniq_stacks[@]:-}"; do [ "$u" = "$s" ] && dup=1; done
  [ "$dup" = "0" ] && uniq_stacks+=("$s")
done

# Header (always emitted). The 7th column (versionFile) is appended after flag.
printf 'stack\tsignal\tconvention\tmanifestPin\tdomainSkills\tflag\tversionFile\n'

if [ "${#findings[@]}" -eq 0 ]; then
  # None state: no recognizable stack signal at all. "none" is a valid value,
  # but the absence of ANY stack is something a human should confirm. No stack
  # means no version-file concept -> empty 7th column.
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "none" "(no stack signal)" \
    "$FLAG no recognizable stack signal found — confirm this is intentional or supply the stack" \
    "none" "" "human" ""
  exit 0
fi

# Ambiguous primary: more than one distinct application stack present. The primary
# is unresolved, so no single version-file is asserted -> empty 7th column (the
# per-stack rows below still carry their own version-file paths).
if [ "${#uniq_stacks[@]}" -gt 1 ]; then
  joined="$(printf '%s,' "${uniq_stacks[@]}")"; joined="${joined%,}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "(multi-stack)" "$joined" \
    "$FLAG multiple application stacks detected — confirm the primary stack for the project" \
    "n/a" "" "human" ""
fi

for line in "${findings[@]}"; do printf '%s\n' "$line"; done
exit 0
