# milestone-bootstrapper

Builds the **project's brain**: it gives Claude a solid, durable understanding of the project — its goal, design, high-level architecture, and specific technology choices (which SQL flavor, FastAPI vs Django, …) — and wires in the best-practice conventions for those choices, so every piece of work stays consistent in approach, organization, and results across the whole project lifecycle.

It does this by populating the [project-docs](../project-docs) (`.project/`) through an interview plus best-practice capture, then making the repo **suite-ready** (configs, labels, branches, branch protection, CI) so `milestone-feeder` and `milestone-driver` run immediately. The repo plumbing serves the understanding mission, not the other way around. It **records** the environment model; it never **provisions** infrastructure.

Surface: `plan` previews a reviewable plan; `apply` deploys it to a fresh repo; `update` reconciles a refreshed plan when the architecture, stack, or design changes (diff-first, non-destructive). The plan file is the spec; the populated `.project/` and the suite-ready repo are the deployment.

Status: **planning.** The build is specified as a feeder brief — [BRIEF.md](BRIEF.md) — meant to be handed to `/milestone-feeder:plan` to generate the build milestone (dogfooding: the suite builds itself). Part of the [dev-tools](../dev-tools) suite.
