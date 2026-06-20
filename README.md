# milestone-bootstrapper

Give a repo a brain — a durable, written understanding of the project Claude can build against — and make it ready for the rest of the suite in one pass.

milestone-bootstrapper is a Claude Code plugin. It interviews you about your project — its goal, architecture, the specific stack, the conventions that follow from it, the environment model, and how you version — and writes that understanding into a set of standing docs under `.project/`. In the same pass it makes the repo **suite-ready**: configs, labels, a branch model, branch protection, and CI. With that in place, its siblings [`milestone-feeder`](https://github.com/kenmulford/milestone-feeder) and [`milestone-driver`](https://github.com/kenmulford/milestone-driver) plan and build every issue against your real conventions, not invented ones. It **records** your environment model; it never **provisions** infrastructure.

**Install it** — this also pulls in the required `superpowers` plugin. Restart Claude Code afterward so the plugins load:

```
/plugin marketplace add kenmulford/milestone-bootstrapper
/plugin install milestone-bootstrapper@milestone-bootstrapper
```

## Quick start

The whole tool is three commands — `plan` to preview, `apply` to deploy, and `update` when your project changes later. The loop:

1. **`plan` your project.** From inside the repo you want to bootstrap:

   ```
   /milestone-bootstrapper:plan
   ```

   It interviews you, detects your stack, inspects the repo, and writes a **plan file** you can read — every doc it would populate and every config, label, branch, and CI change it would make. It writes nothing to your repo, your settings, or GitHub yet.

2. **Read the plan.** Open the plan file it points you to and check what it captured and what it would change. This is your review — a genuine unknown it never guesses; it leaves it marked `[TBD]` and flags it 🔴 for you. Edit your answers and re-run `plan` if anything's off.

3. **`apply` it.** When the plan looks right, deploy it:

   ```
   /milestone-bootstrapper:apply
   ```

   It writes the captured understanding into your `.project/` docs, then makes the repo suite-ready — configs, labels, branch model, CI, and branch protection — in a safe order, each step idempotent.

4. **`update` when your project changes.** Adopted Redis, switched the ORM, changed the layering? Re-run `plan` to capture the new understanding, then sync it onto the repo you already bootstrapped:

   ```
   /milestone-bootstrapper:update
   ```

   It shows you the diff first, patches the configs that drifted, **proposes — never overwrites** — edits to docs you've hand-edited, and **flags** — never deletes — anything in your repo your plan no longer mentions. If nothing changed, it's a true no-op.

The very first time you run `plan` in a repo with no config, it sets up a small profile for you and then carries on — you don't re-run anything.

## Before you start

For us to populate your docs and make the repo suite-ready, a few things need to be in place. Each one below comes with what breaks if it's missing.

- **`gh` (the GitHub CLI) installed and signed in**, and you're working in a directory connected to a GitHub repository — otherwise `apply` and `update` can't create your branches, labels, branch protection, or CI.
- **`gh` with repo-admin rights on that repo** — branch protection is set through the GitHub API and needs admin. Without it, everything else still runs; we surface the protection step as needing admin rather than failing silently.
- **Claude allowed to run the commands** `apply` and `update` use:
  - `gh label create` — to provision the `ui` / `logic` / `risk:*` and driver labels.
  - `gh api` and `gh repo edit` — to create the branches, set the default branch, register the CI status checks, and assert branch protection.
  - **Write** under `.project/`, `.milestone-config/`, and `.github/workflows/` — to populate the docs, write the configs, and emit the CI workflow.
- **git.**
- **bash with `jq`** (or **PowerShell 7+**) — every step ships both a bash and a PowerShell 7+ twin, so the tool runs on either.

One thing worth knowing: **`plan` writes nothing.** It only interviews, reads, and detects — everything it produces is a local plan file you review. The writes above are what `apply` and `update` need — not `plan`.

## How it works

The understanding is the point; the repo plumbing serves it.

- **It populates your docs — it doesn't just scaffold them.** `plan` interviews you and detects your stack, then `apply` writes real, cited understanding into your `.project/` docs under fixed headings: your goal and architecture, the stack and the conventions that follow from it, the environment model, your versioning policy. A genuine unknown it leaves as `[TBD]` and flags for you — never a fabricated answer. A "none" you actually gave (no caching, say) is recorded as a real decision, distinct from an unknown. Those populated docs are what `milestone-feeder` and `milestone-driver` ground every issue and every line of code in.
- **It makes the repo suite-ready in one safe pass.** From the same plan, `apply` writes the `milestone-driver` and `milestone-feeder` configs (including the stack-specific skills the driver should cite), provisions the label taxonomy both siblings expect, creates your integration and protected branches, emits a CI workflow that gates pull requests, and asserts branch protection on top of it — in that order, because each step depends on the one before.

The plan file is the spec; the populated `.project/` and the suite-ready repo are the deployment. That's why preview is the default — these are consequential, long-lived decisions that deserve a read before anything is written.

`update` is how that understanding stays true as the project moves. It's **diff-first and non-destructive**: it shows you the change before writing, patches a drifted config while preserving every key it didn't touch, proposes — never overwrites — a doc you've edited by hand, and flags — never deletes — anything live that your refreshed plan no longer mentions. A fully-synced repo is a true no-op.

## Config

Configuration is **optional** — the first `plan` run writes a small profile for you, and every setting has a sensible default. The bootstrapper's own settings live in `.milestone-config/`, the same folder `milestone-driver` and `milestone-feeder` read from. The settings it *writes for you* — your branch model, source paths, UI-surface paths, stack-specific skills, and versioning policy — are exactly what those siblings consume, so you set them once here and the whole suite runs.

## Status

**v1 — built.** The plugin is complete: `plan` / `apply` / `update`, the understanding-interview and `.project/` population, and the suite-readiness provisioners (configs, labels, branch model, CI, protection). Self-hosted: the bootstrapper was specified as a feeder brief, planned with `milestone-feeder`, and built by `milestone-driver` — the suite built itself. Part of a dev-tools suite with [`milestone-feeder`](https://github.com/kenmulford/milestone-feeder) and [`milestone-driver`](https://github.com/kenmulford/milestone-driver).

## Docs

- [SPEC.md](SPEC.md): the plan-file format — the contract `plan` writes and `apply` / `update` read.
- [docs/understanding-interview.md](docs/understanding-interview.md): how the understanding interview captures and records each field.
- [BRIEF.md](BRIEF.md): the original brief the suite built this plugin from.

## License

[MIT](LICENSE).
