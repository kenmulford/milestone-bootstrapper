# Brief: audit remediation — milestone-bootstrapper

**Goal.** Close the accuracy, flexibility, and token-efficiency gaps found in the 2026-07-05 suite audit, and give apply/update the act→verify→retry loop shape so provisioning failures are caught at write time instead of downstream. Every item below cites the evidence it came from; nothing here changes the plugin's core contract (plan-file-as-interface, preview-then-execute, never-delete, idempotent-by-construction) — several items exist specifically to protect that contract.

**Constraints to hold across all items:**
- The plan file remains the single contract; apply/update deploy exactly what it records and never re-derive.
- All shell must run correctly under macOS system bash 3.2 (no `${var,,}`, no bash-4-isms) — the user-level audit found `${var,,}` silently disabled two hooks on macOS.
- Keep the three-state captured/none/[TBD] vocabulary exactly as SPEC.md defines it.

---

## 1. SPEC.md is missing config-catalog.md — the format contract omits a doc the pipeline produces

**Evidence:** SPEC.md §5 (lines ~214–229) enumerates 6 project docs; config-catalog.md is absent. But docs/understanding-interview.md Tier 8, skills/plan/SKILL.md (Step 1 tier table + Step 4 mapping), docs/write-project-docs.md, and project-docs/SPEC.md §6 all treat config-catalog.md as a live 7th doc with 7 anchors — shipped in v0.4.0 (#76/#87).

**Work:** Add config-catalog.md as a 7th row to SPEC.md §5 (default update reconcile class, human-owned), and update the worked plan-file skeleton in §8 to include it.

**Acceptance:** SPEC.md §5, §8, docs/understanding-interview.md Tier 8, and project-docs/SPEC.md §6 name the same 7 docs with the same anchors; a fresh `plan` run's output matches the §8 skeleton.

## 2. Rails/Ruby stack detection

**Evidence:** scripts/detect-stack.sh has blocks for Python, Node (+framework discrimination), .NET/MAUI, Rust, and the plugin signal — no Gemfile/Ruby block. scripts/write-driver-config.sh:246 hardcodes the enum `node|python|dotnet|maui|rust|plugin|none`. A Rails repo — the author's primary stack — detects as `none`: no domainSkills, no framework pin, an all-[TBD] library-manifest.md.

**Work:** Add a Gemfile detection block mirroring the Python block's grep-based framework discrimination (rails gem → Rails; otherwise plain Ruby), extend the stack enum, and map sensible domainSkills defaults (e.g. ruby-lsp, superpowers TDD/debugging per the author's standing skill table).

**Acceptance:** a fixture repo with a Gemfile containing `gem "rails"` detects with the new stack value, a framework pin, and a non-[TBD] library manifest; a Gemfile without rails detects as plain Ruby; existing stacks' detection is unchanged (run the existing detector against current fixtures).

## 3. Pin the plan-file slug length — one number, one home

**Evidence:** the slug is the identity mechanism for staleness detection (SPEC.md §3), but its length is specified only as "a reasonable bound" in SPEC.md:92, skills/plan/SKILL.md:197, skills/apply/SKILL.md:53, and skills/update/SKILL.md:76 — four independent re-derivations that only coincidentally agree.

**Work:** Pin an exact character cap in SPEC.md §2.2 (60 is conventional) as the single source of truth; the three skills reference SPEC §2.2 instead of restating the algorithm's bound in prose.

**Acceptance:** exactly one numeric bound exists in the repo; grep for "reasonable bound" returns nothing.

## 4. Progressive disclosure: split the three SKILL.md monoliths

**Evidence:** plan 5,299 words / apply 4,429 / update 6,420, fully inline, no references/ anywhere in the repo. Large chunks (the full worked plan-file skeleton, per-flag CLI tables, update's Step-4(2) config union-write walkthrough ~800 words) load on every invocation but are needed only on specific branches.

**Work:** Create references/ per skill; move worked examples and branch-specific walkthroughs there, loaded only when that path fires. Target each SKILL.md body under ~2,500 words of always-needed procedure.

**Acceptance:** `wc -w` on each SKILL.md ≤ 2,500; every moved chunk is referenced at exactly the step that needs it; a plain happy-path run of each skill never needs the references.

## 5. Read-back verify loop in apply's six-step deploy

**Evidence:** skills/apply/SKILL.md Step 3 invokes the six component scripts linearly and assumes success unless a non-zero exit. GitHub's API can accept a write (exit 0) that doesn't stick (a known eventual-consistency quirk for branch-protection rules); today that's discovered when milestone-driver's first PR fails a required check.

**Work:** After each remote-writing step (labels, branches, CI, protection), do a cheap read-back against the just-asserted state (`gh label list`, `gh api repos/<r>/branches/<b>/protection`) and retry once on mismatch before halting with the exact diverged step named.

**Acceptance:** apply's SKILL.md documents a verify-per-step; a simulated mismatch (fixture) produces one retry then a halt naming the step; a clean run adds at most one read call per write step.

## 6. Entry-level resumability for update

**Evidence:** update walks every §A/§B entry in one continuous pass and narrates no-op rows; apply has a step-level resume story but update claims none at the entry level (skills/update/SKILL.md Step 4).

**Work:** Compute a worklist of only add/patch entries first (skip no-ops from the narrative entirely), persist per-entry status to a scratch state file (e.g. `.milestone-bootstrapper/update-state-<slug>.json`), mark each entry done as it lands; an interrupted update resumes from the first not-done entry.

**Acceptance:** re-running update after a simulated mid-run interruption skips completed entries; an all-no-op repo produces a one-line "nothing to reconcile" instead of a row-by-row narrative.

## 7. Small honesty/usability fixes (one PR)

- README "Before you start": add one sentence stating branch protection's default floor is PR+CI with **0 required human approvals** (provision-protection.sh:30-33) so nobody assumes peer review is enforced.
- Surface update's documented can't-collapse-feeder.json-to-{} consequence (skills/update/SKILL.md:158) in the skill's Non-negotiables/Announce block instead of mid-Step-4.
- Scope apply's resume claim (skills/apply/SKILL.md:235) to "as long as every component script remains independently idempotent" so a future script edit doesn't silently void a repo-wide guarantee no test checks.

**Acceptance:** each of the three texts present at the named location; no other prose contradicts them.

## 8. CI size budgets — the loop that prevents regrowth

**Evidence:** the sibling feeder repo set a SKILL.md size standard in writing, trimmed once, and regrew to 3.4x the target because nothing enforced it. This repo currently has no size gate either.

**Work:** Add a CI step (simple script) that fails when any SKILL.md exceeds its word ceiling (per item 4) or any frontmatter description exceeds ~200 words.

**Acceptance:** CI red when a fixture oversized file is introduced; green on current post-item-4 tree.

---

**Out of scope:** multi-forge (GitLab/etc.) support; configurable label taxonomy / branch models (document as fixed assumptions only if a docs pass happens anyway); any change to the plan-file three-state vocabulary.

**Build-order hint:** items 1–3 and 7 are independent doc/script fixes (wave 1); item 4 before item 8 (the budget check needs the post-split ceilings); items 5–6 independent of the rest (wave 2).
