# milestone-bootstrapper — feeder brief

> **How to use this doc.** This is a feature brief for `milestone-feeder`. Run `/milestone-feeder:plan BRIEF.md` in this repo; the feeder will decompose it into a milestone of small, well-formed issues, which `milestone-driver` then builds. It is written as *intent + recorded decisions* so the feeder grounds its issues rather than parking them — it is deliberately **not** pre-broken into issues (that is the feeder's job).

## What it is — the project's brain

`milestone-bootstrapper` exists to give Claude a **solid, durable understanding of the project** — its goal, its design, its high-level architecture, and its specific technology choices — and to make that understanding drive **consistency in approach, organization, and results across the entire project lifecycle**, not just at setup time.

It cares which flavor of SQL you use. It cares whether you're on FastAPI or Django, and it ensures the code Claude writes adheres to that choice's best practices. Above all, it gives Claude **everything it needs, throughout the whole project, to stay consistent** — so the hundredth issue is built with the same understanding as the first.

The mechanism: it builds out the project's [**project-docs**](../project-docs) (the brain) through an interview plus best-practice capture, then `milestone-feeder` and `milestone-driver` ground every issue and every line of code in them. It *also* makes the repo suite-ready (configs, labels, branches, CI) so the rest of the chain runs — but that plumbing is **in service of** the understanding mission, not the point of it.

Same design DNA as its siblings: single purpose, detection + a short interview, gated by a preview-then-execute split, flag-don't-guess autonomy, composable, auditable.

## The two jobs (in priority order)

1. **Establish the project's understanding — the core.** Capture the goal, architecture, stack, conventions, and environment into the project docs, with stack-specific best practices wired in, so all downstream work is consistent.
2. **Make the repo suite-ready — supporting.** Provision the configs, labels, branch model, branch protection, and CI so `milestone-feeder` and `milestone-driver` run immediately.

## The surface (three verbs, no flags)

- **`plan`** — interview the human, inspect the repo, detect the stack, and write a reviewable **provisioning plan file** describing everything it would record and change. Writes nothing to the repo's settings, remote, or GitHub.
- **`apply`** — execute the approved plan on a fresh repo: write the project docs, the configs, the labels, the branches, the protection, and the CI.
- **`update`** — the over-the-life path. When the architecture, stack, or design changes, re-run `plan` against the change, then `update` reconciles the refreshed plan onto the already-bootstrapped repo: it diffs against the existing docs/configs, patches what changed (showing the diff first), adds what's new (e.g. a newly-adopted framework → its conventions + `domainSkills`), and **proposes** edits to human-owned docs rather than overwriting them. Never destructive; a true no-op when nothing changed.

This mirrors the feeder's `plan` / `create` / `update` shape — here the deploy verb is `apply` (the bootstrapper deploys settings + docs, not issues). The architecture-changed path is first-class: `update` is exactly the trigger for "we adopted Redis," "we switched the ORM," "the layering changed." Mental model: **the plan file is the spec; the populated `.project/` and the suite-ready repo are the deployment.** Preview is the default because these are consequential, long-lived decisions that deserve a human read.

## Job 1 — establish the project's understanding (the core capability)

An interview that captures, and records into the project docs, what Claude must know to work consistently. "None" / "not yet" are valid recorded answers; genuine unknowns stay `[TBD]` and flagged, never fabricated.

- **Goal & vision** — what the project is for and what it optimizes for. → `design-philosophy.md`.
- **High-level architecture** — the architectural stance, layering, and boundaries. → `design-philosophy.md`.
- **The technology stack — specifically.** Language and version; framework (e.g. **FastAPI vs Django**); the **SQL flavor** (Postgres vs MySQL vs SQLite vs SQL Server) and ORM; major libraries. → `library-manifest.md` + `environment.md`.
- **Best-practice adherence for each major choice (load-bearing).** Capturing "FastAPI" is not just a label — record the conventions that *follow* from it (e.g. Pydantic models, dependency-injection pattern, async I/O, router/layout structure) into `conventions.md`, pin the framework + version in `library-manifest.md`, and **wire the driver's `domainSkills`** to any stack-specific skill so `milestone-driver`'s implementer cites authoritative best practices rather than improvising. The test: code built later should conform to the chosen stack's idioms because the docs told it how.
- **The environment model** — data stores and their topology (separate vs shared prod/test/staging) and the **test-data isolation strategy**; caching (tech + invalidation, or "none"); async/messaging; external services. → `environment.md`.
- **Mandated packages** — libraries/tooling the developer requires by purpose (pagination, ORM, lint/format, framework), distinct from what detection finds. → `library-manifest.md`.
- **Versioning policy.** Does the project follow semantic versioning? If so, **where the version lives** (`pyproject.toml`, `package.json`, `*.csproj`, a `VERSION` file) and the **bump cadence**. → record in `conventions.md` and set the driver's `versioning` key. This is the "client answers once, downstream automates" lever: with it set, `milestone-driver` applies the per-PR bump and `milestone-feeder` names milestones as versions so the driver can derive the target. (Caveat to record: the driver's bump target is `.claude-plugin/plugin.json` today; a non-plugin repo's version file may need the driver's target generalized — flag it.)
- **Design system** — tokens, components, layout, required states (UI projects only). → `design-system.md` + `tokens.json`.

The output of Job 1 is a **populated** `.project/` — not just scaffolded placeholders, but the real, cited understanding that every later tool and Claude action grounds in. That population is the whole consistency mechanism.

## Job 2 — make the repo suite-ready (supporting capability)

So the feeder and driver run with no further setup:

- **Configs** — `.milestone-config/driver.json` (branches, `sourceGlobs`, `uiSurfaceGlobs`, `unitTestCmd`, `preflightCmd`, `e2eEnv`, **`domainSkills`** from the stack capture, **`versioning`** from the versioning policy) and `feeder.json` (`projectDocs`, `reviewer`); minimal, only non-default keys.
- **Label taxonomy** — create-if-missing the suite's label taxonomy (the authoritative set is `SPEC.md` §6.3).
- **Branch model** — create the integration and protected branches if missing; set the default-branch policy.
- **Branch protection** — on the protected branch: no direct push, PR required, CI status check required (and optionally a review). Via the GitHub API.
- **CI workflow** — a GitHub Actions workflow running the detected `unitTestCmd` / `preflightCmd` on PRs into the integration branch, registered as the required status check.
- **Composability** — where `milestone-driver:setup` and `milestone-feeder:setup` are installed, call them for the config/label slices they own rather than duplicating; the bootstrapper wraps them with the understanding interview, branch model, protection, and CI.
- **Plugin scaffold** — its own `.claude-plugin/plugin.json` + `marketplace.json`, the `superpowers` dependency if needed, repo hygiene.
- **`apply` / `update` orchestration + idempotency** — execute in a safe order; `update` reconciles a changed plan onto an existing repo, and re-runs never clobber human-edited docs or configs.

## Knowing vs creating the environment (the key distinction)

The bootstrapper **records** what the environment is; it never **creates** it. Standing up a database, a Redis instance, secrets, or a deploy target is out of scope (the environment may not even exist yet). Declaring "prod and test use separate databases, tests use a per-worker DB" is exactly in scope — that declaration is what stops downstream issues from drifting. "We don't provision the database" and "we must record the database topology" are both true and not in tension.

## Recorded design decisions (grounding — so the feeder doesn't invent these)

- **The understanding layer is the primary purpose;** repo plumbing is secondary and serves it.
- **Best-practice adherence is wired, not hoped for:** stack choices flow into `conventions.md` + `library-manifest.md` and the driver's `domainSkills`, so the implementer grounds and cites them.
- **Verbs `plan` / `apply` / `update`, no flags;** the plan file is the contract; preview by default. `apply` is the first deploy; `update` reconciles architecture/stack/design changes over the project's life (mirrors the feeder's `plan`/`create`/`update`).
- **Idempotent and non-destructive:** never delete branches, force-push, or clobber human-edited docs/configs; re-asserting protection to match the plan is allowed.
- **Populate, don't just scaffold:** Job 1 writes real captured understanding into the docs; only genuine unknowns remain `[TBD]` + flagged.
- **GitHub Actions** is the first (and only v1) CI provider. **Adopt-or-init:** works on an existing or a fresh repo.
- **Reuse the setup skills** where present; never keep a second, drifting definition of the profiles/labels they own.
- **No persistent bootstrapper config** — one-shot; its inputs are the repo + the interview, its outputs are the project docs + the other tools' configs.

## Non-goals (what it refuses)

- **Provisioning or creating** infrastructure: standing up servers, databases, caches, secrets, or deploy targets. (It *records* the environment model; it does not build it.)
- Application code of any kind.
- Choosing the stack for you silently (it detects and interviews, then confirms).
- Non-GitHub CI providers (v1).

## Constraints / non-negotiables

- Honor the suite DNA and the shared output style (concise, tabular, mark anything needing a human with 🔴).
- Any hooks must be cross-platform (bash-first / PowerShell-7 fallback).
- Requires `gh` authenticated with sufficient scope (branch protection needs repo-admin); surface this as a precondition with a clear message, never a silent failure.
- Project docs and configs stay minimal and human-readable — capture what aids consistency, not ceremony.

## Sequencing hints (for the architect's wave order)

- Plugin scaffold is foundational and can land first.
- Job 1 (the understanding interview + project-docs population, incl. best-practice/`domainSkills` capture) is the spine and precedes the config writes that depend on it (e.g. `domainSkills` in `driver.json`).
- `plan` (interview + inspection + plan-file) precedes any `apply` / `update` write.
- Within `apply`: low-risk writes first (docs, configs, labels), then consequential writes (branch model → branch protection → CI, since protection depends on the CI check existing).
- Composability wiring depends on the config/label steps.

## Definition of done

A repo where Claude has, in `.project/`, a **solid, cited understanding** of the project's goal, architecture, specific stack, and best practices — enough that `milestone-feeder` and `milestone-driver` produce consistent, idiomatic work without re-deciding fundamentals — **and** the repo is suite-ready: branches and protection in place, CI wired and required, configs (incl. `domainSkills`) and labels present. Only genuinely-unknown facts remain as flagged `[TBD]`.
