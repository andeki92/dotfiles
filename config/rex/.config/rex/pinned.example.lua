-- Pinned Rex sessions for this machine. Copy this file to
-- ~/.config/rex/pinned.lua and edit it there:
--
--   cp ~/.config/rex/pinned.example.lua ~/.config/rex/pinned.lua
--
-- pinned.lua is never committed, so it can name private project folders.
-- init.lua reads it at load; run `rex config reload` (cmd+r) after editing.
--
-- Each pin is a session label and the folder it belongs to. A leading ~ is
-- your home folder.
--   cmd+t     in a pinned session, opens a new tab in its folder
--   ctrl+a p  recreates every pinned session that is gone
return {
  { label = "dotfiles", dir = "~/.dotfiles" },
  -- { label = "work", dir = "~/code/work" },
}
