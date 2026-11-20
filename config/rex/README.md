# rex — terminal multiplexer

[Rex](https://www.superlogical.com/rex/docs) reads one Lua file,
`~/.config/rex/init.lua`, for its key bindings and custom actions. The server
keeps its own state (`logs/`, `.claude/`) beside it in `~/.config/rex/`, so
this package links the file, never the folder.

```
.config/rex/
├── init.lua               bindings and the new-work session
└── projects.example.lua   a starting point for this machine's projects.lua
```

| Key | Action | What it does |
| --- | --- | --- |
| `cmd+b` | `new_work` | Starts a piece of work in a project, as its own Rex session (below). |
| `cmd+r` | `client.config.reload` | Reloads this file. |

## New work: one session per piece of work

`cmd+b` asks two questions in Rex's command palette (`rex.ui`). First the
project: type part of its name and press Return. Then the worktree: one Claude
Code already made under `.claude/worktrees` (its branch shows beside it), the
main checkout, or a new name typed into the field, such as `123-flaky-tests`.
The session is
named `<project> · <worktree>`, or just `<project>`, so the sidebar shows
where every piece of work runs, and rex-acp starts in the project's folder with
its `c` agent: Claude Code as `c` starts it, Code Mode and all, in that
worktree. Esc at either question cancels, before any session is made.

If rex-acp fails to start, its pane says so and waits for a key before the
session goes.

When rex-acp exits (`ctrl+d` in its input pane), the session removes itself,
because Rex keeps a session whose last window has closed. The worktree stays:
Claude Code only offers to remove it when it runs in a terminal of its own.

Agents leave the session's name alone; `~/.claude/CLAUDE.md` tells them to
name the tab instead.

Don't name an issue's worktree `#123`: Claude Code reads `-w "#123"` as merge
request 123. Use the bare number, as in `123-slug`.

## Projects

The list is each machine's own and is never committed, since it often names
private folders. `init.lua` reads it from `~/.config/rex/projects.lua`, a
plain file beside the links, every time `cmd+b` opens the picker, so an edit
needs no reload. `projects.example.lua` shows the format:

```lua
return {
  { label = "dotfiles", dir = "~/.dotfiles" },
  { label = "notes",    dir = "~/notes" },
}
```

The picker lists them in the file's order. Without the file, `cmd+b` says
there are no projects; a file that fails to load is reported the same way.

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
`rex config reload` (or `cmd+r`) applies the file. `rex do new_work
project=dotfiles worktree=` skips the questions, for the main checkout. The
questions only show for an action the server has loaded, so a copy run with
`rex do path/to/init.lua --action new_work` needs both arguments.
