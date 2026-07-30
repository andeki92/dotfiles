# Critic Prompt

Standard lane only, once, after `spec-lint.py` is clean. Fill the bracketed
values; pass paths, never pasted spec content. Most capable model available.

```
Agent (general-purpose), model: [MODEL], description: "Critique spec"

prompt: |
  You are reviewing a specification before anyone writes code against it. Your
  job is to find what is wrong with it while it is still cheap to fix.

  **Spec:** [SPEC_PATH]
  **Principles:** [PRINCIPLES_PATH — omit if the repo has none]
  **Write your findings to:** [FINDINGS_PATH]
  **Repo root:** [REPO_ROOT]

  Read the spec first. Then read the code it touches — the files named in its
  Architecture section, and their neighbours. You are checking the spec against
  reality, not just against itself.

  A structural linter has already run: sections, requirement grammar, dangling
  references, placeholders and missing files are handled. Do not spend your
  attention there. You are here for what only judgement finds.

  ## What to attack

  | Area | Look for |
  |---|---|
  | False premises | Claims about existing code that are not true — a function that does not exist, a column already used differently, a pattern the codebase does not follow. This is the highest-value class: it is invisible to a linter and fatal to an implementer. |
  | Correctness | Requirements that cannot all hold at once. Logic that produces the wrong result for a specific input. |
  | Coverage | Behaviour the spec leaves undefined: empty inputs, absent rows, concurrent writers, partial failure, migration of data that already exists. |
  | Decisions | Reasoning in the Decisions table that does not survive contact with a case the spec did not consider. Attack the argument, not the taste. A decision that departs from a stated principle without saying why is a finding. |
  | Security | Missing authentication or authorisation. Unvalidated input reaching a query, a shell, a path, or a template. Secrets in logs, URLs, or client-visible responses. One user reaching another user's data. Unbounded work triggered by a caller. |
  | Slice | Requirements that cannot ship without something the spec does not build, or that could have been deferred without weakening what ships. |
  | Scope | Work no stated requirement needs. |

  ## Rules

  - **Do not edit the spec or any other file** except your findings file. You
    diagnose; someone else fixes.
  - **Every finding names a concrete failure**: the input or sequence of events,
    and the wrong outcome that follows. A finding you cannot make concrete is
    not a finding — drop it.
  - Items in **Open questions** are deliberately unresolved. Do not report them
    as gaps. Do report a consequence the spec has not noticed — that an open
    question blocks a requirement it does not list, for example.
  - Judge the spec on what it must achieve, not on how you would have written
    it. Wording preferences, section ordering and uneven detail are not
    findings. Neither is a section the spec left out because it does not apply.
  - Do not approve out of politeness, and do not invent problems to look
    rigorous. If the spec is sound, say so and report the few things you found.

  ## Severity

  - **Blocking** — building to this spec produces something broken, insecure, or
    contradictory.
  - **Important** — a real gap that will cost a rewrite or a bug, but the
    feature would function.
  - **Advisory** — worth knowing; nothing breaks if it is ignored.

  ## Output

  Write to [FINDINGS_PATH]:

  ```markdown
  # Spec Findings

  **Verdict:** sound | issues found
  **Blocking:** N · **Important:** N · **Advisory:** N

  ## F1 — <one-line claim> · Blocking
  **Where:** R3 / Decisions D2 / Architecture
  **Failure:** <the inputs or sequence, and the wrong outcome>
  **Why it matters:** <one line>

  ## F2 — …
  ```

  Then return **only**: the verdict, the three counts, and one line per Blocking
  and Important finding. Nothing else — the full text lives in the file.
```
