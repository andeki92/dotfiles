# Standard lane

The dispatches in this lane are authorized by your partner invoking this skill
— do not quietly do the work inline instead. Run them synchronously
(`run_in_background: false`): every stage blocks on its result. Resume an
agent with SendMessage — a fresh Agent call starts cold and loses the context
the resume depends on.

Hand artifacts between stages **as file paths, never as pasted content**, and
name the model on every dispatch — an omitted model inherits your session's,
usually the most expensive one available. Critic: most capable. Implementer:
scale to the work. Reviewer: scale to the diff. Finisher: cheap.

**An agent's every turn re-bills its whole context, so a long-lived agent gets
expensive faster than it gets useful.** The implementer is the one that grows —
it holds the build — so its life is deliberately short: it builds and commits
unit by unit, then stops once the tree is shown and approved — there is nothing
left for it to do. Fixing a review finding runs in a separate, fresh-or-resumed
finisher that starts from the diff and the finding, not from the whole build's
history. Resume an agent to keep context it genuinely needs — the finisher
across fix rounds in one review cycle; retire it the moment the next job can be
done from what is written down.

## 1. The critic

Dispatch immediately after the linter is clean, on the most capable model
available — this is the judgement step. Do not ask permission first; your
partner reviews a hardened spec, not a draft.

Use [critic-prompt.md](critic-prompt.md), filling every bracketed value it
names — spec, findings, repo root, and the principles file if the repo has one.
It reads the code the spec claims things about, and it only looks for what
judgement can find — the linter already took the mechanical half.

- **Blocking** and **Important**: fix them in the spec, then re-run the linter.
- Findings you disagree with: leave the spec alone and record the ruling in the
  Review Log — what was flagged, why the spec stands.
- **Advisory**: record in the Review Log, unfixed.
- Anything that changes what the feature *does* is not yours to settle. It goes
  to the gate as an open decision.

## 2. The gate

Stop. Present the spec path; the findings, one line each, with what you did
about it; anything that changes behaviour, as a question; and any Decision worth
promoting to `principles.md`.

Then wait. Do not write code or dispatch an implementer until your partner says
go. When they do, mark the spec `approved` with its `Base` sha as the template
describes — the review diff and the abort path both start there.

## 3. The implementer

Work happens on the current branch; do not create one unless your partner asks.

Settle how many implementers this takes first (below) — usually one. Then
dispatch [implementer-prompt.md](implementer-prompt.md) with the spec path and a
report path. Each returns its unit list as `PLAN_PROPOSED` and stops before
writing code. Check the list yourself — every `R` carried, no Non-goal climbed,
each unit worth committing alone — then approve or correct it and resume that
same agent.

### One implementer, or several

Default to one. A single implementer that stays under about 150k is cheaper and
more coherent than any split, and most slices are that size. Split only when the
spec's **Subsystems** table names more than one — your partner settled that at
Stage 1, so you are reading a decision here, not making one.

The split buys two different things, and you can take the first without the
second:

| | What it buys | What it costs |
|---|---|---|
| **A fresh implementer per subsystem, dispatched in sequence** | The tokens. Each starts cold and finishes before it grows; three agents peaking at 120k cost a fraction of one reaching 500k, because every turn re-bills the whole context. | One dispatch per subsystem, each re-reading the spec and its corner of the code. |
| **Running independent subsystems at the same time** | The clock, and nothing else. An agent's context is identical either way, so this saves no tokens at all. | They share one working tree, so their files must be genuinely disjoint. Concurrent test runs contend on the project's build lock — in a language that compiles a whole crate per run, this can hand back most of the clock it saved. |

Take the sequential win by default; add concurrency only where the subsystems
share no files and running two suites at once is actually faster. Check that
last part rather than assuming it.

**The seam goes first.** Whatever every subsystem depends on — shared types,
helpers, the migration — is built alone, in the first wave, before any other
implementer starts. Later workers then build against compiled code instead of a
described contract, which turns a disagreement about an interface into a
compile error rather than a review finding.

**Against the split.** Every worker you add is a dialect: separate agents
reinvent helpers, name the same concept two ways, and drift apart in style —
and the reviewer's Fit and Scope checks then spend their attention on damage you
chose to cause. Coordination grows as the square of the workers, so three is a
plan and eight is a project. If a subsystem is less than about a fifth of the
work, fold it into its neighbour; the cold start costs more than the split saves.

Each implementer writes its own `report-<subsystem>.md` and is scoped to its own
units and files. Approve each unit list the same way you approve one.

| It returns | You do |
|---|---|
| `DONE` | Confirm the suite output is in the report and the tree is committed — each unit landed as its own commit during the build, any post-suite residual as a trailing one — then show the work (next stage). |
| `DONE_WITH_CONCERNS` | Correctness or scope: hand the concern to the reviewer. Observations: note and proceed. |
| `NEEDS_CONTEXT` | Answer and resume. If the answer is an Open question, it is your partner's. |
| `BLOCKED` | Missing context → resume with it. Needs more reasoning → fresh agent, one tier up. Too large → split the unit list. **Spec is wrong** → stop, take it to your partner. |

Never re-dispatch the same model with the same prompt. If it said it was stuck,
something has to change.

## 4. Show the work

The implementer returns `DONE` with a green suite and a fully committed tree —
each unit landed as its own commit while it was built. Show your partner what
got built: `git log --oneline <Base>..HEAD`, `git diff --stat <Base>..HEAD`,
the hunks worth reading or the paths to open, the test output, one line per
unit. Ask what they would change.

This is the pairing loop, and it is cheap on purpose. Hand each piece of
feedback to the resumed implementer verbatim; it applies, re-runs the covering
tests, commits the change as a new commit, and you show the result again — as
many rounds as the work needs. Where the build was split, show the tree as one
piece of work and route each note to the implementer that owns those files; a
worker that has already returned `DONE` is resumed only if the feedback lands
in its subsystem.
Feedback here is part of the build, not a new spec run: it touches the spec
only when it overturns a settled Decision or adds behaviour no requirement
covers, and then as a one-line edit to the table, not a return to Stage 1.

When your partner is happy, the tree is already fully committed — there is
nothing left to cut. Retire the implementer(s); an implementer is by now the
most expensive agent in the run, and everything left to do from here either
already landed or belongs to the review stage next.

## 5. The review

Run `spec-lint.py --verify <spec>` first — it settles requirement coverage and
missing test files for free. Then package the diff as one file and dispatch
[reviewer-prompt.md](reviewer-prompt.md) with the spec, report, diff and review
paths:

```bash
{ git log --oneline BASE..HEAD; echo; git diff --stat BASE..HEAD; echo; git diff -U10 BASE..HEAD; } > <artifacts>/diff-1.txt
```

On this cycle's first Blocking or Important finding, dispatch a fresh
[finisher](finisher-prompt.md) on a cheap model, scoped to that finding, with
the spec, repo root, `Base` sha, the diff, the finding text, and a report path
to append fix rounds to — never the implementer, which is retired. Every later finding in the same cycle, whether
from this round or the next, resumes that same finisher rather than a fresh
dispatch, so it keeps the context of what it already tried. Advisory findings
go in the Review Log, not to the finisher.

It fixes, re-runs the covering tests and the linter, lands the fix as a new
commit, and appends the round to its report. `NEEDS_IMPLEMENTER` means the
finding is real implementation work, not a fix: dispatch a fresh implementer
scoped to that finding alone. `CONTESTED` is your partner's call, not yours.

Re-review only the fix diff, and only when
something Blocking was in the round — on a cheap tier when the fix is
mechanical, at the original reviewer's tier when the finding was security,
concurrency, or subtle correctness; the smallest diffs carry the highest-stakes
judgements. Important fixes are taken on the finisher's word: re-verification
is spent only where merging broken code is the risk.

Two rounds maximum. Then rule on whatever is still open, recording each ruling
in the Review Log: contestable or nothing depends on it → park it with the
reasoning; real and load-bearing, or it exposes a defect in the spec → stop and
take it to your partner with the fix history.

Never fix findings yourself — a controller's fix skips review and fills the
context you need to coordinate.
