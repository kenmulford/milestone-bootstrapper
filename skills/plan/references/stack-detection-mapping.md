# Stack-detection column mapping

Referenced from: `skills/plan/SKILL.md` Step 2 ("Resolve the app-roots from the
layout, then detect the stack").

The detector emits TSV per run: a header then one finding per stack — columns
`stack  signal  convention  manifestPin  domainSkills  flag  versionFile`.
Consume each finding (across the union) as the **seed** for the interview's
stack-derived defaults and for the plan's recorded entries:

- `convention` → seeds the best-practice convention note (→ `conventions.md` anchors).
- `manifestPin` → seeds the framework + version pin (→ `library-manifest.md#Runtime & frameworks`).
- `domainSkills` → the `driver.json#domainSkills` candidate (a JSON-array literal, or **empty** for an unmapped stack — the detector omits rather than fabricates; an empty field stays a recorded "none", never an invented skill).
- `stack` (the **descriptive** column value) → the `driver.json#stack` **enum** (`node|python|dotnet|maui|rust|plugin|none`). Map the detector's descriptive label to the enum by this fixed table — key on the literal `stack`-column value:

  | detector `stack` column | `driver.json#stack` enum |
  |---|---|
  | `Node (generic)` | `node` |
  | `Angular (Node)` | `node` |
  | `Next.js (Node)` | `node` |
  | `React (Node)` | `node` |
  | `Vue (Node)` | `node` |
  | `Svelte (Node)` | `node` |
  | `Node ([TBD])` (malformed package.json) | `node` |
  | `Python (<framework>)` (e.g. `Python (FastAPI)`, `Python (Django)`, `Python (Flask)`) | `python` |
  | `Python` (framework unresolved, flagged) | `python` |
  | `.NET (non-MAUI)` | `dotnet` |
  | `.NET MAUI` | `maui` |
  | `Rust` | `rust` |
  | `Claude Code plugin` | `plugin` |
  | `none` | `none` |
  | `(multi-stack)` | **not mapped** — this is the existing `flag = human` ambiguous-primary row; the human confirms the primary stack (the per-stack rows below it still map individually). |

- `versionFile` → the `driver.json#stackVersionFile` candidate — the version-file PATH the detector actually found (e.g. `.nvmrc`, `.node-version`, `.python-version`, `global.json`), or **empty** when no such file exists or the stack has no version-file concept. It is a PATH, never a resolved concrete version (setup-* actions read the version from the file on the runner). Empty stays a recorded "none", never a fabricated path.
- `flag` = the literal `human` → carry that finding into the plan as a `[TBD]` 🔴 (e.g. no recognizable stack signal, an ambiguous primary stack, an unresolved framework). Detection's flagged unknowns are the genuine unknowns — they stay `[TBD]` 🔴, never guessed.

(The resolved-wins rule — detection seeds the default, the interview's
confirmed/edited answer is what reaches the plan — is stated inline in
`SKILL.md` Step 2, immediately after the pointer to this file.)
