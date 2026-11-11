# Delivery practices

Fifteen working rules. Rules 1 to 6 were adopted on 11 November 2026 after one issue was taken
through delivery in each of eleven repositories; rules 7 to 10 after a second round the
same day; rules 11 and 12, and additions to rules 2, 4 and 10, after a third; rules 13 to 15, and
additions to rules 2 and 4, after a fourth; the changes to rules 4, 12, 13 and 14 marked
"round 4 review" after looking back at that round the same day. Each rule names the evidence behind it. This repository's own instructions (`AGENTS.md` or `CLAUDE.md`)
are the contract; this page explains how to meet them. Copied from Reddi Workbench (`docs/DELIVERY-PRACTICES.md`, commit `a015471`).

## 1. The CI run is the proof that tests pass

Where a repository has CI, a pull request's evidence is a link to the CI run on its final
commit. A builder's own "all tests pass" is a claim until that run is green. Write the
description after the checks finish, and correct it in a comment if it was wrong.

Where a repository has no CI, paste the commands and their actual output, and say which
checks did not run. A check that could not run is a stop, not a pass: leave the pull
request unmerged and say what is needed.

*Evidence: a pull request here was pushed with a failing test while its description said
37 tests passed; CI caught it, the description had not. One repository had no CI, so its
only relevant check could not run anywhere the builder could reach.*

## 2. Check whether an issue is already done before building it

Before starting an issue, run its acceptance check against the current default branch. If
the outcome is already met, close the issue with the evidence: the commit checked, the
command run and its output. Do not rebuild it.

When picking up a backlog after a gap, sweep the low-severity and follow-up issues this
way first.

Check for an open pull request too. An issue that an open pull request already names is
taken: building it again makes a duplicate. `python3 scripts/triage.py check OWNER/REPO`
lists every issue named by an open pull request whose readiness line does not say so.

An issue can also wait on a pull request that never mentions it, because the code it
changes exists only on that pull request's branch. `python3 scripts/triage.py precheck
OWNER/REPO N ...` reads each shortlisted issue for the files it names and says which are
not on the default branch but are added by an open pull request. It sees only paths the
issue writes in backticks, so an issue that describes a file in words still needs a read.

*Evidence: five of the eight issues chosen as "smallest" in two repositories were already
fixed on main. In the third round an issue was built a second time while its first pull
request was still open, because the check looked only at the default branch. In the fourth,
three issues chosen for one repository all changed code that existed only on an unmerged
pull request's branch.*

## 3. One review rule: the builder reviews its own work

In every Redditech repository the builder reviews its own work as a build step before
reporting it done: re-read the whole diff, run the checks and the negative cases, and
check each claim against a result. A separate independent review happens when the owner
asks for one. This replaces any older rule in a repository that asks for one or two
independent reviews or forbids a builder from approving its own change (owner decision,
11 November 2026).

Merge authority is separate and unchanged: merge only with the owner's instruction or the
repository's standing merge authority.

*Evidence: three repositories had three different review rules, and a builder had to guess
which applied.*

## 4. Every issue says whether it can be started

The Status section of an issue carries one readiness line:

| Readiness | Meaning |
|---|---|
| `Ready` | Scenarios reviewed by a person, dependencies met; can be built now |
| `Needs owner` | Waits on a decision, approval or acceptance from the owner |
| `Needs machine` | Needs a device, a local machine or an environment an agent session lacks |
| `Needs tool` | Needs a tool or connection the session does not have; name it |
| `Blocked` | Waits on another issue or pull request; name it |
| `Draft` | Scenarios not yet reviewed by a person (see rule 6) |

Example: `Readiness: Needs tool (shared-brain recall).`

`python3 scripts/triage.py check OWNER/REPO` in Reddi Workbench lists the open issues with no
readiness line. `apply` writes one into each: `Blocked (pull request N)` when an open pull
request names the issue, `Needs owner (...)` when its Human gate asks something of the
owner, and otherwise `Draft`, because a script cannot know that a person has read the
scenarios. It leaves an issue that already has a line alone; `--refresh-drafts` re-evaluates
only the lines that are still the default `Draft`. A decisions file gives the real line
for issues somebody has looked at.

A round can only "pick a Ready issue" where some are marked `Ready`. Before a round, the
session shortlists a few candidates per repository and the owner confirms them.

The pre-build checks of rule 2 come before the shortlist reaches the owner, not after: for
each candidate, the outcome is checked against the default branch and `triage.py precheck`
is run. Only candidates that pass are offered, and `Ready` is written only after the owner
confirms. A title is not enough to shortlist on.

A round takes the most valuable issues that pass those checks, wherever they are. It does
not take one from each repository: that leaves `Ready` issues waiting in busy repositories
while quiet ones get make-work. Issues the owner marked `Ready` in an earlier round and
nobody built come first (round 4 review).

*Evidence: four repositories had no issue an agent session could start, and finding that
out took a read of every open issue. In the fourth round a shortlist picked from titles was
confirmed and marked `Ready`; four of its fourteen issues then had to be changed to
`Blocked` or closed as already met. One issue per repository meant five of eleven
repositories got real work and nine confirmed `Ready` issues were left unbuilt.*

## 5. Read an issue back before hashing or mirroring it

After writing an issue body through an agent session, read the stored body back from
GitHub and use that text for any mirror or hash. The session's GitHub connection appends a
`Generated by Claude Code` footer and moves an existing one to the end.

*Evidence: 161 mirrored issues all read back differently from what was sent.*

## 6. A person confirms scenarios before they count as acceptance

Scenarios written by an agent from an issue's text are drafts. Mark the issue
`Readiness: Draft` until a person has read the scenarios against the original detail and
changed the line to `Ready`. A builder may build a `Draft` issue only for a small,
reversible change, and says in the pull request that the scenarios were unreviewed.

*Evidence: about 180 issues were given two or three scenarios each from a short excerpt in
one pass.*

## 7. A review follow-up goes on the pull request, or is filed as blocked on it

When a review of an open pull request finds something to fix, fix it on that pull request's
branch. If it is filed as a separate issue instead, the issue's readiness line is
`Blocked (pull request N)` from the start, and it cannot be picked up until that pull
request merges.

*Evidence: in the second round four "smallest ready" issues in two repositories could not
be built, because the code they asked to change existed only on an unmerged branch.*

## 8. Each repository says what its checks need

`CHECKS.md` (in `docs/agent-settings/`, or `docs/` in Reddi Workbench) lists each check,
its command, what it needs and whether it runs in a cloud agent session with no machine
linked. Read it before choosing an issue: a session that cannot run an issue's check
cannot finish that issue. When a check cannot run where you are, say so in the pull
request and name the machine that has to run it.

The facts live in Reddi Workbench (`planning/repo-facts.json`) and are rendered by
`scripts/repo_facts.py`. When a session finds a fact is wrong, it corrects it there.

*Evidence: in four repositories the deciding check could not run in the cloud session
(native modules, a missing task tool, simulators, an image tool), and each time that was
found out only after the work was done.*

## 9. A repository without hosted CI has one check command

Where no hosted CI runs on pull requests, the repository names one command that runs
everything a builder can run locally. Its full output, with the commit it ran on, is
pasted into the pull request before merge. If part of it could not run, the command says
so and exits non-zero, and the pull request stays unmerged until a machine that can run
it has.

*Evidence: four repositories have no routine hosted CI; in each, "tests pass" in a pull
request was whatever the builder chose to run.*

## 10. The agent file says who builds and who reviews

Each repository's agent instructions carry one line naming who builds there and who
reviews, with the detail in `CHECKS.md`. One issue built to completion per round is not
the measure in a repository where the session only reviews, or where the next step is an
owner decision: there the session's work is the review or the prepared decision.

Where every open issue waits on the owner, the session's work for the round is to prepare
those decisions: for each, the question, the options, what each option commits to, and a
recommendation, in one place the owner can answer from.

*Evidence: one repository is built by Codex with Claude reviewing only, and another's
ready work was a visual audit awaiting the owner; treating both as "build one issue" gave
nothing to build. In the third round five of eleven repositories again had nothing a
session could start.*

## 11. The pull request says which check covers the change

A pull request names the check that would fail if the change were wrong, and says whether
that check ran and where. Green CI is evidence only for what it exercises. If no hosted
check covers the change, say so in those words; do not let a green tick stand in for it.

*Evidence: in the third round two pull requests had green CI that did not touch what they
changed: a display string read only by a browser smoke, and a documented command that no
workflow runs.*

## 12. One queue for what the workstation must run

When a pull request or issue stops on a check a cloud session cannot run, add the check to
`planning/workstation-queue.json` in Reddi Workbench: the repository, the ref, the command,
what to record and what it unblocks. `python3 scripts/workstation.py prompt` turns the
whole queue into one task for the workstation agent. Remove an item when its result is
recorded.

An item is sent once (round 4 review). `python3 scripts/workstation.py send LABEL` marks
the unsent items as batch LABEL and prints the prompt to hand over; commit the queue with
it. A later prompt holds only items added since. The session reads results from the
evidence branch itself, so the only reply the owner needs to pass on is "done, batch
LABEL". `done ID ...` removes the items whose result has been read. The queue holds checks only; anything that changes the machine, such as applying
settings, is a separate request the owner approves.

*Evidence: by the end of the third round seven results were waiting on the workstation,
asked for in four separate prompts. In the fourth round three prompts in an hour overlapped:
two items ran twice (one of them a nine-minute gate), and the owner relayed by hand results
the session had already read.*

## 13. Read the result before reporting it

A comment, an issue line or a pull request description states only what a command has
already shown. Run the command, read its output, then write. Do not post in the same step
as the command whose result the post describes, and do not write the expected result in
advance. If a posted statement turns out wrong, correct it in a new comment that says so.

For a pull request's check results, do not type them (round 4 review).
`python3 scripts/evidence.py run DIR LABEL -- COMMAND` runs one command and records its
output, exit code and commit; `python3 scripts/evidence.py block DIR` prints the section to
paste, built only from those records. A check with no record cannot appear in it.

*Evidence: in the fourth round a comment said no commit carried a file, posted before the
search output had been read; the file was on an open pull request's branch. In the third,
a pull request body said tests passed while one was failing. While this rule was being
rolled out, a pull request gave a file count of 1421 that the command had printed as 1420.*

## 14. Without hosted CI, the check runs on main at the end of each round

Where no hosted CI runs on the default branch, nothing notices when a merge leaves it
failing. At the end of a round, each such repository that had a merge gets its check
command queued on `main` once in the workstation queue (rule 12). A failure there is fixed
before the next round starts. Each repository's `CHECKS.md` says, under "After a merge",
whether this applies and where the check can run.

This was first written as "after every merge" and changed the same day (round 4 review):
each result allowed another merge, which queued another run.

*Evidence: one repository's quality gate had been failing on main since four documents were
added without a matching fixture entry. It was found only when an unrelated pull request
was sent to the workstation, and it blocked that pull request. Run per merge, the rule
produced three workstation prompts in an hour. Its first use also showed that one
repository's check could not run on the workstation at all.*

## 15. Know which tests no gate runs

A test file that no workflow, manifest or check command runs is not a check. Each
repository's `CHECKS.md` records, under "Tests no gate names", the result of
`python3 scripts/ungated_tests.py PROJECT_DIR`. The script lists candidates for a person
to read: it cannot see a runner that finds tests by convention. When a change touches
code whose tests are on that list, the pull request either adds them to a gate or says
they were run by hand (rule 11).

*Evidence: fifteen tests for a build verifier had been written, reviewed and merged without
any workflow or local gate running them. The audit that followed found candidates in five
of eleven repositories.*

## Keeping the copies in step

Ten repositories carry a copy of this page and a rendered `CHECKS.md`.
`python3 scripts/rollout.py status NAME=DIR ...` says which clones are behind;
`python3 scripts/rollout.py refresh NAME DIR` rewrites the copy, the `CHECKS.md` and the
README's pointer in one clone and prints the steps that repository needs before its pull
request. The README no longer lists the rules, so it does not change when one does.

*Evidence: one change to these rules took about fifteen pull requests across eleven
repositories, each refreshed by hand, and two copies were already a version behind.*
