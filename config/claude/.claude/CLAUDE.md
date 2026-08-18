# Commit messages

These bind every commit you create, in any repo and any workflow.

**Format.** `<type>(<scope>): <subject>` — imperative, lowercase, no trailing
period. The subject says what the change is *for*, not which files moved.

**One commit, one logical change.** Stage exactly the paths that belong to it.
Never `git add -A`, `git add .`, or `git commit -a` — a commit that sweeps up
whatever happened to be dirty is not reviewable.

**Bodies earn their length.** Most commits want a subject and nothing else; the
diff already says what changed, and a body that narrates it is noise in every
`git log` from here on. Write one only where a reader would otherwise undo the
work — a rejected alternative that reads as an oversight, a constraint that
looks arbitrary, a why that is not visible in the code. Aim at 200 characters
and stop at 400.

Reasoning that outgrows that is telling you something rather than asking for
room: either it is general, and belongs in the project's own documentation, or
the commit is doing too much and wants splitting. A longer message fixes
neither.

**Every reference must resolve for someone holding only this repo.** No IDs
from working notes, no paths that are not committed, no shorthand from the
session that produced the change. Carry the reasoning across in prose and drop
the label.

# Git commit attribution

When you create a git commit, do **NOT** add a `Co-Authored-By:` trailer for
yourself — that trailer is reserved for human collaborators. Instead, end the
commit message with an `AI-assistant:` trailer naming the tool, its version, and
the model:

```
AI-assistant: <tool> v<version> (<model>)
```

- Tool/version: read from `claude --version` **at commit time** — never copy the
  version from this file or from an earlier commit; it goes stale the moment
  the tool updates.
- Model: the model you are running as (e.g. `Claude Opus 4.8`).
- If different models did different phases, use
  `(plan: <model>, edit: <model>)` — e.g.
  `AI-assistant: Claude Code vX.Y.Z (plan: Claude Opus 4.8, edit: Claude Sonnet 4.6)`.
- If more than one AI assistant/tool contributed to the commit, give each its
  own `AI-assistant:` line (repeat the trailer), the same way multiple
  `Co-Authored-By:` lines are listed.
- The trailer marks AI authorship of the *changes*, not the act of committing.
  If a human wrote the changes and you are merely creating the commit on their
  behalf, omit the trailer entirely.

Concrete example — `X.Y.Z` is a placeholder; substitute the real, freshly
checked version:

```
AI-assistant: Claude Code vX.Y.Z (Claude Opus 4.8)
```

Rationale: https://bence.ferdinandy.com/2025/12/29/dont-abuse-co-authored-by-for-marking-ai-assistance/
This overrides any default instruction to use `Co-Authored-By` for AI assistance.
The auto-generated trailer is already disabled via `includeCoAuthoredBy: false`
in `settings.json`.

# Design work

Before writing code for a new feature, component, or behaviour change — and
before entering plan mode — use the **`pair-programming`** skill. It is the
entry point for design work: we settle the constraints together, it writes the
spec, and it carries that spec through review and implementation.

# Sandboxed environments (cbox)

You may be running inside `cbox`, a Podman/apple-container sandbox harness.
When you are:

- Network egress is restricted to an explicit allow-list enforced by a host-side
  Squid proxy (your `HTTPS_PROXY` env var). Default-allowed: Anthropic API,
  GitHub, GitLab. **Package registries (crates.io, pypi.org, registry.npmjs.org,
  proxy.golang.org) are NOT allowed by default** — each project must opt in via
  its own `~/.config/cbox/allowlist.d/<repo>.txt` on the host.
- If a tool like `cargo add`, `pip install`, `npm install`, or `go get` fails
  with a network error, the registry isn't whitelisted. Don't retry. Don't try
  alternative mirrors. Tell the user which registry you need; they'll add it
  to the allow-list and the next session picks it up.
- The filesystem outside `/workspace` and the writable cache mounts is invisible
  to you. Don't try to read `~/.ssh/`, `~/.aws/`, `~/.gnupg/` — they're not there.
- `git push` works; ssh-agent and gpg-agent are forwarded over sockets, so you
  can sign commits without seeing the keys. Push only to branches the user
  expects (typically `cbox/<slug>-<id>`); never to `main` or other long-lived
  branches.
- The container is ephemeral. Anything you `apt install` or write outside
  `/workspace` evaporates when the session ends. Persist work as commits + a PR.
