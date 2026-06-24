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
> None — not applicable. This repo has no UI surface (a Claude Code plugin: markdown skills + shell-script twins), so there is no design-lens grounding to capture. (Grounded in BRIEF.md:39, BRIEF.md:75.)

## Component inventory
The canonical components and where they live. New UI reuses these before introducing a one-off.

| Component | Location | Use for |
|---|---|---|
| [TBD] | [TBD path] | [TBD] |

## Layout & responsive rules
Grid, breakpoints, spacing rhythm, density.
> None — not applicable (no UI surface).

## Required states
Every interactive surface must handle these explicitly.
- **Empty:** [TBD]
- **Loading:** [TBD]
- **Error:** [TBD]
- **Disabled:** [TBD]

## Accessibility baseline
The standard you hold, plus contrast, focus, target size, and semantics expectations.
> None — not applicable (no UI surface).

## Voice & microcopy
Tone for labels, errors, and empty states.
> None — not applicable (no UI surface). The suite's user-facing tone is governed by the shared concise/tabular output style in BRIEF.md:80, not a design system.
