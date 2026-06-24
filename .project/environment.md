# Environment

<!--
Project doc (.project/). Cite as `.project/environment.md#<section>`. Declares what the
project's runtime and production environment looks like — the facts downstream tools ground
their data, test, and caching decisions in. It does NOT provision anything; it records the
model so issues don't drift. Fill every [TBD]; a section left [TBD] is treated as "not
specified." Humans own this file; tools propose, never rewrite. Keep the ## headings stable
— they are citation anchors.
-->

## Environments
Which environments exist (production, staging, test, local) and how they differ.
> None in the application sense — this is a developer-tools plugin, not a deployed service. It runs inside a developer's Claude Code session against a GitHub repo. (Grounded in BRIEF.md:56-58.)

## Data stores
Databases and other persistent stores: the engine(s), and the **topology** — separate prod / staging / test databases, or a shared one. **Test-data isolation:** how tests get a clean, isolated database (a dedicated test DB, a per-worker DB suffix, transactional rollback, truncate-on-start). This is the single biggest drift source if left unstated.
> None — the bootstrapper records the environment model; it never creates or owns a data store. Its only persistent outputs are the repo's own files (`.project/`, `.milestone-config/*`, `.github/workflows/`). (Grounded in BRIEF.md:56-58, BRIEF.md:69, BRIEF.md:73.)

## Caching
Whether caching exists and, if so, the layer and technology (in-memory, Redis, CDN), what is cached, and the invalidation policy. **"None" is a valid, drift-preventing answer** — record it explicitly.
> None — no cache layer. (Recorded explicitly; BRIEF.md:73 non-goals.)

## Async & messaging
Background jobs, queues, streams, schedulers — or "none."
> None — synchronous skill and script invocations only. (Grounded in BRIEF.md:20-26.)

## External services & integrations
Third-party services the app depends on: auth / identity, payments, email / SMS, object storage, analytics, other APIs.
> GitHub (via the `gh` CLI and the GitHub API) for labels, branches, branch protection, and CI registration; `git` for repo operations. Requires `gh` authenticated with repo scope, and repo-admin for branch protection. (Grounded in BRIEF.md:82, README.md:63-65.)

## Runtime & hosting
Where it runs and the runtime/version targets (hosting platform, language-runtime versions, regions). For mandated frameworks and packages, cross-reference `library-manifest.md`.
> Runs locally in a developer's Claude Code session; there is no hosting. Component scripts run on bash (with `jq`) or PowerShell 7+. (Grounded in README.md:66, BRIEF.md:81.)
