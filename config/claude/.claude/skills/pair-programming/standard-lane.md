# Standard lane

The dispatches in this lane are authorized by your partner invoking this skill
— do not quietly do the work inline instead. Run them synchronously
(`run_in_background: false`): every stage blocks on its result. Resume an
agent with SendMessage — a fresh Agent call starts cold and loses the context
the resume depends on.

Hand artifacts between stages **as file paths, never as pasted content**, and
name the model on every dispatch — an omitted model inherits your session's,
usually the most expensive one available. Critic: most capable. Implementer:
scale to the work. Reviewer: scale to the diff. Fix rounds: one tier above
whoever got stuck.

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

Dispatch [implementer-prompt.md](implementer-prompt.md) with the spec path and
the report path. It returns its unit list as `PLAN_PROPOSED` and stops before
writing code. Check the list yourself — every `R` carried, no Non-goal climbed,
each unit worth committing alone — then approve or correct it and resume the
same agent.

| It returns | You do |
|---|---|
| `DONE` | Confirm the suite output is in the report and the tree holds the work uncommitted, then show the work (next stage). |
| `DONE_WITH_CONCERNS` | Correctness or scope: hand the concern to the reviewer. Observations: note and proceed. |
| `COMMITTED` | Verify the commits exist (`git log --oneline <Base>..HEAD`), then review. |
| `NEEDS_CONTEXT` | Answer and resume. If the answer is an Open question, it is your partner's. |
| `BLOCKED` | Missing context → resume with it. Needs more reasoning → fresh agent, one tier up. Too large → split the unit list. **Spec is wrong** → stop, take it to your partner. |

Never re-dispatch the same model with the same prompt. If it said it was stuck,
something has to change.

## 4. Show the work

The implementer returns `DONE` with a green suite and an uncommitted tree —
that is deliberate. Before anything lands in git, show your partner what got
built: `git diff --stat`, the hunks worth reading or the paths to open, the
test output, one line per unit. Ask what they would change.

This is the pairing loop, and it is cheap on purpose. Hand each piece of
feedback to the resumed implementer verbatim; it applies, re-runs the covering
tests, and you show the result again — as many rounds as the work needs.
Feedback here is part of the build, not a new spec run: it touches the spec
only when it overturns a settled Decision or adds behaviour no requirement
covers, and then as a one-line edit to the table, not a return to Stage 1.

When your partner is happy, resume the implementer with the approval. It
commits unit by unit and returns `COMMITTED`.

## 5. The review

Run `spec-lint.py --verify <spec>` first — it settles requirement coverage and
missing test files for free. Then package the diff as one file and dispatch
[reviewer-prompt.md](reviewer-prompt.md) with the spec, report, diff and review
paths:

```bash
{ git log --oneline BASE..HEAD; echo; git diff --stat BASE..HEAD; echo; git diff -U10 BASE..HEAD; } > <artifacts>/diff-1.txt
```

Blocking and Important findings go back to the implementer verbatim; Advisory
findings go in the Review Log. It fixes, re-runs the covering tests and the
linter, and appends to its report. Re-review only the fix diff, and only when
something Blocking was in the round — on a cheap tier when the fix is
mechanical, at the original reviewer's tier when the finding was security,
concurrency, or subtle correctness; the smallest diffs carry the highest-stakes
judgements. Important fixes are taken on the implementer's word: re-verification
is spent only where merging broken code is the risk.

Two rounds maximum. Then rule on whatever is still open, recording each ruling
in the Review Log: contestable or nothing depends on it → park it with the
reasoning; real and load-bearing, or it exposes a defect in the spec → stop and
take it to your partner with the fix history.

Never fix findings yourself — a controller's fix skips review and fills the
context you need to coordinate.
