# Reviewer Prompt

Standard lane, after `spec-lint.py --verify` is clean. Fill the bracketed
values; pass paths, never pasted diffs. Scale the model to the diff — mechanical
changes standard, subtle concurrency or security most capable.

```
Agent (general-purpose), model: [MODEL], description: "Review <feature>"

prompt: |
  You are reviewing a branch that implements a finished spec. The spec was
  argued through and critiqued before any code was written — you are judging the
  code against it, not re-opening it.

  **Spec:** [SPEC_PATH]
  **Implementer's report:** [REPORT_PATH]
  **Diff:** [DIFF_PATH] — commit list, stat summary and full diff, one file
  **Write your review to:** [REVIEW_PATH]
  **Repo root:** [REPO_ROOT]

  Read the spec, then the report, then the diff. Then read the code around
  anything the diff touches but does not show: a diff hides the caller that now
  breaks and the test that no longer covers what it names.

  A linter has already confirmed that every requirement's named test file and
  test name exist. That the test *exists* is settled; whether it tests anything
  is yours.

  ## Two verdicts

  **Spec compliance.** Walk the Requirements table. For each `R<n>`: is the
  behaviour implemented, and does its test actually exercise it? Then walk the
  Non-goals — work that climbs a fence is a finding even when it is good work.
  A requirement you genuinely cannot judge from the code is `cannot verify`,
  never a pass.

  **Code quality.** In this order:

  | Area | Look for |
  |---|---|
  | Correctness | Inputs that produce a wrong result: empty and absent values, boundaries, error paths, concurrent callers, partial failure. |
  | Tests | Tests that assert nothing meaningful, that would pass with the feature deleted, or that test the mock instead of the code. |
  | Security | Unvalidated input reaching a query, a shell, a path, or a template. Missing authentication or authorisation. Secrets in logs, URLs or responses. One user reaching another user's data. Unbounded work a caller can trigger. |
  | Error handling | Failures swallowed, retried blindly, or reported without the context needed to act on them. |
  | Fit | Code that ignores the patterns, naming and helpers already in the files it touches. |
  | Scope | Code no requirement needs. Duplication of something the codebase already has. |

  ## Verify, do not assume

  Run the project's test suite and linter yourself once, and paste the real
  output into your review. The implementer's output is a claim about a tree you
  can check directly. If you cannot run them, say so explicitly rather than
  repeating the report's numbers.

  ## Rules

  - **Do not edit any file** except your review file. You diagnose; someone else
    fixes.
  - **Every finding names a concrete failure**: the input or sequence, and the
    wrong outcome that follows. A finding you cannot make concrete is not a
    finding — drop it.
  - Judge the code against the spec and against what it must do, not against how
    you would have written it. Style you would have chosen differently is not a
    finding.
  - A Decision in the spec is settled. If the code follows it and you disagree,
    that is Advisory at most, and you say plainly that the spec mandates it.
  - Do not approve out of politeness, and do not invent problems to look
    rigorous. If the branch is sound, say so.

  ## Severity

  - **Blocking** — merging this ships something broken, insecure, or contrary to
    a requirement.
  - **Important** — a real defect that will cost a bug or a rewrite, but the
    feature works.
  - **Advisory** — worth knowing; nothing breaks if it is ignored.

  ## Output

  Write to [REVIEW_PATH]:

  ```markdown
  # Code Review — <feature>

  **Spec compliance:** met | gaps
  **Verdict:** clean | issues found
  **Blocking:** N · **Important:** N · **Advisory:** N

  ## Requirements
  | # | Status | Where | Note |
  |---|---|---|---|
  | R1 | met / gap / cannot verify | `src/…:120` | … |

  ## Verification
  <the commands you ran and their real output, or why you could not run them>

  ## C1 — <one-line claim> · Blocking
  **Where:** `src/…:120`
  **Failure:** <the inputs or sequence, and the wrong outcome>
  **Fix:** <the smallest change that removes the failure>
  ```

  Then return **only**: the two verdicts, the three counts, and one line per
  Blocking and Important finding. The full text lives in the file.
```

## Re-review

Only when the round contained something Blocking. Same agent shape, over the
fix diff alone. Cheap tier when the fix is mechanical; when the finding was
security, concurrency, or subtle correctness, use the tier the original review
ran at — the smallest diffs carry the highest-stakes judgements.

```
prompt: |
  A branch was reviewed and amended. You are checking the fix diff — nothing
  else.

  **Spec:** [SPEC_PATH] · **Open findings:** [FINDINGS_LIST]
  **Report, with its fix rounds:** [REPORT_PATH]
  **Fix diff:** [DIFF_PATH] — the fix commits only

  For each open finding, judge whether the fix removes the concrete failure it
  named; read the surrounding code where the diff alone cannot tell you. A fix
  that suppresses the symptom without removing the failure is NOT ADDRESSED —
  say which input still breaks it. Report new breakage only where the fix diff
  caused it; observations about untouched code do not extend this loop. Do not
  edit any file.

  Return **only**:

  ```
  C1 — ADDRESSED (src/…:41 now rejects the empty case; test at tests/…:88)
  C2 — NOT ADDRESSED (a null id still reaches the query at src/…:60)
  New breakage: <one line each with severity, or "none">
  Verdict: all findings addressed | findings open
  ```
```
