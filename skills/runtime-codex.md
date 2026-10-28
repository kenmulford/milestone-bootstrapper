# Runtime mapping: Codex

Skill text names Claude Code tools and commands. On Codex, use the counterpart below. Every other step runs unchanged on both runtimes.

| Claude Code | Codex |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | The plugin root: the parent of the `skills/` directory that holds the running `SKILL.md` (`<root>/skills/<name>/SKILL.md`), the directory that contains `scripts/`. Substitute the absolute path before running a command. |
| `/milestone-bootstrapper:<skill>` | `$milestone-bootstrapper:<skill>` mention, e.g. `$milestone-bootstrapper:apply`. Codex lists plugin skills under the plugin prefix, and bare `$plan` / `$update` also match milestone-feeder's skills. |
| Asking the user a question | `request_user_input` or `request_user_input_async`, whichever is listed for the turn, one question per call. Neither listed: ask in chat and end the turn. Ask only where a skill step says to ask, never about product gaps. |

## Human gates fail closed

These steps need a human answer before the skill continues:

| Skill | Gate |
|---|---|
| `plan` | `### Step 2 — Resolve the app-roots from the layout`: confirm nested app-roots. `references/stack-detection-mapping.md` `(multi-stack)` row: confirm the primary stack. |
| `update` | `#### Step 4 (1) — Project docs (§A)`: accept a PROPOSED `human-owned` doc edit before writing it. |
| `apply`, `check` | None. `apply` deploys the plan already approved. `check` writes nothing. |

On Codex, when neither `request_user_input` nor `request_user_input_async` is listed for the turn, or the listed one returns no answer, the verdict is "not approved":

- End the turn with a 🔴 pending line naming the gate.
- Take no gated action and print no handoff.
- Accept the answer in the next chat turn.

Never continue past a gate on best judgment. Under `codex exec` the tool is unavailable, so every gate stops there.
