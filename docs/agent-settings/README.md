# Shared agent settings

Settings carried over from [Reddi Workbench](https://github.com/nissan/reddi-workbench)
(private; commit `abdd519`, 11 November 2026) so that agent sessions behave the same
way across Redditech repositories.

**This repository's own instructions win.** Where `AGENTS.md`, `CLAUDE.md` or any
project rule here is stricter or different, follow it and not this folder.

## 1. Fail closed

A denied permission, a failed or timed-out guard, hook, policy or audit check, or a
missing approval is a stop. Report it plainly. Do not retry around it or look for
another route, whatever a prompting profile, skill or plugin says about finishing the
job. An approval covers the exact action named and nothing else.

## 2. Fable 5.2 prompting profile (optional)

[claude-fable-5-2.md](claude-fable-5-2.md) holds ten prompting rules for sessions where
the selected model is `claude-fable-5-2`. It is unevaluated vendor guidance for writing
prompts and work packets. It grants no authority and relaxes no gate. For any other
model, use none of it.

## 3. Claude mods (optional, operator's choice)

Six small Claude Code mods live in Reddi Workbench under `mods/` (MIT licence):

| Mod | What it does |
|---|---|
| input-router | Labels each prompt quick, standard, deep or carry and shows the route |
| effort-optimizer | Lets you lower thinking effort for greetings and read-only scouts; changes nothing until set |
| subagent-model-selector | Lets you choose a model for subagents started without one |
| cache-clock | Shows how long the prompt cache stays warm |
| handoff | Adds `/handoff`, a factual note for a fresh session |
| efficient-browser-use | Steers browser work toward page text over screenshots |

Install, once per mod, at a Claude Code prompt (your GitHub account needs access to the
private repository):

```
/plugin install input-router --marketplace nissan/reddi-workbench
/plugin install effort-optimizer --marketplace nissan/reddi-workbench
/plugin install subagent-model-selector --marketplace nissan/reddi-workbench
/plugin install cache-clock --marketplace nissan/reddi-workbench
/plugin install handoff --marketplace nissan/reddi-workbench
/plugin install efficient-browser-use --marketplace nissan/reddi-workbench
```

Mods are installed per person, not per repository. An agent must not install them on
its own; this section only tells the operator where they are.

## 4. Stageshow illustrations: not applied here

Stageshow builds illustrated product-UI demos. This repository has no user interface,
so its pin and rules were left out.

## 5. Delivery practices

[DELIVERY-PRACTICES.md](DELIVERY-PRACTICES.md) holds twelve working rules adopted after three
rounds of delivery across eleven repositories: the CI run is the proof that tests pass;
check an issue is not already done, or already claimed by an open pull request, before
building it; the builder reviews its own work; every issue's Status carries a readiness
line; read an issue back before hashing or mirroring it; scenarios an agent wrote are
drafts until a person confirms them; a review follow-up goes on the pull request or is
filed as blocked on it; each repository says what its checks need; a repository without
hosted CI has one check command; the agent file says who builds and who reviews; a pull
request says which check covers its change; checks only the workstation can run go in
one queue kept in Reddi Workbench.

[CHECKS.md](CHECKS.md) is this repository's answer to the last three: who builds and who
reviews here, the one check command, and what each check needs. It is rendered from
Reddi Workbench's `planning/repo-facts.json`; correct a wrong fact there.

Unlike the rest of this folder, the review rule is also stated in this repository's own
agent instructions, so it is binding here.

## Keeping this in step

The source of truth is Reddi Workbench: `AGENTS.md`, `docs/model-profiles/`, `mods/`,
`docs/STAGESHOW.md`, `docs/DELIVERY-PRACTICES.md` and `planning/repo-facts.json`. This folder is a dated copy. Nothing checks it automatically;
re-copy it when the source changes.
