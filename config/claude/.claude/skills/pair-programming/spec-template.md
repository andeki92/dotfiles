# Spec Template

Write to `<repo-root>/.specs/<YYYY-MM-DD>-<slug>/spec.md`.

Sections marked REQUIRED always appear — `spec-lint.py` fails without them. The
rest appear when they apply: an empty section is noise, a missing one that
applied is where a bug gets in. Scale each to its complexity; one line is fine
when one line is true. A small-lane spec is usually Problem, Non-goals,
Decisions, Requirements, Verification and nothing else.

When your partner says go — the gate in the standard lane, the spec review in
the small one — add `**Base:** <sha>` (`git rev-parse HEAD`) to the header in
the same edit that sets Status to `approved`. The review diff and the abort
path both start there; the linter requires it from `approved` on.

---

```markdown
# <Feature name>

**Date:** YYYY-MM-DD
**Repo:** <repo name> · **Branch:** <branch> · **Lane:** small | standard
**Status:** drafted | critiqued | approved | implemented | reviewed | abandoned

## Problem — REQUIRED

What is broken or missing today, and what makes it worth doing now. One
paragraph. Describe the situation, not the solution.

## Non-goals — REQUIRED

What this deliberately does not do, including the follow-up slices this one
defers. Each line is a fence the implementer must not climb.

- …

## Decisions — REQUIRED

Every fork you argued through, with the road not taken. Cite the principle a
decision follows or departs from. The implementer treats this table as binding
and does not re-litigate it. If nothing was contested, say `None contested.`
instead of leaving it empty — silence reads as nobody having looked.

| # | Decision | Why | Rejected alternative |
|---|---|---|---|
| D1 | … | … (follows P2) | … |

## Requirements — REQUIRED

EARS notation. One behaviour per requirement — one `shall`, no `should`, `will`
or `may`. Numbered so findings, tests and reviews can cite them; the numbers
are stable — a deleted requirement's number retires with it, gaps are fine,
renumbering breaks every citation.

| Pattern | Shape |
|---|---|
| Ubiquitous | The `<system>` shall `<response>` |
| Event-driven | When `<trigger>`, the `<system>` shall `<response>` |
| State-driven | While `<state>`, the `<system>` shall `<response>` |
| Unwanted behaviour | If `<condition>`, then the `<system>` shall `<response>` |
| Optional feature | Where `<feature>`, the `<system>` shall `<response>` |
| Complex | While `<state>`, when `<trigger>`, the `<system>` shall `<response>` |

`Verify by` is `test`, `inspection`, `analysis`, or `demonstration`. Prefer
`test:<path>::<name>` — naming the test makes coverage a string match rather
than a judgement call.

| # | Requirement | Verify by |
|---|---|---|
| R1 | When <trigger>, the <system> shall <response>. | test:tests/test_x.py::test_name |
| R2 | If <condition>, then the <system> shall <response>. | test:tests/test_x.py::test_other |
| R3 | The <system> shall <response>. | inspection |

## Architecture

Components involved and how data moves between them. Prose or a small diagram —
whichever is shorter for the shape being described.

Prefer references to real artifacts over fresh description: name the existing
function, schema, or test that already has the shape you mean, and for UI work
link a mockup — an HTML mockup beats a paragraph describing one.

### Subsystems

Standard lane, when the slice is fat enough to want more than one implementer.
Name the parts this splits into and what each owns. A subsystem is a boundary
you can write an interface across — not a folder, and not a layer you named
because layers exist.

Decide this here, with your partner, rather than leaving it to be discovered
later: it is a design fact about the feature, and the critic checks this section
against the real codebase, so naming it buys a free sanity check.

| Subsystem | Owns | Depends on |
|---|---|---|
| schema | migration, `db::` accessors | — |
| handlers | routing, request handling | schema |

`—` in Depends on means it can start immediately. Anything every subsystem
depends on is the seam: it is built first, alone, before the rest start.

### Files

Required in the standard lane — the critic checks these paths against the
codebase, so a spec without them loses its false-premise check.

| Path | Change | Responsibility |
|---|---|---|
| `src/…` | create / modify | … |

### Interfaces

Exact signatures the implementer must produce or consume, where later work
depends on the names.

**Required once Subsystems names more than one.** Separate implementers cannot
agree on a name they were never given, and an interface invented twice is the
cheapest kind of drift to prevent and the most tedious to repair. If you cannot
write the signature before either side exists, that is the boundary telling you
it is not one — merge the two subsystems and move on.

## Data and schema changes

New tables, columns, migrations, and what happens to rows that already exist.

## Failure modes and security

For each way this can go wrong, what the system does about it. Cover what
applies: invalid or hostile input, authentication and authorisation, secrets
handling, data exposure across users, resource exhaustion, partial failure and
retries, concurrent access.

| Scenario | Behaviour |
|---|---|
| … | … |

## Verification — REQUIRED

How this is known to work: the commands to run, and any manual check that
cannot be automated. The per-requirement tests live in the Requirements table;
this is what proves the whole thing hangs together.

## Open questions

Deliberately unresolved, with who decides and what it blocks. An empty list
means everything is settled — say so explicitly rather than deleting the
section, so a reader can tell a closed question from a forgotten one.

| # | Question | Decider | Blocks |
|---|---|---|---|
| Q1 | … | … | R… |

## Promote to principles

Decisions here that are general rather than about this feature — candidates for
`docs/principles.md`. Your partner decides when they sign off on the spec; you
propose.

- D2 → "…"

## Review Log

Standard lane. One line per finding from the critic and the reviewer, including
the ones not acted on. A silent dismissal is not a ruling.

| Finding | Source | Severity | Ruling |
|---|---|---|---|
| F1 … | critic | Blocking / Important / Advisory | fixed in R… / spec stands because … |
| C1 … | reviewer | Blocking / Important / Advisory | parked: real, nothing depends on it |
```
