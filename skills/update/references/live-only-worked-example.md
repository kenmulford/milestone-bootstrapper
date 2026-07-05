# Live-only worked example — a dropped stack, preserved through the union write

Referenced from `skills/update/SKILL.md` Step 5. This walks the live-only flag through a concrete scenario end to end: a config key that disappears from the refreshed plan and a project-doc section that disappears alongside it, both flagged 🔴 and neither one deleted.

**Worked example — live-only flag, preserved through the union write (the triage Advisory's un-exercised path, made first-class).**

The team **dropped a stack** between bootstraps: the last `apply` wired `driver.json#domainSkills = ["fastapi-skills", "pytest-skills"]` and a live `.project/conventions.md#Test patterns` section describing pytest fixtures. The refreshed plan (after re-running `plan`) reflects a migration **off** pytest — its §B Configs now records `domainSkills = ["fastapi-skills"]` and its §A `conventions.md` no longer carries the pytest test-patterns content. (Say the same run also patches another driver.json key — e.g. `versioning` — so the writer *does* run.)

Because `write-driver-config` rewrites the whole file from the keys passed, `update` does **not** simply skip the key — that would let the rewrite drop it. Instead `update` keeps `pytest-skills` alive by **passing the live `domainSkills = ["fastapi-skills", "pytest-skills"]` value back in the union write** (alongside the patched `versioning`), so the rewritten file still carries it. It does **NOT** delete the live `conventions.md#Test patterns` section (project docs are propose-only, never rewritten). Then it reports:

```
🔴 Live-only (flagged for your decision — update preserved these in place, did not remove them):
  - driver.json#domainSkills: "pytest-skills" present live, absent from the refreshed plan — passed back in the union write, so it survives; flagged for you to decide.
  - .project/conventions.md#Test patterns: human-authored content present live, absent from the refreshed plan — not rewritten.
These were in your repo but not in the refreshed plan. Remove them yourself if intended — update never deletes.
```

The human decides whether the drop is real (then removes them by hand) or a plan omission (then re-runs `plan` to re-capture them). `update` parks the decision; the live-only key **survives the rewrite precisely because `update` passes it back in** — it is flagged for the human, never deleted, and never silently clobbered by the whole-file rewrite.
