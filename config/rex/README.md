# rex — terminal multiplexer

[Rex](https://www.superlogical.com/rex/docs) reads one Lua file,
`~/.config/rex/init.lua`, for its key bindings and custom actions. The server
keeps its own state (`logs/`, `.claude/`) beside it in `~/.config/rex/`, so
this package links only the file.

```
.config/rex/
└── init.lua    bindings, the new-work prompt and pinned sessions
```

| Key | Action | What it does |
| --- | --- | --- |
| `cmd+b` | `new_work` | A small floating pane asks for a worktree's name, such as `123-flaky-tests`. Enter opens a tab of that name running `c -w <name>` in the focused pane's repository. From inside `.claude/worktrees/…` that is the main checkout. Empty input or `ctrl+c` cancels. |
| `cmd+t` | `pinned_tab` | In a pinned session, a new tab in its directory; elsewhere Rex's own new tab. |
| `ctrl+a p` | `pinned_sessions` | Recreates any pinned session that is gone. |
| `cmd+r`, `ctrl+a shift+r` | `client.config.reload` | Reloads this file. |

Don't name an issue's worktree `#123`: Claude Code reads `-w "#123"` as merge
request 123. Use the bare number, as in `123-slug`. When Claude exits from a
worktree with no changes, it removes the worktree and its branch.

## Pinned sessions

The pins name this machine's own project folders, so they stay out of this
public repository. `init.lua` reads them from `~/.config/rex/pinned.lua`, a
plain file next to the link, and has no pins without it:

```lua
return {
  { label = "notes", dir = "~/notes" },
}
```

## Setup (once per machine)

```bash
rm ~/.config/rex/init.lua   # only if it is a plain file, after checking it matches
stow rex
rex config check
```

After editing, `rex config check` reports errors with their line, and
`rex config reload` (or `cmd+r`) applies the file. To try an action from a
copy without reloading, run `rex do path/to/init.lua --action new_work`.
