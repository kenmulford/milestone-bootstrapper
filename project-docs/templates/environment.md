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
> [TBD] — e.g. "prod + staging on managed hosting; an ephemeral CI test env; local via docker-compose."

## Data stores
Databases and other persistent stores: the engine(s), and the **topology** — separate prod / staging / test databases, or a shared one. **Test-data isolation:** how tests get a clean, isolated database (a dedicated test DB, a per-worker DB suffix, transactional rollback, truncate-on-start). This is the single biggest drift source if left unstated.
> [TBD] — e.g. "Postgres; separate prod/staging/test databases; tests use a per-worker DB (parallel_tests `TEST_ENV_NUMBER` suffix)."

## Caching
Whether caching exists and, if so, the layer and technology (in-memory, Redis, CDN), what is cached, and the invalidation policy. **"None" is a valid, drift-preventing answer** — record it explicitly.
> [TBD]

## Async & messaging
Background jobs, queues, streams, schedulers — or "none."
> [TBD]

## External services & integrations
Third-party services the app depends on: auth / identity, payments, email / SMS, object storage, analytics, other APIs.
> [TBD]

## Runtime & hosting
Where it runs and the runtime/version targets (hosting platform, language-runtime versions, regions). For mandated frameworks and packages, cross-reference `library-manifest.md`.
> [TBD]

## Deployment targets
Where the app is **deployed** — the hosting vendor / platform / target (Cloudflare, AWS, Azure, Vercel, Netlify, Fly.io, a self-managed host). **Records** the deploy destination; it does **not** provision it. Boundary vs `## Runtime & hosting`: that anchor is the runtime/version targets and regions the app *needs*; this anchor is *where it is deployed to* and who hosts it.
> [TBD] — e.g. "Cloudflare Workers + Pages (prod); Vercel preview deploy per PR."
