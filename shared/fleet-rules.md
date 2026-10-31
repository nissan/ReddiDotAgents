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
- Use the lowest model and reasoning tier that can reliably complete the task, and raise it only with a concrete complexity, uncertainty, or risk reason that can be stated.
- Coordinators default to GPT-6.1 Sol (OpenAI) or Claude Opus 5.5 (Anthropic) at the cheapest sufficient reasoning level. Delegated work uses the complexity tiers instead: omp model roles `@cheap_*`, `@mid_*`, and `@high_*`, defined once in `~/.omp/agent/config.yml`, balanced across the Claude, OpenAI, and Google families by quota, with omp's `auto` effort classifier choosing the reasoning level.
- Before every delegation, classify the task by type, complexity, uncertainty, and risk. Record the justification when using a non-default model or a higher reasoning tier.
- A worker repeatedly making model calls without durable progress, retrying the same failure, using a stronger tier without justification, or continuing after a stable external wait must be redirected through its owning recovery procedure to a safe checkpoint or pause. Never change tiers mid-validation or discard work merely to save usage.
- At a safe waiting point, keep the worker genuinely idle or stop it through supported lifecycle control. Before resuming, reassess provider capacity and the cheapest sufficient tier rather than inheriting the prior tier.

## Delivery

- Conserve hosted CI minutes. Run tests, lint, builds, and reviews locally wherever practical; consolidate changes before pushing; never use repeated pushes as a debugging loop.
- Treat issues in the project's forge as the durable cross-machine record of work: keep assignments, status, decisions, dependencies, acceptance criteria, and handoff notes current so parallel workers do not overlap.
- Keep reviews bounded: fix critical and high-severity findings in the current loop, and file lower-severity findings as issues.
- Permit automerge only after two independent reviewers have reviewed the same exact commit and both returned GO. Any later commit invalidates those approvals.
- At the end of each tranche, run a retrospective and record durable lessons in your knowledge base.
