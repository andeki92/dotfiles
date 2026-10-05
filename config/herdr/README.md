# herdr — agent multiplexer

[herdr](https://herdr.dev) hosts every Claude Code session here. This package
holds its config and local plugins; the Claude side lives in
`config/claude/.claude/hooks/`.

```
.config/herdr/
├── config.toml          prefix, sidebar rows ($pr, Claude's live title)
└── plugins/
    ├── pr-status/       $pr token: branch PR / MR + CI rollup on agent rows
    ├── worktree-setup/  copies .worktreeinclude files into new worktrees
    ├── gh-alerts/       GitHub review queue panes (gh-dash)
    └── gitlab-alerts/   GitLab review queue panes
```

## Setup (once per machine)

```bash
stow herdr claude
./scripts/herdr-setup.sh
```

The script installs herdr's Claude integration and links the plugins. Run it
again after a herdr upgrade: the integration hook may have changed, and
herdr's docs ask for a reinstall.

## How herdr and Claude Code fit together

| Concern | Who | How |
|---|---|---|
| Working / idle / blocked | herdr | screen detection (`HERDR_AGENT=claude`) |
| Resume after server restart | herdr | `hooks/herdr-agent-state.sh`, herdr-managed |
| Tab label, worktree workspace | us | `hooks/herdr-sync.sh` |
| What the session is doing | Claude | its terminal title, shown via `terminal_title_stripped` |
| PR / MR and CI | us | `pr-status` plugin, `$pr` token |

`herdr-agent-state.sh` and its `settings.json` entry are written by
`herdr integration install claude`; don't edit them. The entry keeps herdr's
absolute path, because a reinstall adds a duplicate for any other form.

## Plugins

**pr-status** runs on pane focus (throttled to 30 s per pane), on an agent
finishing a turn, and on a pane moving workspace. There is no background
poll; refresh by hand with
`herdr plugin action invoke dotfiles.pr-status.refresh`. GitHub remotes use
`gh`, GitLab remotes `glab`.

**worktree-setup** copies the gitignored files a repo lists in
`.worktreeinclude` (gitignore syntax) into each worktree herdr opens. Claude
Code reads the same file for worktrees it creates, so one file covers both.
mise needs nothing: it shares trust with the main checkout.

```
# .worktreeinclude
.env
.env.local
```

## Tests

```bash
bats config/herdr/.config/herdr/plugins/*/test
```
