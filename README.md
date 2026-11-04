# ReddiDotAgents

A portable, refreshable setup for running a multi-provider coding-agent fleet:
[Oh My Pi](https://github.com/can1357/oh-my-pi) (`omp`) as the agent harness, [Firstmate](https://github.com/nissan/firstmate) supervising fleets of agents in [herdr](https://github.com/herdrdev/herdr) panes, and work spread across Claude, ChatGPT, and Google Antigravity subscriptions by quota and task complexity.

This repository holds only configuration and a sync script. The tools themselves come from their own repositories (linked below). Clone it on every machine, point your coding agent at [`AGENTS.md`](AGENTS.md), and rerun the sync whenever this repository updates.

## What you get

**Tiers by kind of work, across three subscriptions.** Each tier pairs the newest model of each family at a similar price point:

| Tier | Used by | Claude | ChatGPT (Codex) | Antigravity Gemini | Antigravity Claude |
|---|---|---|---|---|---|
| `cheap` | `scout`, `sonic` subagents; small crew tasks | Haiku 5.5 | GPT-6 Luna | Gemini 3.8 Flash | none |
| `mid` | `task` subagents, eval `agent()`/`workpool()`; ordinary crew work | Sonnet 5.5 | GPT-6.1 Terra | Gemini 3.8 Flash | Sonnet 5.5 |
| `high` | Everyday crew work and anything unclear (the default, at medium effort); `reviewer`, `security-reviewer`; high-risk work | Opus 5.5 | GPT-6.1 Sol | Gemini 4 Argon | Opus 5.5 |
| `frontier` | Big, ambiguous jobs expected to run for hours; planned at medium effort, run at high | Fable 5.2 | GPT-6 Astra | none | none |

The `mid` tier is for a clear, scoped fix and `cheap` for side jobs (search, logs, tests). The frontier tier uses whichever of Fable 5.2 and Astra has quota.

**Cursor and Grok.** A session running in Cursor or Grok uses the Cursor subscription's own tiers. Grok models are reached through Cursor, not a separate xAI login:

| Tier | Cursor | Grok through Cursor |
|---|---|---|
| `cheap` | Composer 2.5 | Grok Code Fast 1 |
| `mid` | Claude Sonnet 5 (medium) | Grok 4.6 |
| `high` | Claude Opus 5.5 | Grok 4.7 |
| `frontier` | Claude Fable 5.1 (high) | none |

These roles are named explicitly (`@high_cursor`, `@mid_grok`, ...); the quota balancer does not rotate into them. For Firstmate, `scripts/sync.sh --dispatch cursor` installs [`firstmate/crew-dispatch.cursor.json`](firstmate/crew-dispatch.cursor.json) into a home whose primary runs in Cursor or Grok. The model ids come from omp's bundled catalogue and have not been checked against a logged-in Cursor account; run `omp login cursor` and confirm them with omp's model list before relying on them.

**Quota-aware balancing.** [`omp/extensions/provider-balancer.ts`](omp/extensions/provider-balancer.ts) picks a provider for every subagent spawn. It reads `omp usage --json` and favours the subscription furthest below its expected pace in its current quota window, interleaving spawns by weighted round-robin. The remaining providers become the child's automatic fallbacks.

**Reasoning effort.** The cheap, mid and high tier models carry omp's `:auto` effort, so a small judge model rates each task and picks the lowest sufficient level. The frontier roles are pinned to high, and Firstmate's default dispatch asks for medium.

**Session defaults.** A plain `omp` session runs GPT-6.1 Sol with `auto` effort and falls back to Claude Opus 5.5 if OpenAI is unavailable.

**Fleet rules.** [`shared/fleet-rules.md`](shared/fleet-rules.md) is installed into the global instructions of both omp and Pi. It sets a five-active-agents-per-provider-family cap, tier selection by kind of work, stall redirection, local-first CI, and builder self-review before merge.

**Firstmate crew dispatch.** [`firstmate/crew-dispatch.json`](firstmate/crew-dispatch.json) routes Firstmate crew tasks to the same omp tiers, ranked by Firstmate's own quota snapshot. Unmatched work goes to the high tier at medium effort.

**Firstmate harness changes.** The [nissan/firstmate](https://github.com/nissan/firstmate) fork carries the harness support this kit relies on:
- [#52](https://github.com/nissan/firstmate/pull/52): an omp primary's built-in delegation (the `task` tool and eval `agent()`/`workpool()`) is refused in favour of fleet dispatch. Firstmate accepts omp model roles and `auto` effort for omp crew, keeps `auto` through relaunch, and refuses it for other harnesses.
- [#53](https://github.com/nissan/firstmate/pull/53): reconciles newer upstream Firstmate.

The crew dispatch profile needs a Firstmate home that includes #52. `scripts/sync.sh` refuses to install it into an older checkout or into upstream Firstmate, because their validators reject `auto` effort.

**Tooling.** The script installs the herdr integrations for omp and Pi, so their sessions appear in herdr's sidebar and resume after a restart. It also installs the npm CLI tools Firstmate expects (the `*-axi` tools and the Railway CLI).

## Components

| Component | Role | Source |
|---|---|---|
| Oh My Pi (`omp`) | Agent harness: roles, subagents, extensions | [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) |
| Pi (`pi`) | Original harness; optional, still used for some Firstmate workers | [earendil-works/pi](https://github.com/earendil-works/pi) |
| herdr | Terminal workspace manager that shows agent state | [herdrdev/herdr](https://github.com/herdrdev/herdr) |
| Firstmate | Fleet supervision harness (this setup's fork) | [nissan/firstmate](https://github.com/nissan/firstmate), upstream [kunchenguid/firstmate](https://github.com/kunchenguid/firstmate) |
| no-mistakes | Local validation gate Firstmate uses to ship changes | [kunchenguid/no-mistakes](https://github.com/kunchenguid/no-mistakes) |
| `*-axi` CLIs | Agent-friendly GitHub, quota, task, browser and editor tools | [gh-axi](https://github.com/kunchenguid/gh-axi), [quota-axi](https://github.com/kunchenguid/quota-axi), [tasks-axi](https://github.com/kunchenguid/tasks-axi), [lavish-axi](https://github.com/kunchenguid/lavish-axi), [chrome-devtools-axi](https://github.com/kunchenguid/chrome-devtools-axi) |
| mise | Installs and pins the tools above | [jdx/mise](https://github.com/jdx/mise) |

## Quick start

### With your coding agent (recommended)

```sh
git clone https://github.com/nissan/ReddiDotAgents.git ~/ReddiDotAgents
cd ~/ReddiDotAgents
```

Start your agent (`omp`, `claude`, `codex`, …) in that directory and ask it to **"set up this machine from AGENTS.md"**. It installs the prerequisites, shows you what will change, applies the kit, and walks you through the provider logins, which you complete yourself.

### By hand

1. Install the prerequisites with [mise](https://mise.jdx.dev/getting-started.html):
   ```sh
   mise use -g node@lts jq gh herdr github:can1357/oh-my-pi pi
   ```
   Omit `pi` if you only use omp. On Windows, run this in PowerShell, then use Git Bash or WSL for step 2.
2. Preview, then apply:
   ```sh
   scripts/sync.sh --check   # shows drift, changes nothing
   scripts/sync.sh --apply   # applies, backing up every changed file
   ```
3. Log in to each subscription you have. You type the credentials; nothing in this repository stores them:
   ```sh
   omp login anthropic
   omp login openai-codex
   omp login google-antigravity
   omp usage accounts        # confirm
   ```
4. Optional, for Firstmate: clone [nissan/firstmate](https://github.com/nissan/firstmate) to `~/firstmate`, follow its README, then rerun `scripts/sync.sh --apply` to install the crew dispatch profile. An existing Firstmate home must be updated to include [#52](https://github.com/nissan/firstmate/pull/52) first.

## Updating

```sh
cd ~/ReddiDotAgents
git pull --ff-only
scripts/sync.sh --check
scripts/sync.sh --apply
scripts/sync.sh --apply --upgrade-npm   # also update the npm tools to @latest
```

`--check` exits 1 when the machine differs from the kit, so you can run it from a scheduled job or a shell startup.

## How the sync treats your own settings

- **omp** (`~/.omp/agent/config.yml`): only the keys in [`omp/settings.json`](omp/settings.json) are managed. Record values such as `modelRoles` are merged key by key: the kit's keys win, your own keys survive, and extra `@<role>` entries in `cheap`, `mid`, and `high` that reference your own keys stay in place after the kit's entries. omp rewrites the file when settings change, so YAML comments are not preserved; the pre-change file is kept in the backup.
- **Pi** (`~/.pi/agent/settings.json`): deep-merged with [`pi/settings.json`](pi/settings.json); the kit's keys win and other keys stay.
- **Instructions** (`AGENTS.md` in each harness's agent directory): the fleet rules live between `reddidotagents:begin` and `reddidotagents:end` markers. Text outside the markers is yours and is never changed.
- **Firstmate** (`<firstmate-home>/config/crew-dispatch.json`): merged with [`firstmate/crew-dispatch.json`](firstmate/crew-dispatch.json) (or `crew-dispatch.cursor.json` with `--dispatch cursor`) by matching each rule's `(harness, model)` selectors in `use`. On matched rules, the kit's `when`, `select`, and managed `use` entries win, while extra machine-local `use` lanes (and the local `why` note when extra lanes are present) and extra local rules stay. Other files in `config/` (such as `secondmate-harness`) are untouched.
- **Whole files**: `provider-balancer.ts`.
- **Backups**: every changed file is copied to `~/.reddidotagents-backups/<timestamp>/` first.
- **Never touched**: logins, tokens, auth stores, sessions, and anything else in the agent directories.

## Customising

A refresh reverts edits to managed keys. To customise durably, fork this repository and edit the kit:

- **Fewer subscriptions:** remove that family's roles from the tier lists in `omp/settings.json` and from `firstmate/crew-dispatch.json`, and remove its lane in `LANES` in `provider-balancer.ts`. Without those edits, a provider you are not logged in to gets zero weight and is used only as a last-resort fallback.
- **Different models:** edit the role values in `omp/settings.json`. Firstmate dispatch names roles, so it follows automatically.
- **Concurrency cap or rules:** edit `shared/fleet-rules.md`.
- **Extra machine-local lanes:** define additional `<tier>_<lane>` roles in `~/.omp/agent/config.yml` and reference `@<tier>_<lane>` in `cheap`/`mid`/`high` or in Firstmate's `config/crew-dispatch.json`; a refresh keeps them alongside the kit's lanes.

Personal, machine-specific rules belong outside the managed block in your local `AGENTS.md`.

## Platform support

| Platform | Status |
|---|---|
| Linux | Tested |
| macOS | Expected to work (bash, jq); not yet verified |
| Windows | Prerequisites via mise in PowerShell; run the sync from Git Bash or WSL; not yet verified |

## Repository layout

```text
AGENTS.md                         setup and refresh procedure for coding agents
CLAUDE.md                         points Claude Code at AGENTS.md
shared/fleet-rules.md             global fleet rules (managed block in each harness's AGENTS.md)
omp/settings.json                 managed omp config keys (roles, tiers, effort, fallbacks)
omp/extensions/provider-balancer.ts  quota-aware provider choice for subagent spawns
pi/settings.json                  managed Pi defaults
firstmate/crew-dispatch.json      Firstmate crew dispatch profiles using omp roles
firstmate/crew-dispatch.cursor.json  the same, for a home whose primary runs in Cursor or Grok
npm-globals.txt                   npm CLI tools to install globally
scripts/sync.sh                   check / apply the kit on this machine
```

## License

[MIT](LICENSE)
