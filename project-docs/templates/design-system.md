# Design system

<!--
Project doc (.project/). Cite as `.project/design-system.md#<section>`. Machine-readable
design tokens live in `tokens.json` alongside this file. Absent or all-[TBD] →
no design-lens grounding (design-reviewer / coherence-reviewer / wireframing
skip it). Skip this file entirely for repos with no UI surface. Keep ## headings
stable — they are citation anchors.
-->

## Design tokens
Canonical color, type, spacing, and radius scales. Source of truth is `tokens.json`; describe intent and usage here.
> [TBD] — e.g. "Brand primary for primary actions only; never for body text. Spacing on a 4px rhythm."

## Component inventory
The canonical components and where they live. New UI reuses these before introducing a one-off.

| Component | Location | Use for |
|---|---|---|
| [TBD] | [TBD path] | [TBD] |

## Layout & responsive rules
Grid, breakpoints, spacing rhythm, density.
> [TBD]

## Required states
Every interactive surface must handle these explicitly.
- **Empty:** [TBD]
- **Loading:** [TBD]
- **Error:** [TBD]
- **Disabled:** [TBD]

## Accessibility baseline
The standard you hold, plus contrast, focus, target size, and semantics expectations.
> [TBD] — e.g. "WCAG 2.2 AA; visible focus on all interactive elements; min 44px touch targets."

## Voice & microcopy
Tone for labels, errors, and empty states.
> [TBD]
