# Library manifest

<!--
Project doc (.project/). Cite as `.project/library-manifest.md#<section>`. The
implementer's "new dependency = PAUSE" gate reads this; the coherence-reviewer
flags a new library that duplicates one listed here. Keep it current. Keep ##
headings stable — they are citation anchors.
-->

## Runtime & frameworks
The platform/runtime and primary frameworks, with versions. (Mirror these into milestone-driver `nonNegotiables` where they're hard constraints.)
> [TBD] — e.g. ".NET 10 MAUI + Community Toolkit; iOS 26.5 / Android API 36."

## Approved libraries (by purpose)
One approved choice per purpose, so a redundant alternative is easy to spot.

| Purpose | Library | Notes |
|---|---|---|
| [TBD] (e.g. dates) | [TBD] | [TBD] |
| [TBD] (e.g. HTTP) | [TBD] | [TBD] |
| [TBD] (e.g. DI) | [TBD] | [TBD] |

## Adding a dependency (the gate)
A new dependency is a PAUSE, not an autonomous call. Record what it buys, its license / OSS status, and why nothing approved suffices; a human approves before it's added.
> [TBD] — where proposals go (e.g. "open an issue labeled `needs decision`").

## Avoid / banned
Libraries explicitly not to use, and why.
> [TBD]
