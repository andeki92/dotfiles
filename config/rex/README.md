# rex — terminal multiplexer

[Rex](https://www.superlogical.com/rex/docs) reads one Lua file,
`~/.config/rex/init.lua`, for its key bindings and custom actions. The server
keeps its own state (`logs/`, `.claude/`) beside it in `~/.config/rex/`, so
this package links the file, never the folder.

```
.config/rex/
├── init.lua               bindings, the new-work session and the projects
└── projects.example.lua   a starting point for this machine's projects.lua
```

| Key | Action | What it does |
| --- | --- | --- |
| `cmd+b` | `new_work` | Starts a piece of work as its own Rex session (below). |
| `cmd+r` | `client.config.reload` | Reloads this file. |
| `shift+cmd+p`, then a project | `project_<label>` | Goes to a favourite project's session (below). |

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

## Projects

Each favourite project is an entry in Rex's command palette, `Project:
<label>`, under a Projects heading. Press `shift+cmd+p`, type part of the
name, and press Enter. It switches to the session labelled `<label>`, in any
case, or creates it with a shell in the project's folder. From then on
`cmd+k` lists it with the other sessions, and `cmd+b` from it starts work in
that repository.

The list is each machine's own and is never committed, since it often names
private folders. `init.lua` reads it from `~/.config/rex/projects.lua`, a
plain file beside the links. `projects.example.lua` shows the format. To add a
project, add a line there and press `cmd+r`:

```lua
return {
  { label = "Dotfiles", dir = "~/.dotfiles" },
  { label = "Notes",    dir = "~/notes" },
}
```

Without the file there are no project entries. An entry with no `label` or
`dir`, or a file that fails to load, is logged as a warning.

## Setup (once per machine)

```bash
mkdir -p ~/.config/rex      # so stow links the files, not the whole folder
stow rex
cp ~/.config/rex/projects.example.lua ~/.config/rex/projects.lua   # then edit it
rex config check
```

Without the `mkdir`, stow links `~/.config/rex` itself into this repository,
and Rex's logs and your projects would be written here. A machine that already has a plain
`~/.config/rex/init.lua` needs it removed before `stow rex`.

After editing, `rex config check` reports errors with their line, and
`rex config reload` (or `cmd+r`) applies the file. To try an action from a
copy without reloading, run `rex do path/to/init.lua --action new_work`.
