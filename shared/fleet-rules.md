# Fleet operating rules (ReddiDotAgents)

These rules are installed by ReddiDotAgents into the global instruction file of each agent harness (`~/.omp/agent/AGENTS.md`, `~/.pi/agent/AGENTS.md`). Edit them in the ReddiDotAgents repository, not on the machine: a refresh rewrites this managed block. Put personal or project-specific rules outside the block.

## Concurrency

- Across all projects and agent sessions, allow no more than five concurrently active spawned agents per model-provider family.
- Count Claude models together under the Anthropic/Claude family, OpenAI models together under the OpenAI family, and Gemini plus Antigravity models together under the Google family. Apply the same five-agent cap independently to any other provider family.
- Before spawning, resuming, or restarting an agent, count active spawned agents in its provider family across the visible fleet. If starting it would exceed five for that family, queue the work until a slot is available.
- An agent that is fully stopped or paused without making model calls does not consume a slot; an agent running, reviewing, fixing, compacting, or awaiting an in-flight model response does.
- Do not evade a provider-family cap by changing projects, sessions, worker runtimes, aliases, or model names within that provider.

## Model and effort selection

- At every spawn, resume, or relaunch decision, and during each fleet-wide status review, inspect each direct worker's provider, model, reasoning effort, task complexity, current activity, and evidence of forward progress. Do not infer useful work from process liveness alone.
- Pick the tier from the kind of work (owner direction, 11 November 2026). The omp model roles are defined once in `~/.omp/agent/config.yml`:
  - Everyday work, or not sure: the high tier (`@high_*`: Claude Opus 5.5, GPT-6.1 Sol, Gemini 4 Argon) at medium effort. This is the default.
  - A clear, scoped fix: the mid tier (`@mid_*`: Claude Sonnet 5.5, GPT-6.1 Terra, Gemini 3.8 Flash).
  - Side jobs such as searching, reading logs and running tests: the cheap tier (`@cheap_*`: Claude Haiku 5.5, GPT-6 Luna, Gemini 3.8 Flash), as subagents.
  - A big, ambiguous job expected to run for hours: the frontier tier (`@frontier`: Claude Fable 5.2 or GPT-6 Astra, whichever subscription has quota). Plan it at medium effort, then run it at high.
- Within a tier, quota decides the provider family. Do not go above the tier the work calls for without a concrete complexity, uncertainty, or risk reason that can be stated, and never use the frontier tier for work that fits a lower one.
- When the session itself runs in Cursor or Grok, use the Cursor subscription's tiers instead: `@cheap_cursor`, `@mid_cursor`, `@high_cursor` and `@frontier_cursor`, or `@cheap_grok`, `@mid_grok` and `@high_grok` for Grok models through Cursor. Cursor counts as its own provider family for the five-agent cap.
- Coordinators run on GPT-6.1 Sol (OpenAI) or Claude Opus 5.5 (Anthropic).
- Before every delegation, classify the task by type, complexity, uncertainty, and risk. Record the justification when using a non-default model or a higher reasoning tier.
- A worker repeatedly making model calls without durable progress, retrying the same failure, using a stronger tier without justification, or continuing after a stable external wait must be redirected through its owning recovery procedure to a safe checkpoint or pause. Never change tiers mid-validation or discard work merely to save usage.
- At a safe waiting point, keep the worker genuinely idle or stop it through supported lifecycle control. Before resuming, reassess provider capacity and the cheapest sufficient tier rather than inheriting the prior tier.

## Delivery

- Conserve hosted CI minutes. Run tests, lint, builds, and reviews locally wherever practical; consolidate changes before pushing; never use repeated pushes as a debugging loop.
- Treat issues in the project's forge as the durable cross-machine record of work: keep assignments, status, decisions, dependencies, acceptance criteria, and handoff notes current so parallel workers do not overlap.
- Keep reviews bounded: fix critical and high-severity findings in the current loop, and file lower-severity findings as issues.
- The builder reviews its own work as a build step before reporting it done: whole diff re-read, checks and negative cases run, each claim checked against a result. An independent review happens when the owner asks for one (owner decision, 11 November 2026). Permit automerge only where the repository gives standing merge authority, after that self-review and with required checks passing on the exact commit; any later commit needs both again. Never describe a review of your own work as independent.
- At the end of each tranche, run a retrospective and record durable lessons in your knowledge base.
