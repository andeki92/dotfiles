# rex — terminal multiplexer

[Rex](https://www.superlogical.com/rex/docs) reads one Lua file,
`~/.config/rex/init.lua`, for its key bindings and custom actions. The server
keeps its own state (`logs/`, `.claude/`) beside it in `~/.config/rex/`, so
this package links the file, never the folder.

```
.config/rex/
└── init.lua    bindings and the new-work session
```

| Key | Action | What it does |
| --- | --- | --- |
| `cmd+b` | `new_work` | Starts a piece of work as its own Rex session (below). |
| `cmd+r` | `client.config.reload` | Reloads this file. |

## One session per piece of work

Rex's agent hook names the whole session after the agent's task, so each piece
of work gets a session of its own. Its tabs and splits hold that work's
helpers: servers, test runs, other agents.

`cmd+b` creates a session titled `<Repo> - new work`, for the repository of
the pane that has focus, and switches to it. Its one pane asks for a
worktree's name, such as `123-flaky-tests`. Enter renames the session to
`<Repo> - <name>`, such as `0th - 123-flaky-tests`, and runs `c -w <name>`
there. From inside `.claude/worktrees/…`, the repository is the main checkout.
Empty input or `ctrl+c` cancels and removes the session.

When Claude exits, the session removes itself, because Rex keeps a session
whose last window has closed. Claude Code removes the worktree and its branch
too when they hold no changes; otherwise it asks.

Don't name an issue's worktree `#123`: Claude Code reads `-w "#123"` as merge
request 123. Use the bare number, as in `123-slug`.

## Setup (once per machine)

```bash
mkdir -p ~/.config/rex      # so stow links the file, not the whole folder
stow rex
rex config check
```

Without the `mkdir`, stow links `~/.config/rex` itself into this repository,
and Rex's logs would be written here. A machine that already has a plain
`~/.config/rex/init.lua` needs it removed before `stow rex`.

After editing, `rex config check` reports errors with their line, and
`rex config reload` (or `cmd+r`) applies the file. To try an action from a
copy without reloading, run `rex do path/to/init.lua --action new_work`.
