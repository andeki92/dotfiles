# ideas

Capture and pick up backlog ideas as GitHub or GitLab issues.

Stowed: `config/ideas/.local/bin/ideas` → `~/.local/bin/ideas`.

The binary is `ideas`, plural, because `idea` is already taken: IntelliJ IDEA's
cask installs its launcher at `/opt/homebrew/bin/idea`.

The companion Claude skill lives in the `claude` module, at
`config/claude/.claude/skills/idea/SKILL.md` → `~/.claude/skills/idea/`.

## Why issues rather than a file

A backlog kept in a markdown file cannot say what is already being worked on.
Every local-file scheme for that — a status field, a lock file, a committed
flag read across branches — relies on some script remembering to write
something, and each one has a way to be wrong. Issues move that job to the
platform: open versus closed, who is assigned, and which labels are on it are
atomic, enforced, and visible from every machine the moment they change.

So `ideas` stores nothing of its own. It is a translation layer over `gh` and
`glab`, and everything it shows you is derived from what those return.

## Requirements

- A git repository whose `origin` is on `github.com` or `gitlab.com`. Anything
  else is an error, not a fallback — there is no local mode.
- `gh` (for GitHub) or `glab` (for GitLab), installed and authenticated.
  `ideas` checks both before it makes any other call and names whichever is
  missing.
- `fzf` is optional; without it, selection falls back to a numbered prompt.

Self-hosted GitHub Enterprise and GitLab instances are not a supported target.
They may work if your CLI is already configured for that host, but nothing here
is tested against them.

## Commands

```bash
ideas new "speed up the dispatcher" --size M --tags cli,perf
ideas list --status open --size S
ideas pick 42                # show it in full, then claim it
ideas pick --status open     # choose from the filtered list instead
ideas drop 42                # release a claim
ideas done 42
ideas abandon 42
ideas reopen 42
```

`ideas new` takes its body from `--body`, from stdin when something is piped in,
or — on a terminal with neither — from `gh`'s prompt or `glab`'s editor.

`ideas list --json` emits the same fields as the printed line as a JSON array,
which is how the Claude skill reads the backlog.

## Lifecycle

Five states, none of them stored. They are read back off the issue each time:

| State | Means |
|---|---|
| `open` | open, nobody assigned |
| `in-progress` | open, assigned to you |
| `claimed` | open, assigned to somebody else |
| `abandoned` | closed, carries the `abandoned` label |
| `done` | closed, without that label |

`abandoned` is tested before `done`, so a closed issue only ever answers to one
of them.

Assignment is the in-progress signal, which is why this stays a single-user
tool: `ideas pick` only ever assigns you, and `drop` and `reopen` only ever
remove you. It will warn when an issue is already someone else's and let you
proceed, but it will never remove or replace an assignment it did not make.

`size` is a `size:S` / `size:M` / `size:L` label, tags are plain labels, and
`abandoned` is a label too. Every one of them is created before it is applied,
with an already-exists response treated as success — listing labels first would
mean trusting a listing that pages oldest-first from a small default.

## Notes

Every call names the repository explicitly, taken from `origin`. Neither CLI
works that out from `origin` on its own — `gh` has its own resolution order in
which `upstream` can outrank it — so an unpinned call made inside a fork can
quietly file on the upstream's public tracker.

`ideas` does not create worktrees or branches, and does not start a build. After
you claim an idea it points you at a Claude Code session, where the `idea` skill
hands the body to `pair-programming`.

A subcommand that makes several calls does not roll back a failure partway
through. Label creation is idempotent, so re-running `ideas new` is always safe;
an `abandon` that labels but fails to close leaves the issue labelled and open,
and you close it yourself.

## Tests

```bash
bats config/ideas/tests/bats/ideas.bats
```

The tests put fake `gh` and `glab` executables first on `PATH` that record
their arguments instead of reaching an API, so they prove `ideas` issues the
right calls — not that the providers behave as expected. Confirming that needs
a real run against a scratch repository on each provider.
