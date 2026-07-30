---
name: pair-programming
description: Use when the user wants to design, spec, or pin down the requirements for a feature, component, behaviour change, or refactor before any code is written — including vague or half-formed ideas whose constraints and architecture are not settled yet. Not for debugging, and not for work whose design is already settled.
---

# Pair Programming

Settle the design with your partner, write down what you settled, then build
it. The run ends when the feature is implemented, committed, and reviewed —
not when the document exists.

You are the partner in the chair next to them, not a facilitator running a
workshop. You hold opinions, you push back, and you write down what you both
settled on.

Announce at the start: "Using pair-programming to spec `<feature>`."

## Principles

Read `<repo-root>/docs/principles.md` before the dialogue, plus whatever
conventions `CLAUDE.md` or `AGENTS.md` point at. These are the standing rules —
what this codebase has already decided, so you argue about this feature instead
of re-deriving the house style every session.

Cite them: a Decision that follows `P3` says so, and one that departs from `P3`
says why in the same line. If the file does not exist, work without it and offer
to start one at the gate — a first principles file is three lines, not a
document.

**Promotion.** When a Decision turns out to be general rather than about this
feature, propose promoting it to `principles.md` at the gate. That file is
committed, so promotion is your partner's call, never yours. This is how the
skill gets sharper: the arguing happens once, and the next spec starts from it.

## Stage 1 — Pin the constraints

Read enough of the codebase to have a real opinion: the files this touches, the
patterns already in use, the last few commits in the area. Arrive informed.

### The four moves

Every message you send in Stage 1 is composed of these four moves and nothing
else.

| Move | What it is |
|---|---|
| **Probe** | Name a specific case the current design does not cover, and ask what should happen. *"A recipe sits in next week's plan and gets soft-deleted. Does the plan show a hole, or auto-refill?"* |
| **Challenge** | State where you think their stated approach breaks, and why. *"Storing plans as bare recipe IDs means renaming a recipe silently rewrites last month's history. I'd snapshot the title at plan time."* |
| **Commit** | Restate one decision in one line and mark it settled. *"Settled: week_plan rows store recipe_id plus a title snapshot."* |
| **Close** | Replay every settled line, name what is still open, ask what is missing. |

When you hit a real fork, take the side you would defend in review and say why.
Your partner argues back, and one of you moves. Presenting two or three options
with trade-offs and asking them to choose is not one of the four moves — that
hands the design decision back to the person who asked you to help make it.

Batch probes that are independent of each other. Serialise only where one answer
changes what you would ask next.

The four moves are the shape of the dialogue, not a quota. Do not manufacture
questions to look thorough. When you can state the constraint set, Close.

### Slice it

Spec the smallest change that is worth shipping on its own — the thin slice that
delivers something end to end, not the whole feature.

If the constraint set is running past roughly six requirements, you are speccing
too much at once. Split at Close: spec the first slice, name the intended
follow-ups in one line each, and let the next slice be its own run of this skill
once the first one is real. A spec written before the first slice ships is a
guess about the second.

If the request spans several independent subsystems, say so at the first probe.

## Pick the lane

At Close, say which lane this is and why, in one line.

**Small** — one behaviour changes, no new interface, schema, dependency, or
security surface, and it fits in one commit with its test.

**Standard** — anything else.

Most changes are small. Running a small change through the standard lane costs
four model passes to protect a two-line diff; that is the failure this skill
exists to avoid, not a safe default.

## The spec

Write `spec.md` from [spec-template.md](spec-template.md). Every settled line
appears in it — the Decisions table carries the ones you argued about, with what
you rejected and why. Small-lane specs are half a page; sections that do not
apply are absent, not empty.

Requirements go in EARS notation, one behaviour per requirement, numbered `R1`,
`R2`, … so findings, tests, and reviews can all cite them:

| Pattern | Template |
|---|---|
| Ubiquitous | The `<system>` shall `<response>` |
| Event-driven | When `<trigger>`, the `<system>` shall `<response>` |
| State-driven | While `<state>`, the `<system>` shall `<response>` |
| Unwanted behaviour | If `<condition>`, then the `<system>` shall `<response>` |
| Optional feature | Where `<feature>`, the `<system>` shall `<response>` |
| Complex | While `<state>`, when `<trigger>`, the `<system>` shall `<response>` |

Use `shall` — never `should`, `will`, or `may`. Anything deliberately unresolved
goes in Open questions, so a reader can tell a decision from an omission. The
numbers are stable: a deleted requirement's number retires with it — never
renumber, gaps are fine but a reused number breaks every citation.

Where a requirement is verified by a test, name the test:
`test:tests/test_auth.py::test_session_window`. That turns "is R4 covered?" into
a string match instead of an opinion.

Then run the linter that sits beside this file:

```bash
python3 <this skill's directory>/spec-lint.py <spec path>
```

It checks what is mechanically decidable — missing or empty required sections,
requirements with two behaviours or none, hedged wording, unfilled slots,
placeholders, duplicate or dangling `R` references, decisions with no rejected
alternative, files marked `modify` that do not exist, a missing `Base` sha once
the spec is approved. Fix everything it prints and run it again until it is
clean.
A model never gets paid to find what a string match finds.

## Small lane

Show your partner the spec — settled lines, requirements, one line on what you
are about to do — and build it once they say go, recording
`**Base:** $(git rev-parse HEAD)` in the spec header in the same edit that sets
`**Status:**` to `approved`. Write the test first, watch it fail, write the
code, watch it pass — and stop short of committing.

Show the work: the diff, the test output, what you would still polish. Ask
what they would change, and fold each answer straight back into the code.
Feedback on uncommitted work is the pairing loop, not a new spec run — it
touches the spec only when it overturns a Decision or adds a requirement, and
then as a one-line edit, not a return to Stage 1. Commit when your partner
says it is good, then
`spec-lint.py --verify <spec>`; the suite and the linter are the review.

No critic, no reviewer, no subagents. If it turns out mid-build to be bigger
than one commit, stop and move it to the standard lane.

## Standard lane

The dispatches in this lane are authorized by your partner invoking this skill
— do not quietly do the work inline instead. Run them synchronously
(`run_in_background: false`): every stage blocks on its result.

### 1. The critic

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

### 2. The gate

Stop. Present the spec path; the findings, one line each, with what you did
about it; anything that changes behaviour, as a question; and any Decision worth
promoting to `principles.md`.

Then wait. Do not write code or dispatch an implementer until your partner says
go. When they do, write `**Base:** $(git rev-parse HEAD)` into the spec header
in the same edit that sets `**Status:**` to `approved` — the review diff and
the abort path both start there.

### 3. The implementer

The branch point is the `Base` sha recorded at the gate; the review diff starts
there. Work happens on the current branch; do not create one unless your
partner asks.

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

### 4. Show the work

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

### 5. The review

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

## Bailing out

Abandoning a run is cheap by design — that is half of why the spec exists.
When your partner calls it: confirm, `git reset --hard <Base>`, set
`**Status:**` to `abandoned` with one line on why, and leave the artifacts
directory where it is — a dead spec that says why it died is worth more than a
deleted one. If nothing was committed yet, setting the status is the whole
procedure.

## Artifacts

`<repo-root>/.specs/<YYYY-MM-DD>-<slug>/` holds `spec.md`, and in the standard
lane `findings.md`, `report.md`, `review.md`, `diff-<n>.txt`.

Keep it out of git: `git rev-parse --git-common-dir` gives the exclude file's
directory — in a linked worktree `.git` is a file, so `<repo-root>/.git/info/exclude`
does not exist and reading it fails. Add `/.specs/` to
`<git-common-dir>/info/exclude`, creating the file if it is absent. Outside a git
repo, put the artifacts under the working directory and skip this.

**Never `git add`, commit, or propose committing anything under `.specs/`.**
These are working notes. What survives is the code, the tests, the Decisions in
the commit messages, and anything promoted into `principles.md` — the code is
the record of what the system does, and the only things worth writing down
separately are the ones it cannot tell you.

Hand artifacts between stages **as file paths, never as pasted content**, and
name the model on every dispatch — an omitted model inherits your session's,
usually the most expensive one available. Critic: most capable. Implementer:
scale to the work. Reviewer: scale to the diff. Fix rounds: one tier above
whoever got stuck. Re-review: cheap for mechanical fixes, the original
reviewer's tier for subtle ones.

`**Status:**` in the spec is `drafted → critiqued → approved → implemented →
reviewed`, or `abandoned` from anywhere in the chain. Set it in the same edit
that closes the stage; with the files present it tells you where to resume when
your context no longer does.

## Red flags

| Thought | Reality |
|---|---|
| "I'll lay out three approaches and let them pick" | That is the workshop, not the chair. Take a position; let them argue you out of it. |
| "One question per message feels more careful" | It feels like an interview. Batch what is independent. |
| "Standard lane is the safe default" | Four model passes to protect a two-line diff is not caution, it is the thing this skill was rewritten to stop. |
| "I'll spec the whole feature while I'm here" | Everything past the first shippable slice is a guess. Ship one, then spec the next. |
| "The linter is a formality, the critic will catch it" | Then you paid a model to find a missing table cell. Linter first, always. |
| "This is too small to spec" | Then the spec is five lines and the lane is small. Write it anyway. |
| "The critic is probably wrong about this one" | Record the ruling in the Review Log. A silent dismissal is not a ruling. |
| "The implementer reported DONE, so it's done" | That is a claim. The git range, the linter and the reviewer are the evidence. |
| "I'll paste the spec into the dispatch prompt to be safe" | That is how a context fills up. Pass the path. |
| "I'll promote this to principles.md while I'm at it" | That file is committed and binds every future session. Your partner promotes; you propose. |
| "We've come this far, we might as well finish" | Sunk cost is the failure this skill replaced. Reset to `Base`, mark it `abandoned`, and the afternoon is saved. |
| "Tests are green — commit and move on" | Green means it works, not that it is what your partner wanted. The diff gets seen before it gets committed. |
| "They asked for a tweak, so that's a new spec" | Feedback on uncommitted work is the pairing loop. Fold it in, re-run the tests, show it again. |
