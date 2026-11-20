# rex — terminal multiplexer

[Rex](https://www.superlogical.com/rex/docs) reads one Lua file,
`~/.config/rex/init.lua`. Here it only loads `~/.config/rex/rex-acp.lua`,
which [rex-acp](https://gitlab.com/bache-klever/rex-acp) writes and keeps up to
date: new work on `cmd+b`, the agent's questions in the command palette, and
the key bindings. Everything about them lives in rex-acp's README, under "Set
up Rex"; change them there, not here.

The server keeps its own state (`logs/`, `.claude/`) beside init.lua in
`~/.config/rex/`, so this package links the file, never the folder.

## Setup (once per machine)

```bash
mkdir -p ~/.config/rex      # so stow links the file, not the whole folder
stow rex
rex-acp rex-setup           # writes ~/.config/rex/rex-acp.lua and reloads Rex
```

Then list the machine's projects for `cmd+b` in `~/.config/rex/projects.lua`,
a plain file that is never committed, since it often names private folders:

```lua
return {
  { label = "dotfiles", dir = "~/.dotfiles" },
}
```

Without the `mkdir`, stow links `~/.config/rex` itself into this repository,
and Rex's logs and your projects would be written here. A machine that already
has a plain `~/.config/rex/init.lua` needs it removed before `stow rex`.
