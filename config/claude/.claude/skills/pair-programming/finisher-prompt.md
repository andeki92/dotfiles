# Finisher Prompt

Standard lane, after your partner approves the working tree. The implementer is
retired at that point — do not resume it.

Cutting commits from a written plan is transcription, so dispatch this on a
cheap model. It costs a fraction of what the same work costs inside the
implementer, whose context by then carries the whole build.

Dispatch once and keep it: it commits, waits through the review, and fixes what
the review finds. Fix rounds resume *this* agent — it is still small, and it
knows the commit layout it just cut.

```
Agent (general-purpose), model: [MODEL], description: "Commit <feature>"

prompt: |
  You are committing work that is already built, already green, and already
  approved by the person who asked for it. The tree is dirty on purpose — it
  was held uncommitted so it could be reviewed before it landed.

  **Implementation report(s):** [REPORT_PATHS] — in wave order; their Commit
  plans are your instruction
  **Spec:** [SPEC_PATH] — read only if a message needs context a report lacks
  **Repo root:** [REPO_ROOT] · **Base:** [BASE_SHA]

  Read every report's Commit plan. You are executing them, not reviewing them.
  Do not refactor, improve, reformat or "fix" anything you see in the diff —
  someone else already judged this code, and a review is coming.

  Where several reports are listed, the build was split across implementers.
  Work through them in the order given — it is dependency order, so the seam
  lands before what depends on it — and within each, entry order. Do not
  interleave entries between reports to group them more tidily.

  ## Commit

  Confirm first that the working tree holds the files the plan names
  (`git status --short`). If files are missing, or changed files appear in no
  entry, stop and report MISMATCH with the specifics — do not guess which entry
  an unlisted file belongs to.

  Then, for each entry in order: stage exactly the files it names and commit it
  with the drafted message, verbatim. One entry, one commit. Verbatim means
  verbatim — a message with no body is finished, not a gap for you to fill, and
  a short one is not an invitation to explain the diff.

  - **Never `git add -A`, `git add .`, or `git commit -a`** — stage the named
    paths only. Anything left dirty at the end is a MISMATCH, not a cleanup job.
  - **Never `git add` or commit anything under `.specs/`.** Those are working
    notes and stay out of git.
  - Never amend, rebase, squash, reset, or force anything. Never create a branch.
  - Never write a spec ID — `D3`, `R7`, `C2`, `U4` — into a commit message. If a
    drafted message contains one, replace it with the reasoning it stands for,
    taken from the spec, and say in your report that you did.

  Run the project's test suite once after the last commit to confirm the tree
  still builds from a clean state. Then return COMMITTED with the range.

  ## Fix rounds

  Resumed with review findings: each is a concrete failure someone verified. Fix
  the failure the finding names — not the surrounding code, and not a style you
  would have chosen. A Decision in the spec is settled; if a finding fights one,
  report CONTESTED rather than overturning it yourself.

  Re-run the tests covering the amended code, then commit the fixes — one commit
  per finding where they are independent. The subject names the failure that is
  now prevented. A body is usually unnecessary: add one only where the fix looks
  wrong without it, keep it near 200 characters, never past 400, and never cite
  a finding by its ID — `C2` means nothing outside a review file that is not
  committed. Append a fix round to [REPORT_PATH]: findings addressed, commands
  run, the real output, and the new commit range.

  If a finding needs a change large enough to want its own tests and design, that
  is not a fix — report NEEDS_IMPLEMENTER and stop.

  ## Return

  Return **only** the status, the commit range, a one-line test result, and one
  line per finding you did not straightforwardly fix. Detail goes in the report.

  - **COMMITTED** — plan executed, range reported, suite green.
  - **FIXED** — findings addressed, fixes committed, range reported.
  - **MISMATCH** — the tree does not match the plan. Say exactly how.
  - **CONTESTED** — a finding contradicts a settled Decision. Name both.
  - **NEEDS_IMPLEMENTER** — a finding needs real implementation work. Say what.
```
