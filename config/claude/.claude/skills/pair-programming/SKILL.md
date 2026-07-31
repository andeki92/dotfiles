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
apply are absent, not empty. The template carries the EARS patterns, the
numbering rules, and the `Base` sha procedure — follow it rather than
reconstructing them from memory.

Then run the linter that sits beside this file and fix everything it prints,
until it is clean — each message says what is wrong and why it matters:

```bash
python3 <this skill's directory>/spec-lint.py <spec path>
```

A model never gets paid to find what a string match finds.

## Small lane

Show your partner the spec — settled lines, requirements, one line on what you
are about to do — and build it once they say go, marking the spec `approved`
with its `Base` sha as the template describes. Write the test first, watch it
fail, write the code, watch it pass — and stop short of committing.

Show the work: the diff, the test output, what you would still polish. Ask
what they would change, and fold each answer straight back into the code.
Feedback on uncommitted work is the pairing loop, not a new spec run — it
touches the spec only when it overturns a Decision or adds a requirement, and
then as a one-line edit, not a return to Stage 1. Commit when your partner
says it is good, then run `spec-lint.py --verify <spec>` and set `**Status:**`
to `reviewed` — the suite and the linter are the review, so the small lane
skips `critiqued` and `implemented`.

No critic, no reviewer, no subagents. If it turns out mid-build to be bigger
than one commit, stop and move it to the standard lane.

## Standard lane

The five stages — critic, gate, implementer, show the work, review — live in
[standard-lane.md](standard-lane.md). Read it when the lane is standard, not
before.

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

`**Status:**` in the spec is `drafted → critiqued → approved → implemented →
reviewed`, or `abandoned` from anywhere in the chain. Set it in the same edit
that closes the stage; with the files present it tells you where to resume when
your context no longer does.

## Red flags

| Thought | Reality |
|---|---|
| "I'll lay out three approaches and let them pick" | That is the workshop, not the chair. Take a position; let them argue you out of it. |
| "Standard lane is the safe default" | Four model passes to protect a two-line diff is not caution, it is the thing this skill was rewritten to stop. |
| "This is too small to spec" | Then the spec is five lines and the lane is small. Write it anyway. |
| "We've come this far, we might as well finish" | Sunk cost is the failure this skill replaced. Reset to `Base`, mark it `abandoned`, and the afternoon is saved. |
