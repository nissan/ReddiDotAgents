# ReddiDotAgents

A portable, refreshable distribution kit for Workbench-led development practice.
[Oh My Pi](https://github.com/can1357/oh-my-pi) (`omp`) runs standalone using native
delegation. Existing Firstmate work is an explicitly opted-in legacy path, not a
requirement or the policy authority.

The canonical common practice is
[`nissan/reddi-workbench/planning/operating-model.json`](https://github.com/nissan/reddi-workbench/blob/main/planning/operating-model.json).
This kit carries generated rules and a source commit/digest manifest in
`shared/workbench-policy.json`. Review a pinned update; do not auto-apply drift.
Project security and explicit owner permissions remain authoritative.

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
| `cheap` | Composer 2.5 | Grok 4.5 Fast |
| `mid` | Claude Sonnet 5.5 | Grok 4.6 |
| `high` | Claude Opus 5.5 | Grok 4.7 |
| `frontier` | Claude Fable 5.2 (high) | none |

These roles are named explicitly (`@high_cursor`, `@mid_grok`, ...); the quota balancer does not rotate into them. For an explicitly opted-in legacy home, `scripts/sync.sh --with-firstmate --dispatch cursor` selects [`firstmate/crew-dispatch.cursor.json`](firstmate/crew-dispatch.cursor.json). On 11 November 2026 every id was found in `omp models --json` on a machine logged in to Cursor. That proves catalogue discovery only; no request was sent through them.

**Quota-aware balancing.** [`omp/extensions/provider-balancer.ts`](omp/extensions/provider-balancer.ts) picks a provider for every subagent spawn. It reads `omp usage --json` and favours the subscription furthest below its expected pace in its current quota window, interleaving spawns by weighted round-robin. The remaining providers become the child's automatic fallbacks.

**Reasoning effort.** The cheap, mid and high tier models carry omp's `:auto` effort, so a small judge model rates each task and picks the lowest sufficient level. The frontier roles are pinned to high, and Firstmate's default dispatch asks for medium.

**Session defaults.** A plain `omp` session runs GPT-6.1 Sol with `auto` effort and falls back to Claude Opus 5.5 if OpenAI is unavailable.

**Common practice.** [`shared/fleet-rules.md`](shared/fleet-rules.md) is generated from Workbench and installed into the marked instruction blocks of omp and Pi. Its cap, recovery, authority and review rules are guidance; copying them does not establish runtime enforcement.

**Optional Firstmate dispatch.** [`firstmate/crew-dispatch.json`](firstmate/crew-dispatch.json) supports already-owned legacy work. Default sync never inspects a Firstmate home. Use `--with-firstmate` or `--firstmate-home DIR` only with explicit permission; `--skip-firstmate` disables that path.

**Legacy harness prerequisites.** The [nissan/firstmate](https://github.com/nissan/firstmate) fork carries:
- [#52](https://github.com/nissan/firstmate/pull/52): an omp primary's built-in delegation (the `task` tool and eval `agent()`/`workpool()`) is refused in favour of fleet dispatch. Firstmate accepts omp model roles and `auto` effort for omp crew, keeps `auto` through relaunch, and refuses it for other harnesses.
- [#53](https://github.com/nissan/firstmate/pull/53): reconciles newer upstream Firstmate.

Only the opted-in crew dispatch path needs #52. It refuses unsupported homes. Do not bypass its guard, move custody or retire an active run while adopting native execution.

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

Start your agent in this directory and ask it to preview the pinned kit. Apply only the exact target and settings you authorize. Native OMP needs no Firstmate setup; provider logins and new providers require separate permission.

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

   For **practice-only adoption on an existing OMP host**, preview and explicitly
   authorize only its instruction block:
   ```sh
   scripts/sync.sh --check --rules-only --skip-pi
   scripts/sync.sh --apply --rules-only --skip-pi
   ```
   `--rules-only` never manages settings, extensions, tools or legacy dispatch;
   it rejects conflicting legacy/tool-upgrade options. Other hosts require their
   own qualification. Personal coordination text needs a separate reviewed edit.
3. Log in to each subscription you have. You type the credentials; nothing in this repository stores them:
   ```sh
   omp login anthropic
   omp login openai-codex
   omp login google-antigravity
   omp usage accounts        # confirm
   ```
4. Optional legacy maintenance only: after an owner checkpoint and explicit permission, an existing Firstmate home including [#52](https://github.com/nissan/firstmate/pull/52) may use `scripts/sync.sh --with-firstmate --apply`. Do not create a new Firstmate dependency for baseline adoption.

## Updating

```sh
cd ~/ReddiDotAgents
git pull --ff-only
scripts/sync.sh --check
scripts/sync.sh --apply
scripts/sync.sh --apply --upgrade-npm   # also update the npm tools to @latest
```

`--check` reports drift without applying it. Run it at session start, handoff and tranche boundary; do not add an auto-apply daemon. Sync refuses a generated rules file whose digest differs from its manifest. Hashes detect integrity drift; they are not signatures or permission to apply.

## How the sync treats your own settings

- **omp** (`~/.omp/agent/config.yml`): only the keys in [`omp/settings.json`](omp/settings.json) are managed. Record values such as `modelRoles` are merged key by key, so your own roles survive and the kit's roles win. omp rewrites the file when settings change, so YAML comments are not preserved; the pre-change file is kept in the backup.
- **Pi** (`~/.pi/agent/settings.json`): deep-merged with [`pi/settings.json`](pi/settings.json). Other keys stay.
- **Instructions** (`AGENTS.md` in each harness's agent directory): the fleet rules live between `reddidotagents:begin` and `reddidotagents:end` markers. Text outside the markers is yours and is never changed.
- **Safe instruction writes**: malformed, duplicate, reversed or non-regular instruction targets are refused. Updates retain backups and use an atomic replacement. Missing prerequisites make `--apply` fail; partial setup is not a successful rollout.
- **Whole files**: `provider-balancer.ts`; Firstmate's `config/crew-dispatch.json` only on explicit opt-in (`--with-firstmate`, optionally `--dispatch cursor`).
- **Backups**: every changed file is copied to `~/.reddidotagents-backups/<timestamp>/` first.
- **Never touched**: logins, tokens, auth stores, sessions, and anything else in the agent directories.

## Customising

Managed settings remain kit-owned. Common practice is Workbench-owned: edit its canonical contract, review it, then run `python3 scripts/operating_model.py export --kit /explicit/ReddiDotAgents` from that source checkout. The manifest distinguishes committed source from a local proposal.

- **Fewer subscriptions:** remove that family's roles from the tier lists in `omp/settings.json` and from `firstmate/crew-dispatch.json`, and remove its lane in `LANES` in `provider-balancer.ts`. Without those edits, a provider you are not logged in to gets zero weight and is used only as a last-resort fallback.
- **Different models:** edit the role values in `omp/settings.json`. Firstmate dispatch names roles, so it follows automatically.
- **Concurrency cap or common rules:** change Workbench's `planning/operating-model.json` and regenerate; never hand-edit `shared/fleet-rules.md`.

Personal, machine-specific rules belong outside the managed block in your local `AGENTS.md`.

## Platform support

| Platform | Status |
|---|---|
| Linux OMP | Disposable sync/RPC qualification first; artifact alignment is not model-behavior proof |
| Linux Claude/Codex | Next qualification wave; not established by OMP evidence |
| Mac/OpenClaw | Following wave; not yet qualified |
| Pi, Gemini, Cursor/Grok, other hosts | Opt-in qualification required; copied files alone do not qualify them |

## Repository layout

```text
AGENTS.md                         setup and refresh procedure for coding agents
CLAUDE.md                         points Claude Code at AGENTS.md
shared/fleet-rules.md             global fleet rules (managed block in each harness's AGENTS.md)
shared/workbench-policy.json      pinned Workbench source, contract and generated-file digest
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
