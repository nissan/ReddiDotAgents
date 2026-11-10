# Prompting profile · Claude Fable 5.2 (`claude-fable-5-2`)

**Optional prompting guidance, usable only when the selected model is
`claude-fable-5-2`.** It tells whoever writes a prompt or work packet how to write it
for this model. It does not select a model, approve a provider or relax any gate. This
repository's instructions and security rules win on any conflict, and nothing here is a
reason to push past a denied, failed or timed-out control.

Evidence status: **vendor guidance, not locally evaluated.** The headings come from a
conference slide; the detail from Anthropic's
[Fable 5.2 prompting guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-2),
[What's new page](https://platform.claude.com/docs/en/models/fable-5-2/whats-new-fable-5-2)
and the earlier [Fable 5 guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5),
checked by machine on 10 November 2026. No person has read the sources against this
page. Copied from Reddi Workbench (`docs/model-profiles/claude-fable-5-2.md`), where the
full version and its canonical rule text live. Treat each rule as a starting hypothesis.

## The ten rules

1. **Run it on high.** Set effort explicitly. `high` is the vendor's starting point for
   hard coding, review and long unattended runs; most of the gain arrives by `high`.
   Use `low` for read-only scouting.
2. **Make it prove its work.** Before a status report, check each claim against a tool
   result from the same session. Report failed tests with their output, name skipped
   steps and label anything unverified.
3. **Tell it to finish the job.** The model can stop a long turn early. Tell it to keep
   going until the task's conditions are met and to work through ordinary obstacles
   such as a failing test, a compile error or a command that needs a different flag.
   **A control that fails is different.** A denied permission, or a guard, hook,
   sandbox, policy, budget or audit check that fails, times out or is unavailable, is a
   stop. So are human gates, merge, deploy, spend, settings changes, credentials and
   outside communication. Stop, report, and do not look for a way round. Name the exact
   action when approving a step, because the model applies approvals literally.
4. **Clean up your old prompts.** Remove "think less" lines, standing delegate lines,
   token countdowns and hard style caps from prompts, skills and notes you reuse. This
   never applies to this repository's instructions, security rules or any authorisation
   rule; those stay as written.
5. **You can't stop it thinking.** Adaptive thinking is always on. Lower the effort for
   easy turns instead, and count thinking tokens in budgets. Do not switch model
   mid-conversation; start a new one from a durable checkpoint.
6. **Don't ask for its reasoning.** A prompt that asks the model to transcribe its
   internal reasoning can be refused. Ask for the decision, the evidence and a short
   rationale.
7. **Say who owns the code.** Default: the operator owns the repository; the builder
   owns only the changes its task needs. The vendor's broader "this codebase is yours"
   wording produced unrequested changes in vendor tests; use it only for an approved
   restructure.
8. **Don't push it to delegate.** Remove standing "use subagents" lines and let the
   task decide. A subagent cannot approve anything.
9. **Ask for updates.** One line before starting, a one-line status every few tool
   calls, and a closing recap that stands on its own.
10. **Prompt for length and tone.** Say what length and tone you want. Write reports
    for a reader who saw none of the work: outcome first, full sentences, defined
    terms. Avoid hard word limits.

Prompt rules are operating guidance. They are not policy enforcement.
