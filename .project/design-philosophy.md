# Design philosophy

<!--
Part of your project docs (.project/). Tools read and cite this file as
`.project/design-philosophy.md#<section>`. Fill every [TBD]. A section left as
[TBD] is treated as "not specified" — tools fall back to inferred repo
convention rather than ground on a placeholder. Humans own this file; tools may
*propose* changes but never rewrite it. Keep the ## headings stable — they are
citation anchors. Add new sections by appending, not renaming.
-->

## Architectural stance
What kind of system is this, and what does it fundamentally optimize for?
> A Claude Code plugin that gives Claude a solid, durable understanding of the project — goal, design, architecture, and specific stack — and makes that understanding drive consistency across the whole project lifecycle, not just at setup. It records the environment; it never creates it. (Grounded in BRIEF.md:5-11, BRIEF.md:56-58.)

## Layering & boundaries
The layers and the allowed dependency directions — what may depend on what, and what must never.
> Three flagless verbs over component scripts: `plan` (preview only — writes one local plan file, nothing remote), `apply` (first deploy), `update` (diff-first reconcile). Skills orchestrate ordering and reporting only; each step is a thin invocation of the component script that owns its slice — skills never duplicate component logic. The plan file is the contract: `apply`/`update` read it and re-derive nothing. (Grounded in BRIEF.md:20-26, SPEC.md §1, skills/apply/SKILL.md non-negotiables.)

## What we optimize for
Ranked priorities, and the explicit non-goals that follow from them.
> 1) a durable, cited project understanding (the core); 2) suite-readiness so milestone-feeder and milestone-driver run immediately (supporting); 3) auditability. Explicit non-goals: provisioning or creating infrastructure (servers, databases, caches, secrets, deploy targets); application code of any kind; choosing the stack silently; non-GitHub CI providers (v1). (Grounded in BRIEF.md:15-18, BRIEF.md:71-76.)

## One-way doors
Decisions that require human sign-off *before* they're made — irreversible or expensive-to-reverse choices.
> Adding a dependency (a PAUSE, not an autonomous call); any change to the plan-file format / SPEC contract; any destructive repo action — the suite never deletes branches, force-pushes, or clobbers human-edited docs or configs. (Grounded in BRIEF.md:24, BRIEF.md:65.)

## Error & failure philosophy
How the system handles and surfaces failure: fail-open vs fail-closed, the user-facing error policy, logging expectations.
> Flag, don't guess: "None" / "not yet" are valid recorded answers; genuine unknowns stay `[TBD]` and flagged 🔴, never fabricated. The `gh` precondition is surfaced as a clear precondition message, never a silent failure. `apply` halts on a step failure, names the failed step, reports what was and wasn't written, and never rolls back. (Grounded in BRIEF.md:30, BRIEF.md:66, BRIEF.md:82, skills/apply/SKILL.md partial-failure path.)

## Testing philosophy
What we test, at what level, and what "verified" means before a change is done.
> Cross-platform twins (a bash `.sh` and a PowerShell 7+ `.ps1`) must stay behaviorally byte-equivalent; idempotency and non-destructiveness are verified by re-run (a re-run of an already-applied step is a true no-op). The suite dogfoods itself — it was written up as a brief, planned with milestone-feeder, and built by milestone-driver. (Grounded in CHANGELOG.md:77, README.md:76, BRIEF.md:65.)
