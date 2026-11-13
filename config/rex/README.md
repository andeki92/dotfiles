# rex — terminal multiplexer

[Rex](https://www.superlogical.com/rex/docs) reads one Lua file,
`~/.config/rex/init.lua`, for its key bindings and custom actions. The server
keeps its own state (`logs/`, `.claude/`) beside it in `~/.config/rex/`, so
this package links files, never the folder.

```
.config/rex/
├── init.lua             bindings, the new-work prompt and pinned sessions
└── pinned.example.lua   a starting point for this machine's pinned.lua
```

| Key | Action | What it does |
| --- | --- | --- |
| `cmd+b` | `new_work` | A small floating pane asks for a worktree's name, such as `123-flaky-tests`. Enter opens a tab of that name running `c -w <name>` in the focused pane's repository. From inside `.claude/worktrees/…` that is the main checkout. Empty input or `ctrl+c` cancels. |
| `cmd+t` | `pinned_tab` | In a pinned session, a new tab in its directory; elsewhere Rex's own new tab. |
| `shift+cmd+k` | `pinned_sessions` | Recreates any pinned session that is gone. |
| `cmd+r` | `client.config.reload` | Reloads this file. |

Don't name an issue's worktree `#123`: Claude Code reads `-w "#123"` as merge
request 123. Use the bare number, as in `123-slug`. When Claude exits from a
worktree with no changes, it removes the worktree and its branch.

## Pinned sessions

Pins are each machine's own config: a session label and the folder it belongs
to. They often name private project folders, so they never enter this public
repository. `init.lua` reads them from `~/.config/rex/pinned.lua`, a plain
file beside the links, and without it has no pins and leaves `cmd+t` to Rex.
`.gitignore` keeps a stray `pinned.lua` in the package out of commits too.

To add or change a pin, edit `~/.config/rex/pinned.lua` and press `cmd+r`.

## Setup (once per machine)

```bash
mkdir -p ~/.config/rex      # so stow links the files, not the whole folder
stow rex
cp ~/.config/rex/pinned.example.lua ~/.config/rex/pinned.lua   # then edit it
rex config check
```

Without the `mkdir`, stow links `~/.config/rex` itself into this repository,
and Rex's logs and your pins would be written here. A machine that already
had a plain `~/.config/rex/init.lua` needs it removed before `stow rex`.

After editing, `rex config check` reports errors with their line, and
`rex config reload` (or `cmd+r`) applies the file. To try an action from a
copy without reloading, run `rex do path/to/init.lua --action new_work`.
