# herdr — agent multiplexer

[herdr](https://herdr.dev) hosts every Claude Code session here. This package
holds its config and the one local plugin; the Claude side is two hooks in
`config/claude/.claude/hooks/` and the `claude()` wrapper in
`config/zsh/.config/zsh/lazy/81-herdr-claude.zsh`.

```
.config/herdr/
├── config.toml        prefix, sidebar rows ($pr, Claude's live title)
└── plugins/
    └── pr-status/     $pr token: branch PR / MR + CI rollup on agent rows
```

## Setup (once per machine)

```bash
stow herdr claude
./scripts/herdr-setup.sh
```

The script installs herdr's Claude integration and links the plugin. Run it
again after a herdr upgrade: herdr's docs ask for an integration reinstall.

## Who does what

| Concern | Who | How |
|---|---|---|
| Working / idle / blocked | herdr | screen detection (`HERDR_AGENT=claude`) |
| Resume after server restart | herdr | `hooks/herdr-agent-state.sh`, herdr-managed |
| What the session is doing | Claude | its terminal title, shown via `terminal_title_stripped` |
| New tab per `claude` | us | `claude()` zsh wrapper |
| Worktree ↔ workspace | us | `hooks/herdr-worktree.sh` |
| PR / MR and CI | us | `pr-status` plugin, `$pr` token |

herdr cannot see a worktree Claude Code creates on its own, so
`herdr-worktree.sh` opens it as a workspace under the repo and moves the
Claude pane there on `EnterWorktree`, and back on `ExitWorktree`.

`herdr-agent-state.sh` and its `settings.json` entry are written by
`herdr integration install claude`; don't edit them. The entry keeps herdr's
absolute path, because a reinstall adds a duplicate for any other form.

Gitignored files a worktree needs (`.env`, ...) are each repo's own
`.worktreeinclude`, which Claude Code copies from when it creates a worktree.

## pr-status

Runs on pane focus (throttled to 30 s per pane), on an agent finishing a
turn, and on a pane moving workspace. There is no background poll; refresh
by hand with `herdr plugin action invoke dotfiles.pr-status.refresh`. GitHub
remotes use `gh`, GitLab remotes `glab`.

## Tests

```bash
bats config/herdr/.config/herdr/plugins/*/test config/claude/.claude/hooks/test
```
