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
> [TBD] — e.g. "Layered MVVM client; optimize for testability and offline-first reliability over raw throughput."

## Layering & boundaries
The layers and the allowed dependency directions — what may depend on what, and what must never.
> [TBD] — e.g. "View → ViewModel → Service → Repository. Views never touch Repositories. No layer reaches around its neighbor."

## What we optimize for
Ranked priorities, and the explicit non-goals that follow from them.
> [TBD] — e.g. "1) correctness, 2) maintainability, 3) performance. Non-goal: premature generalization (inline before abstracting)."

## One-way doors
Decisions that require human sign-off *before* they're made — irreversible or expensive-to-reverse choices.
> [TBD] — e.g. "Schema/migration changes; public API or contract changes; auth & payment paths; adding an external dependency."

## Error & failure philosophy
How the system handles and surfaces failure: fail-open vs fail-closed, the user-facing error policy, logging expectations.
> [TBD]

## Testing philosophy
What we test, at what level, and what "verified" means before a change is done.
> [TBD] — e.g. "Unit-test all logic; one E2E per user-visible flow; a bug fix starts with a failing test."
