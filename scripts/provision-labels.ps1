#!/usr/bin/env pwsh
#
# provision-labels.ps1 — provision the suite's label taxonomy idempotently.
#
# What this does, in plain terms:
#   The `apply` and `update` verbs call this to guarantee that every label
#   milestone-driver and milestone-feeder rely on already exists in the target
#   GitHub repo, so both downstream tools run with no further label setup. It
#   creates the ten labels (six from the driver, four from the feeder) if they
#   are missing, and upserts color + description if they already exist — so a
#   re-run never produces duplicates and corrects any drifted color/description.
#
# Why provision in-house (not by invoking the sibling setup skills):
#   milestone-driver:setup and milestone-feeder:setup also write config and run
#   an interview, so invoking them solely for labels is the wrong tool. We reuse
#   the canonical `gh label create --force` idiom and the exact taxonomy values
#   those skills own — never a second, drifting definition. (BRIEF.md §"Job 2"
#   line 52, §"Recorded design decisions" line 68.)
#
# Taxonomy source of truth (verbatim):
#   Driver slice — milestone-driver/skills/setup/SKILL.md:178-186, :205-211
#   Feeder slice — milestone-feeder/skills/setup/SKILL.md:95-100,  :107-110
#
# Preconditions:
#   `gh` installed and authenticated, run inside a GitHub-connected working
#   directory. If a precondition is unmet, this names it and exits non-zero
#   before touching any label — never a silent failure (BRIEF.md §"Constraints"
#   line 82). Cross-platform companion: provision-labels.sh.

$ErrorActionPreference = 'Stop'

function Fail([string]$message) {
    [Console]::Error.WriteLine("milestone-bootstrapper: $message")
    exit 1
}

# --- Preconditions (surface the unmet one by name; provision nothing) --------
# `gh` reports failure via a non-zero exit code, not a thrown exception, so each
# check inspects $LASTEXITCODE. A missing `gh` raises a command-not-found error,
# caught and reported as the installation precondition.

try { gh --version *> $null } catch {
    Fail "GitHub CLI ('gh') is not installed or not on PATH. Install it from https://cli.github.com, then re-run."
}

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "GitHub CLI is not authenticated. Run 'gh auth login' (with a token that can manage labels), then re-run."
}

gh repo view *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "the working directory is not connected to a GitHub repository (or the repo is unreachable). Run this inside a repo with a GitHub remote, then re-run."
}

# --- Legacy reconcile (runs FIRST, before the bulk block) --------------------
# A legacy 'judgment-call' / '⚠ judgment-call' label may predate the canonical
# 'judgment call' name. Renaming it here preserves all existing issue/PR
# associations before the upsert block re-asserts its color/description. If
# neither legacy name exists the edit errors harmlessly — tolerated, not fatal.
# The try/catch is the PowerShell twin of bash's `|| true`: under
# $ErrorActionPreference = 'Stop' (and PowerShell 7.4+, where
# PSNativeCommandErrorActionPreference is on by default) a non-zero native exit
# raises a terminating error, so an absent legacy label would abort the whole
# script before any label is created. Swallowing it keeps the upsert block
# below running on a fresh repo.
# Reference: milestone-driver/skills/setup/SKILL.md:189-198.
try { gh label edit "judgment-call"   --name "judgment call" --color FBCA04 *> $null } catch { }
try { gh label edit "⚠ judgment-call" --name "judgment call" --color FBCA04 *> $null } catch { }

# --- Idempotent upsert: ten labels as a flat list (no shell loop) ------------
# `--force` creates the label if absent and updates color/description if it
# already exists; re-runs produce no duplicates. A flat list keeps these calls
# identical to the bash companion and portable across platforms.

# Driver slice (6) — milestone-driver/skills/setup/SKILL.md:205-211
gh label create "in progress"    --color 1D76DB --description "Branch open with partial or parked work; not yet done" --force
gh label create "blocked"        --color B60205 --description "Can't proceed; waiting on something external (unmerged dependency, unverified E2E)" --force
gh label create "needs design"   --color 5319E7 --description "Design direction required before building" --force
gh label create "needs decision" --color D93F0B --description "Non-design human decision required" --force
gh label create "needs review"   --color 0E8A16 --description "Built; awaiting human review/merge (e.g. a UI PR awaiting visual sign-off)" --force
gh label create "judgment call"  --color FBCA04 --description "Borderline autonomous call — audit post-run" --force

# Feeder slice (4) — milestone-feeder/skills/setup/SKILL.md:107-110
gh label create "ui"             --color 5319E7 --description "UI-surface issue (design review applies)" --force
gh label create "logic"          --color 0E8A16 --description "Logic / non-UI issue" --force
gh label create "risk:light"     --color C2E0C6 --description "Reduced-ceremony build profile (driver override)" --force
gh label create "risk:heavy"     --color B60205 --description "Full-ceremony build profile (driver override)" --force

Write-Output "milestone-bootstrapper: provisioned 10 labels (6 driver + 4 feeder)."
