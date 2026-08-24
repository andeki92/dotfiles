# claude — Claude Code configuration

Stowed to `~/.claude/`. Source-of-truth for how Claude Code behaves on this
machine: global settings, hooks, slash commands, and project guidance.

> Edit the files here, never the symlinks under `~/.claude/`.
> Re-apply with `stow -R claude` from the repo root (or `stow -R $(ls config)`
> to restow everything — never bare `stow -R .`, which symlinks every tool
> directly into `~/` instead of `~/.config/<tool>`).

```
config/claude/.claude/
├── settings.json          # global Claude Code settings (hooks, deny-list, UI)
├── CLAUDE.md              # global instructions injected into every session
├── commands/              # custom slash commands
├── skills/                # personal skills (see "Skills" below)
│   └── pair-programming/  # design → spec → critique → implement
└── hooks/                 # event-driven automation (see "Hooks" below)
    ├── lint-dispatch.sh   # PostToolUse entrypoint
    └── linters/           # one script per file type
        ├── yaml.sh
        ├── json.sh
        └── sh.sh
```

---

## Skills

Skills are *instructions* Claude loads on demand — the opposite end of the lever
from hooks. A hook fires deterministically and the model has no say; a skill is
read by the model when it judges the skill relevant, or when you invoke it by
name as `/<skill-name>`.

Each skill is a directory with a `SKILL.md` whose YAML frontmatter carries two
fields: `name`, and a `description` that tells Claude *when* to reach for it.
Supporting files sit alongside and are read only when the workflow needs them,
so they cost no context until they do.

```
skills/pair-programming/
├── SKILL.md               # the workflow itself
├── spec-template.md       # output format: design doc + EARS requirements
├── spec-lint.py           # mechanical spec checks — runs before any model pass
├── test_spec_lint.py      # its test suite (python3 test_spec_lint.py)
├── critic-prompt.md       # adversarial spec review, fresh context
├── implementer-prompt.md  # TDD implementation, fresh context
└── reviewer-prompt.md     # code review against the spec, fresh context
```

### pair-programming

The entry point for design work, wired up in `CLAUDE.md` so it applies before
any feature, component, or behaviour change. Two lanes: **small** (one
behaviour, one commit — spec'd, built, shown, no subagents) and **standard**,
whose stages each run in a fresh context:

1. **Pin the constraints** — an actual back-and-forth in the session. Probe,
   challenge, commit, close. No menus of options to pick from.
2. **Lint** — `spec-lint.py` catches everything mechanically decidable before
   a model is paid to look.
3. **Critic** (subagent) — a fresh model that never saw the conversation
   attacks the spec for false premises, uncovered cases, and security holes.
4. **Gate** — you approve the spec; the `Base` sha is recorded, so bailing
   later is one `git reset` and an `abandoned` status.
5. **Implementer** (subagent) — builds unit by unit with TDD, commits nothing.
6. **Show the work** — you see the diff and test output before anything lands
   in git; tweaks fold straight in, commits are cut on your go.
7. **Review** (subagent) — judges the committed diff against the spec, two
   rounds maximum.

Artifacts live in `<repo>/.specs/` and are excluded via `.git/info/exclude`, so
nothing lands in a tracked file and nothing gets committed.

### Adding a skill

1. Create `skills/<name>/SKILL.md` with `name` + `description` frontmatter.
   Write the description as triggering conditions ("Use when…"), not as a
   summary of what the skill does — a description that summarises the workflow
   gets followed *instead of* the skill body.
2. Put anything heavy (templates, reference material, subagent prompts) in
   sibling files and link to them relatively.
3. `stow -R claude`, then confirm with `/<name>` in a fresh session.

---

## Hooks

Hooks are how we make Claude *do something automatically* around its own tool
calls — without asking the model to remember to do it. The harness runs them,
not the model, so they fire every time, deterministically.

This directory is built so that **adding a new automated behaviour is dropping
in one small script**, not rewriting wiring. Linting-on-edit is the first use;
the same shape works for formatting, notifications, guardrails, or anything
keyed off a tool event.

### The lint-on-edit framework (current use)

**Problem it solves:** Claude used to validate YAML by running throwaway probes
(`python3 -c 'import yamllint…'`). That's slow, inconsistent, and pollutes the
transcript. Instead, a single hook lints *every* file the moment Claude writes
it, and hands any errors straight back to the model to fix.

**Flow:**

```
Claude edits a file (Write / Edit / MultiEdit)
        │
        ▼
settings.json  PostToolUse hook  ──►  hooks/lint-dispatch.sh
        │                                   │ reads tool payload (JSON on stdin)
        │                                   │ extracts tool_input.file_path
        │                                   │ maps extension ──► linters/<type>.sh
        ▼                                   ▼
   .yaml ─────────────────────────►  linters/yaml.sh   (yamllint)
   .json ─────────────────────────►  linters/json.sh   (jq)
   .sh / .bash ───────────────────►  linters/sh.sh     (shellcheck)
        │
        ▼
   exit 0  → clean (or linter's tool not installed) → nothing happens
   exit 2  → errors on stderr → Claude Code feeds them back to the model → it fixes the file
```

**Design contract** — every linter in `linters/` is invoked as
`linters/<type>.sh <absolute-file-path>` and must obey:

| Exit | Meaning | Behaviour |
|------|---------|-----------|
| `0`  | Clean **or** the linter's tool isn't on `PATH` | Silent; editing continues. Never block a machine that lacks the tool. |
| `2`  | Lint errors found | Errors printed to **stderr**; Claude Code returns them to the model as feedback. |

The dispatcher (`lint-dispatch.sh`) owns the shared work — reading the JSON
payload once, resolving the path, mapping extension → linter, and no-op'ing on
anything unhandled. Linters stay tiny and single-purpose.

### Adding a new linter / formatter

1. Create `hooks/linters/<type>.sh`. Take `$1` (the file path), guard on
   `command -v <tool>`, run it, `exit 2` with errors on stderr or `exit 0`.
   Copy an existing linter — they're ~15 lines.
2. Add the extension(s) to the `case` in `hooks/lint-dispatch.sh`.
3. Add the tool to `config/mise/.config/mise/config.toml` so it's installed
   reproducibly (then run `mise install`).
4. `chmod +x` the new script and `stow -R claude`.

No `settings.json` change is needed — the single PostToolUse hook already
routes everything through the dispatcher.

### Using hooks for non-lint behaviour later

The `linters/` dispatcher is one *pattern*, not the whole story. Claude Code
fires hooks on many events — useful ones to build on:

| Event | When it fires | Example future use |
|-------|---------------|--------------------|
| `PostToolUse`  | after a tool succeeds | lint/format edits (current), auto-`stow` after config changes |
| `PreToolUse`   | before a tool runs    | block edits to generated/vendored paths |
| `UserPromptSubmit` | on each user message | inject repo context, redact secrets |
| `Stop` / `SubagentStop` | when a turn ends | desktop notification, run a test suite |
| `SessionStart` | session boot          | warn if `mise install` is stale |

To add one, give it its own entrypoint script under `hooks/` and register it in
`settings.json` under the matching event. Keep the same discipline: the script
is the logic, `settings.json` only wires it.

---

## settings.json — what lives here vs. locally

This file is **global** (`~/.claude/settings.json`) and version-controlled, so
only put things here that should be true on *every* repo and *every* machine:

- ✅ **Hooks** — global automation like lint-on-edit.
- ✅ **Global `permissions.deny`** — blanket guardrails that should never be
  overridden per-project (e.g. deny reading secret stores).
- ❌ **`permissions.allow` / project allow-lists** — these are per-repo trust
  decisions. Keep them in each project's own `.claude/settings.local.json`,
  *not* here. A global allow-list would grant trust we haven't actually vetted
  for a given repo.

> Note: Claude Code writes some state back into this file (e.g.
> `enabledPlugins`). Expect occasional diff churn here — commit it like any
> other config change.

---

## Dependencies

The lint hooks degrade gracefully if a tool is missing, but for full coverage
the following must be installed (all declared in
`config/mise/.config/mise/config.toml`, installed via `mise install`):

| Tool | Backend | Used by |
|------|---------|---------|
| `yamllint` | `pipx:` (via `uv`, see `[settings.pipx] uvx`) | `linters/yaml.sh` |
| `jq` | mise core | `linters/json.sh` + dispatcher payload parsing |
| `shellcheck` | mise core | `linters/sh.sh` |

`yamllint`'s ruleset is itself a stowed dotfile:
`config/yamllint/.config/yamllint/config` → `~/.config/yamllint/config`. One
global ruleset for every project unless a repo ships its own `.yamllint`.

---

## Testing & debugging a hook

Hooks read a JSON payload on stdin. Simulate one without involving Claude:

```bash
# Should print nothing and exit 0 on a clean file, or errors + exit 2 on a bad one.
echo '{"tool_input":{"file_path":"/path/to/some.yaml"}}' \
  | ~/.claude/hooks/lint-dispatch.sh ; echo "exit=$?"
```

To see hooks fire live inside Claude Code, run with `claude --debug`, or inspect
the configured hooks with the `/hooks` command.

The `block-bash-file-edits.sh` guard has a bats suite under `hooks/test/`:

```bash
bats config/claude/.claude/hooks/test
```
