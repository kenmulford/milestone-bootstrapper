#!/usr/bin/env pwsh
# milestone-bootstrapper — stack detector (Job 1 detection-and-mapping core).
# PowerShell-7 parity of scripts/detect-stack.sh (bash-first / pwsh-fallback, the
# suite convention). Same contract, same Stack->domainSkills table VERBATIM from
# milestone-driver/skills/setup/SKILL.md:39-49 (the single source — no drifting
# copy). REPORTS findings; never writes docs or config (#7/#8/#9 consume this).
#
# Contract (identical to the .sh):
#   - One TSV row per finding (flat/tabular suite output style).
#   - Genuine unknowns -> [TBD] + flagged for a human (note prefixed with 🔴,
#     flag column = "human"). "none"/"not yet" is a valid value.
#   - Never fabricates a stack value or skill mapping; empty domainSkills field
#     for an unmapped stack (per the table's omit rows).
#   - A malformed signal file is REPORTED and flagged; the pass CONTINUES.
#   - Multi-signal repo: reports every stack; ambiguous primary is flagged.
#
# Usage:   detect-stack.ps1 [-RepoDir <path>]   (default: current directory)
# Output:  TSV on stdout — header then one finding per line. Columns:
#            stack  signal  convention  manifestPin  domainSkills  flag  versionFile
#          domainSkills is a JSON array literal (e.g. ["maui-skills:*"]) or empty.
#          flag is the literal "human" for rows needing a human, else "".
#          versionFile is the repo-relative version-file PATH actually found for
#          this stack (node -> .nvmrc else .node-version; python -> .python-version;
#          .NET / MAUI -> global.json), or EMPTY when no such file exists or the
#          stack has no version-file concept. Never a resolved concrete version —
#          setup-* actions read the version from the file on the runner. Never a
#          fabricated path (flag-don't-guess): empty when the file is absent.
# Read-only, side-effect-free.

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RepoDir = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

# Emit UTF-8 on stdout so the 🔴 marker survives. PowerShell 7+ already defaults
# to UTF-8, but Windows PowerShell 5.1 uses the OEM/ANSI code page, which would
# mangle the emoji — set it explicitly (BOM-less) for portability across hosts.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# 🔴 suite output-style human-attention marker. U+1F534 is a supplementary-plane
# codepoint (> U+FFFF), so [char] (a 16-bit UTF-16 code unit) cannot hold it —
# ConvertFromUtf32 returns the correct surrogate pair as a string.
$FLAG = [char]::ConvertFromUtf32(0x1F534)
$TBD  = '[TBD]'
$TAB  = "`t"

$repo = ([string]$RepoDir) -replace '\\', '/'
$repo = $repo.TrimEnd('/')
if (-not (Test-Path -LiteralPath $repo -PathType Container)) {
    [Console]::Error.WriteLine("detect-stack: not a directory: $repo")
    exit 1
}

# Findings accumulate; ambiguity flag is decided after the pass.
$findings  = [System.Collections.Generic.List[string]]::new()
$appStacks = [System.Collections.Generic.List[string]]::new()

function Add-Finding {
    param([string]$Stack, [string]$Signal, [string]$Convention,
          [string]$ManifestPin, [string]$DomainSkills, [string]$Flag,
          [string]$VersionFile = '')
    # The 7th column (versionFile) is APPENDED after flag; it defaults to '' so the
    # call sites that pass only six args keep their established output.
    $findings.Add(($Stack, $Signal, $Convention, $ManifestPin, $DomainSkills, $Flag, $VersionFile) -join $TAB)
}

function Join-Path2 { param([string]$a, [string]$b) "$a/$b" }

# First candidate that exists as a regular file under repo (the version-file PATH
# actually present), else ''. Mirrors the .sh version_file helper: reuses the same
# presence test (Test-Path -PathType Leaf) the per-stack signal blocks already use
# — flag-don't-guess: an absent file yields an EMPTY column, never a fabricated path.
function Get-VersionFile {
    param([string[]]$Candidates)
    foreach ($c in $Candidates) {
        if (Test-Path -LiteralPath (Join-Path2 $repo $c) -PathType Leaf) { return $c }
    }
    return ''
}

# ---------------------------------------------------------------------------
# Python — pyproject.toml
# ---------------------------------------------------------------------------
$pyproject = Join-Path2 $repo 'pyproject.toml'
if (Test-Path -LiteralPath $pyproject -PathType Leaf) {
    $appStacks.Add('python')
    $pyVerFile = Get-VersionFile @('.python-version')
    $toml = ''
    try { $toml = Get-Content -LiteralPath $pyproject -Raw -ErrorAction Stop } catch { $toml = '' }
    $fw = ''
    if     ($toml -imatch '(^|[^a-z])fastapi([^a-z]|$)') { $fw = 'FastAPI' }
    elseif ($toml -imatch '(^|[^a-z])django([^a-z]|$)')  { $fw = 'Django' }
    elseif ($toml -imatch '(^|[^a-z])flask([^a-z]|$)')   { $fw = 'Flask' }
    switch ($fw) {
        'FastAPI' { $conv = 'FastAPI: Pydantic models, dependency-injection pattern, async I/O, router/layout structure' }
        'Django'  { $conv = 'Django: apps/models/views layout, ORM migrations, settings split' }
        'Flask'   { $conv = 'Flask: blueprint layout, app factory, explicit extensions' }
        default   { $fw = $TBD; $conv = "$FLAG framework not resolved from pyproject.toml — confirm framework + conventions" }
    }
    if ($fw -eq $TBD) {
        # Genuine unknown — framework present but unresolved. [TBD] + flag. Python
        # still maps to NO domainSkills (omit row); never fabricated.
        Add-Finding 'Python' 'pyproject.toml' $conv "Python $TBD; framework $TBD" '' 'human' $pyVerFile
    } else {
        # Framework resolved -> omit domainSkills. The version pin stays [TBD] for
        # the interview; that is expected, not a genuine unknown -> NOT flagged.
        Add-Finding "Python ($fw)" 'pyproject.toml' $conv "Python $TBD; $fw $TBD (pin version)" '' '' $pyVerFile
    }
}

# ---------------------------------------------------------------------------
# Node — package.json (+ Angular discrimination)
# ---------------------------------------------------------------------------
$pkg = Join-Path2 $repo 'package.json'
if (Test-Path -LiteralPath $pkg -PathType Leaf) {
    # Node version-file PATH: .nvmrc takes precedence over .node-version (the order
    # the candidates are passed). Empty when neither exists. Same presence fact
    # whether or not package.json parses, so it is computed once for all node rows.
    $nodeVerFile = Get-VersionFile @('.nvmrc', '.node-version')
    $pkgJson = $null
    try { $pkgJson = Get-Content -LiteralPath $pkg -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { $pkgJson = $null }
    if ($null -ne $pkgJson) {
        $deps = @()
        if ($pkgJson.dependencies)    { $deps += $pkgJson.dependencies.PSObject.Properties.Name }
        if ($pkgJson.devDependencies) { $deps += $pkgJson.devDependencies.PSObject.Properties.Name }
        # MOST-SPECIFIC-FIRST framework discrimination on exact dependency-KEY
        # membership (exactly one branch fires -> one node-family finding). Next
        # MUST precede React: a Next app carries BOTH 'next' and 'react'. React /
        # Vue / Svelte / Next are ABSENT from the setup Stack->domainSkills table,
        # so they omit domainSkills (empty field) — the same never-fabricate
        # convention as generic Node, NOT [TBD].
        $isAngular = ($deps | Where-Object { $_ -like '@angular/*' } | Select-Object -First 1) -ne $null
        if ($isAngular) {
            $appStacks.Add('angular')
            Add-Finding 'Angular (Node)' 'package.json' `
                'Angular: standalone components, typed reactive forms, OnPush change detection, feature-module/route layout' `
                "Node $TBD; Angular $TBD (pin @angular/core version)" `
                '["angular-skills:angular-developer"]' '' $nodeVerFile
        } elseif ($deps -contains 'next') {
            $appStacks.Add('next')
            Add-Finding 'Next.js (Node)' 'package.json' `
                'Next.js: app-router/file-based routing, server components by default, colocated data fetching, API route handlers' `
                "Node $TBD; Next.js $TBD (pin next version)" `
                '' '' $nodeVerFile
        } elseif ($deps -contains 'react') {
            $appStacks.Add('react')
            Add-Finding 'React (Node)' 'package.json' `
                'React: function components with hooks, unidirectional data flow, composition over inheritance, stable keys on lists' `
                "Node $TBD; React $TBD (pin react version)" `
                '' '' $nodeVerFile
        } elseif ($deps -contains 'vue') {
            $appStacks.Add('vue')
            Add-Finding 'Vue (Node)' 'package.json' `
                'Vue: single-file components, Composition API, reactive refs/computed, scoped styles' `
                "Node $TBD; Vue $TBD (pin vue version)" `
                '' '' $nodeVerFile
        } elseif ($deps -contains 'svelte') {
            $appStacks.Add('svelte')
            Add-Finding 'Svelte (Node)' 'package.json' `
                'Svelte: single-file components, reactive declarations, stores for shared state, compile-time minimal runtime' `
                "Node $TBD; Svelte $TBD (pin svelte version)" `
                '' '' $nodeVerFile
        } else {
            $appStacks.Add('node')
            # Generic Node -> omit (no mapped skill). NOT fabricated, NOT [TBD].
            Add-Finding 'Node (generic)' 'package.json' `
                'Node: ESM modules, package scripts as task entrypoints, lockfile committed' `
                "Node $TBD (pin engines.node / runtime)" `
                '' '' $nodeVerFile
        }
    } else {
        # Malformed/unreadable package.json: report + flag, CONTINUE the pass.
        $appStacks.Add('node')
        Add-Finding "Node ($TBD)" 'package.json' `
            "$FLAG package.json present but failed to parse — fix JSON, then re-detect" `
            $TBD '' 'human' $nodeVerFile
    }
}

# ---------------------------------------------------------------------------
# .NET — *.csproj / *.sln (+ MAUI discrimination)
# ---------------------------------------------------------------------------
$csproj = @(Get-ChildItem -LiteralPath $repo -Filter '*.csproj' -File -ErrorAction SilentlyContinue)
$sln    = @(Get-ChildItem -LiteralPath $repo -Filter '*.sln'    -File -ErrorAction SilentlyContinue)
$dotnetFile = $null
if     ($csproj.Count -gt 0) { $dotnetFile = $csproj[0].Name }
elseif ($sln.Count    -gt 0) { $dotnetFile = $sln[0].Name }
if ($dotnetFile) {
    # .NET version-file PATH: global.json (pins the SDK band) for both MAUI and
    # non-MAUI. Empty when absent.
    $dotnetVerFile = Get-VersionFile @('global.json')
    # Scan every csproj in the tree (root and nested) for a MAUI marker.
    $isMaui = $false
    $allCsproj = @(Get-ChildItem -LiteralPath $repo -Filter '*.csproj' -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($cs in $allCsproj) {
        $body = ''
        try { $body = Get-Content -LiteralPath $cs.FullName -Raw -ErrorAction Stop } catch { $body = '' }
        if ($body -imatch 'UseMaui|net[0-9]+\.[0-9]+-(android|ios|maccatalyst)|Microsoft\.Maui') {
            $isMaui = $true; break
        }
    }
    if ($isMaui) {
        $appStacks.Add('maui')
        Add-Finding '.NET MAUI' $dotnetFile `
            'MAUI: MVVM, XAML resource dictionaries, handlers over renderers, current-API adherence (no obsolete APIs)' `
            ".NET $TBD; MAUI $TBD (pin TFM + workload)" `
            '["maui-skills:*","maui-current-apis"]' '' $dotnetVerFile
    } else {
        $appStacks.Add('dotnet')
        # Non-MAUI .NET -> omit (no bundled domain skill). NOT [TBD] — a known omit.
        Add-Finding '.NET (non-MAUI)' $dotnetFile `
            '.NET: DI via host builder, async/await, options pattern, layered project structure' `
            ".NET $TBD (pin TargetFramework)" `
            '' '' $dotnetVerFile
    }
}

# ---------------------------------------------------------------------------
# Rust — Cargo.toml
# ---------------------------------------------------------------------------
if (Test-Path -LiteralPath (Join-Path2 $repo 'Cargo.toml') -PathType Leaf) {
    $appStacks.Add('rust')
    Add-Finding 'Rust' 'Cargo.toml' `
        'Rust: edition pinned, modules over files, Result/error-enum conventions, clippy clean' `
        "Rust $TBD (pin edition / toolchain)" `
        '' ''
}

# ---------------------------------------------------------------------------
# Claude Code plugin — skills/** + agents/** + hooks/**
# ---------------------------------------------------------------------------
$hasSkills = Test-Path -LiteralPath (Join-Path2 $repo 'skills') -PathType Container
$hasAgents = Test-Path -LiteralPath (Join-Path2 $repo 'agents') -PathType Container
$hasHooks  = Test-Path -LiteralPath (Join-Path2 $repo 'hooks')  -PathType Container
# Plugin manifest is a stronger signal; treat it as confirming the plugin stack.
if (Test-Path -LiteralPath (Join-Path2 $repo '.claude-plugin/plugin.json') -PathType Leaf) { $hasSkills = $true }
if ($hasSkills -and $hasAgents -and $hasHooks) {
    $appStacks.Add('plugin')
    Add-Finding 'Claude Code plugin' 'skills/+agents/+hooks/' `
        'Plugin: skill-per-capability, frontmatter triggers, cross-platform bash+pwsh hooks, no-BOM LF scripts' `
        "Claude Code plugin schema $TBD (pin .claude-plugin/plugin.json version)" `
        '["plugin-dev:*","superpowers:writing-skills"]' ''
}

# ---------------------------------------------------------------------------
# Resolve / emit
# ---------------------------------------------------------------------------
$uniqStacks = [System.Collections.Generic.List[string]]::new()
foreach ($s in $appStacks) {
    if ([string]::IsNullOrEmpty($s)) { continue }
    if (-not $uniqStacks.Contains($s)) { $uniqStacks.Add($s) }
}

# Header (always emitted). The 7th column (versionFile) is appended after flag.
[Console]::Out.WriteLine(('stack', 'signal', 'convention', 'manifestPin', 'domainSkills', 'flag', 'versionFile') -join $TAB)

if ($findings.Count -eq 0) {
    # None state: no recognizable stack signal at all. "none" is a valid value,
    # but the absence of ANY stack is something a human should confirm. No stack
    # means no version-file concept -> empty 7th column.
    [Console]::Out.WriteLine((
        'none', '(no stack signal)',
        "$FLAG no recognizable stack signal found — confirm this is intentional or supply the stack",
        'none', '', 'human', '') -join $TAB)
    exit 0
}

# Ambiguous primary: more than one distinct application stack present. The primary
# is unresolved, so no single version-file is asserted -> empty 7th column (the
# per-stack rows below still carry their own version-file paths).
if ($uniqStacks.Count -gt 1) {
    $joined = ($uniqStacks -join ',')
    [Console]::Out.WriteLine((
        '(multi-stack)', $joined,
        "$FLAG multiple application stacks detected — confirm the primary stack for the project",
        'n/a', '', 'human', '') -join $TAB)
}

foreach ($line in $findings) { [Console]::Out.WriteLine($line) }
exit 0
