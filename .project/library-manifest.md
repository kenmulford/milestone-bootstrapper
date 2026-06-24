# Library manifest

<!--
Project doc (.project/). Cite as `.project/library-manifest.md#<section>`. The
implementer's "new dependency = PAUSE" gate reads this; the coherence-reviewer
flags a new library that duplicates one listed here. Keep it current. Keep ##
headings stable — they are citation anchors.
-->

## Runtime & frameworks
The platform/runtime and primary frameworks, with versions. (Mirror these into milestone-driver `nonNegotiables` where they're hard constraints.)
> Claude Code plugin — markdown skills plus bash-first / PowerShell-7-fallback component scripts (the bash twins require `jq`). There is no application-language runtime. (Grounded in BRIEF.md:13, BRIEF.md:81, CHANGELOG.md:77, .milestone-config/driver.json `nonNegotiables`.)

## Approved libraries (by purpose)
One approved choice per purpose, so a redundant alternative is easy to spot.

| Purpose | Library | Notes |
|---|---|---|
| Plugin runtime | Claude Code skills (markdown) + `gh` CLI + `git` | the plugin surface and its GitHub writes |
| Shell scripting | bash + `jq` (primary), PowerShell 7+ (fallback twin) | every component script ships both twins, byte-equivalent |
| Plugin dependency | `superpowers` (cross-marketplace) | required dependency declared in `.claude-plugin/plugin.json` |

## Adding a dependency (the gate)
A new dependency is a PAUSE, not an autonomous call. Record what it buys, its license / OSS status, and why nothing approved suffices; a human approves before it's added.
> A new dependency is a PAUSE, not an autonomous call — open an issue labeled `needs decision`, record what it buys, its license / OSS status, and why nothing approved suffices; a human approves before it is added. (Grounded in BRIEF.md:37, the driver + feeder label taxonomy.)

## Avoid / banned
Libraries explicitly not to use, and why.
> Non-GitHub CI providers (v1 is GitHub Actions only). Any non-cross-platform hook or script — every script must ship both a bash and a PowerShell-7 twin. (Grounded in BRIEF.md:67, BRIEF.md:76, BRIEF.md:81.)
