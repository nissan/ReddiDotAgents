# AGENTS.md: setting up or refreshing a machine with ReddiDotAgents

You are a coding agent in a clone of ReddiDotAgents. The user wants this machine set up, or refreshed, so its omp, Pi, herdr, and Firstmate configuration matches this repository. [README.md](README.md) explains what the kit contains and why. This file is the procedure.

## Hard rules

- **Never handle credentials.** Do not read, copy, print, or write auth stores, tokens, API keys, `auth.json`, `agent.db`, `models.db`, session files, or `.env` files. Provider logins are typed by the user (`omp login <provider>`). You may run `omp usage accounts` to confirm which providers are logged in.
- **Preview before applying.** Run `scripts/sync.sh --check` and show the user the drift. Apply only once the user has asked you to, either in their request or after seeing the drift.
- **Change only what the kit manages.** `scripts/sync.sh` merges managed keys and replaces only the marked `reddidotagents` block in each `AGENTS.md`. Do not hand-edit the user's agent configuration beyond that. If the user wants something different, change this repository (see Maintaining).
- **Do not commit machine state here.** This repository is public. Nothing from `~/.omp`, `~/.pi`, `~/firstmate/config`, or any home directory goes into it except deliberate, sanitized kit changes.
- **Leave running work alone.** If a Firstmate primary or fleet is running on this machine, do not stop, restart, or reconfigure it beyond what `scripts/sync.sh` writes. Firstmate config changes take effect on its next spawn.

## Procedure

### 1. Identify the machine

Record the OS (Linux, macOS, Windows), the shell, and whether this is a first setup or a refresh: if `~/.omp/agent/AGENTS.md` contains `reddidotagents:begin`, it is a refresh. On Windows, use Git Bash or WSL for every `scripts/sync.sh` command; mise and the tools themselves can be installed from PowerShell.

### 2. Prerequisites

Check what is present, then install only what is missing:

```sh
command -v mise omp pi herdr node npm jq gh git
```

Install missing tools with mise (https://mise.jdx.dev/getting-started.html if mise itself is missing):

```sh
mise use -g node@lts jq gh herdr github:can1357/oh-my-pi pi
```

- `pi` is optional; leave it out if the user only uses omp.
- If herdr cannot be installed through mise on this platform, use its own installer from https://github.com/herdrdev/herdr.
- `jq` must be real jq. Some systems ship `jaq` as `jq`, which breaks parts of Firstmate's dispatch resolver; check `jq --version`.

### 3. Preview and apply

```sh
git pull --ff-only          # on a refresh
scripts/sync.sh --check
```

Summarise the DRIFT and MISSING lines for the user, then:

```sh
scripts/sync.sh --apply
scripts/sync.sh --check     # must print "In sync."
```

Useful options: `--firstmate-home DIR` when Firstmate is not at `~/firstmate`, `--skip-pi` when Pi is not used, `--upgrade-npm` to refresh the npm tools to `@latest`, and `--skip-npm` / `--skip-herdr`. Every changed file is backed up under `~/.reddidotagents-backups/<timestamp>/`; report that path to the user.

### 4. Provider logins (user action)

Tell the user which of these to run, in a terminal you are not driving, for each subscription they have:

```sh
omp login anthropic
omp login openai-codex
omp login google-antigravity
```

Then verify with `omp usage accounts`. A provider the user does not subscribe to can stay logged out: the balancer gives it zero weight and uses it only as a last-resort fallback.

### 5. Firstmate (only if the user wants it)

- If `~/firstmate` does not exist, clone https://github.com/nissan/firstmate there, follow its README and CONTRIBUTING for bootstrap and `no-mistakes` setup, then rerun `scripts/sync.sh --apply` to install `config/crew-dispatch.json`.
- Start the primary with plain `omp` inside the Firstmate home, in a herdr pane.
- Never hand-copy files into an existing Firstmate home's `config/` beyond what the sync writes.

### 6. Verify

Run these and report the results:

```sh
omp config get modelRoles                  # tier roles present
omp -p --no-tools "Reply OK"               # default model answers
herdr integration status                   # omp (and pi) current, if herdr is installed
scripts/sync.sh --check                    # In sync.
```

The fleet rules reach omp when a fresh session's instructions include the "Fleet operating rules (ReddiDotAgents)" section from `~/.omp/agent/AGENTS.md`.

## Troubleshooting

- **`omp config set` failed:** run `omp config path` to find the active agent directory. `PI_CODING_AGENT_DIR` or `omp --profile` may point elsewhere; a refresh applies to whichever directory `omp config path` reports.
- **A subagent ran on an unexpected provider:** the balancer writes its reasoning into each spawn's routing note, for example `cheap → gpt (claude=1.61 gpt=1.19 …)`. Quota pace changes the weights over the week, which is expected.
- **Drift reappears on every check:** something else is rewriting that key (another tool, or a manual edit). Find it before reapplying in a loop.

## Maintaining this repository

Changes to the kit are made here, then pulled by every machine.

1. Edit the kit files: `omp/settings.json`, `omp/extensions/`, `pi/settings.json`, `shared/fleet-rules.md`, `firstmate/crew-dispatch.json`, `npm-globals.txt`, or `scripts/sync.sh`.
2. Test the script against throwaway directories, never the user's real ones:
   ```sh
   S=$(mktemp -d); mkdir -p "$S/omp" "$S/pi"
   PI_CODING_AGENT_DIR="$S/omp" REDDIDOTAGENTS_PI_DIR="$S/pi" REDDIDOTAGENTS_BACKUP_DIR="$S/bak" \
     scripts/sync.sh --apply --skip-npm --skip-herdr --firstmate-home "$S/none"
   ```
   A second `--check` against the same directories must print `In sync.`
3. Scan for secrets and personal data before every commit:
   ```sh
   mise exec gitleaks@latest -- gitleaks git --redact .
   ```
   Also look for home-directory paths, email addresses, account or organisation IDs, and private project names. Keep examples generic.
4. Update the README tables when models, tiers, or components change.
