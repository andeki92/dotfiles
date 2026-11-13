-- Favourite projects for Rex's command palette. Copy this file to
-- ~/.config/rex/projects.lua and edit it there:
--
--   cp ~/.config/rex/projects.example.lua ~/.config/rex/projects.lua
--
-- projects.lua is never committed, so it can name private folders. Each
-- project becomes a palette entry, "Project: <label>": shift+cmd+p, type part
-- of the name, Enter. It switches to the session labelled <label>, or creates
-- it with a shell in <dir>. Press cmd+r after editing to load the list.
--
-- label  the palette entry and the session's name
-- dir    the project's folder; a leading ~ is your home folder
return {
  { label = "Dotfiles", dir = "~/.dotfiles" },
  -- { label = "Notes", dir = "~/notes" },
}
