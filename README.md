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

- **omp** (`~/.omp/agent/config.yml`): only the keys in [`omp/settings.json`](omp/settings.json) are managed. Record values such as `modelRoles` are merged key by key: the kit's keys win and your own keys survive. The `cheap`, `mid`, `high`, and `frontier` tier lists are owned outright: they become the kit's entries followed by the ones declared in `local.json` (see [Machine-local additions](#machine-local-additions)), so a lane the kit retires disappears on the next refresh. omp rewrites the file when settings change, so YAML comments are not preserved; the pre-change file is kept in the backup.
- **Pi** (`~/.pi/agent/settings.json`): deep-merged with [`pi/settings.json`](pi/settings.json); the kit's keys win and other keys stay.
- **Instructions** (`AGENTS.md` in each harness's agent directory): the fleet rules live between `reddidotagents:begin` and `reddidotagents:end` markers. Text outside the markers is yours and is never changed.
- **Firstmate** (`<firstmate-home>/config/crew-dispatch.json`): written as [`firstmate/crew-dispatch.json`](firstmate/crew-dispatch.json) (or `crew-dispatch.cursor.json` with `--dispatch cursor`) plus the lanes and rules declared in `local.json`. Each kit rule carries a `tier` name (`cheap`, `mid`, `high`, `frontier`); local lanes for that tier are appended to its `use` exactly as declared, local rules are appended whole after the kit's rules, and local `default` lanes follow the kit's. The kit's `when`, `select`, `why`, and effort always win on its own rules and lanes. Other files in `config/` (such as `secondmate-harness`) are untouched.
- **Whole files**: `provider-balancer.ts`.
- **Backups**: every changed file is copied to `~/.reddidotagents-backups/<timestamp>/` first.
- **Never touched**: logins, tokens, auth stores, sessions, and anything else in the agent directories.

## Customising

A refresh reverts edits to managed keys. To customise durably, fork this repository and edit the kit:

- **Fewer subscriptions:** remove that family's roles from the tier lists in `omp/settings.json` and from `firstmate/crew-dispatch.json`, and remove its lane in `LANES` in `provider-balancer.ts`. Without those edits, a provider you are not logged in to gets zero weight and is used only as a last-resort fallback.
- **Different models:** edit the role values in `omp/settings.json`. Firstmate dispatch names roles, so it follows automatically.
- **Concurrency cap or rules:** edit `shared/fleet-rules.md`.
- **Extra lanes or rules on one machine only:** declare them in `local.json` (next section) instead of editing the kit; a refresh keeps them alongside the kit's entries.

Personal, machine-specific rules belong outside the managed block in your local `AGENTS.md`.

## Machine-local additions

Lanes, roles, or dispatch rules that belong to one machine (a local model, an extra subscription) go in `local.json` at the root of your clone. It is git-ignored, never leaves the machine, and is optional. Its shape mirrors the kit files:

```json
{
  "omp": {
    "modelRoles": {
      "cheap_local": "local/small-coder",
      "cheap": "@cheap_local",
      "mid": "@cheap_local"
    }
  },
  "firstmate": {
    "use": {
      "cheap": [ { "harness": "omp", "model": "@cheap_local", "provider": "local" } ]
    },
    "rules": [
      { "when": "Docs-only edits", "use": [ { "harness": "omp", "model": "@cheap_gpt", "provider": "codex" } ], "select": "quota-balanced", "why": "Cheapest GPT lane is enough for prose." }
    ],
    "default": [ { "harness": "omp", "model": "@cheap_local", "provider": "local" } ]
  }
}
```

- `omp.modelRoles` is the only `omp` key accepted. It adds role definitions, and the kit's own keys win. Its `cheap`, `mid`, `high`, and `frontier` values are comma-separated strings appended to the kit's tier lists rather than replacing them.
- `firstmate.use.<tier>` appends lanes to the kit rule with that `tier`; `firstmate.rules` appends whole rules; `firstmate.default` appends default lanes. No other `firstmate` keys are accepted. Local lanes keep whatever `effort` you give them (or none); the kit's lanes carry `auto`. An `omp` lane must name its `provider`, since Firstmate's resolver cannot infer one for omp. The sync checks the shapes it composes: `harness` and `model` non-empty, `effort` non-empty and, for omp lanes only, one of omp's levels, `provider` format, `select`, and repeated profiles; Firstmate validates everything else, including other harnesses' effort levels, `floor`, `approval`, and `min_confidence`, at its next spawn. A local lane that repeats a kit lane's harness, model, and effort is written once, since Firstmate rejects a rule with duplicate profiles.
- The kit stays canonical: removing a lane or rewording a `why` in the kit reaches every machine, and anything in the managed lists that is neither in the kit nor in `local.json` is replaced on `--apply` (the previous file is backed up).

**Migration.** Until a machine has a `local.json`, a tier list that contains entries the kit does not define, or a `config/crew-dispatch.json` that differs in any way from the kit's `firstmate/crew-dispatch.json`, stops the whole run: `--check` reports it under `MISSING` and `--apply` exits before changing anything on the machine, including the fleet rules, extension, Pi, npm, and herdr surfaces. Declare the lanes and rules you want to keep in `local.json`, or create the file containing only `{}` to accept the kit's lists and dispatch file, then rerun. `scripts/test-sync.sh` exercises these rules against throwaway directories.

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
scripts/test-sync.sh              behavioural tests for the sync, in throwaway directories
local.json                        optional, git-ignored machine-local additions (see above)
```

## License

[MIT](LICENSE)
