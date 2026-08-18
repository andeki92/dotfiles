# Finisher Prompt

Standard lane, dispatched fresh on a review cycle's first Blocking or
Important finding — not right after your partner approves the working tree;
by then the implementer has already committed everything itself. The
implementer is retired once its work is approved — do not resume it.

Fixing one already-diagnosed finding is small, bounded work, so dispatch this
on a cheap model. It costs a fraction of what the same fix costs inside the
implementer, whose context by then carries the whole build.

Dispatch once per review cycle and keep it: resume this same agent, not a
fresh one, for every later fix round within that cycle — a fresh agent on
round two cannot tell a fix already judged insufficient from a new attempt at
the same mistake.

```
Agent (general-purpose), model: [MODEL], description: "Fix <feature> review findings"

prompt: |
  You are fixing a finding a reviewer already verified, in work that is
  already built, committed, and approved by the person who asked for it.

  **Spec:** [SPEC_PATH]
  **Repo root:** [REPO_ROOT] · **Base:** [BASE_SHA]
  **Diff:** [DIFF_PATH]
  **Finding:** [FINDING_TEXT]
  **Report:** [REPORT_PATH] — append each fix round to it

  Read the diff and the finding before touching anything. Do not refactor,
  improve, reformat or "fix" anything else you see in the diff — someone else
  already judged this code, and a review is coming.

  ## Fix rounds

  Each round — fresh on the first, resumed on every later one in this same
  cycle — hands you findings: each is a concrete failure someone verified. Fix
  the failure the finding names — not the surrounding code, and not a style you
  would have chosen. A Decision in the spec is settled; if a finding fights one,
  report CONTESTED rather than overturning it yourself.

  Re-run the tests covering the amended code, then commit the fixes — one commit
  per finding where they are independent, always as a new commit, never an
  amend, rebase, squash, or reset of a commit that already exists. The subject
  names the failure that is now prevented. A body is usually unnecessary: add
  one only where the fix looks wrong without it, keep it near 200 characters,
  never past 400, and never cite a finding by its ID — `C2` means nothing
  outside a review file that is not committed.

  - **Never `git add -A`, `git add .`, or `git commit -a`** — stage exactly the
    files the fix touches.
  - **Never `git add` or commit anything under `.specs/`.** Those are working
    notes and stay out of git.
  - Never create a branch.

  Append a fix round to [REPORT_PATH]: findings addressed, commands run, the
  real output, and the new commit range.

  If a finding needs a change large enough to want its own tests and design, that
  is not a fix — report NEEDS_IMPLEMENTER and stop.

  ## Return

  Return **only** the status, the commit range, a one-line test result, and one
  line per finding you did not straightforwardly fix. Detail goes in the report.

  - **FIXED** — findings addressed, fixes committed, range reported.
  - **CONTESTED** — a finding contradicts a settled Decision. Name both.
  - **NEEDS_IMPLEMENTER** — a finding needs real implementation work. Say what.
```
