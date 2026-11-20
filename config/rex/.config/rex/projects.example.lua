-- Projects for new work in Rex (cmd+b). Copy this file to
-- ~/.config/rex/projects.lua and edit it there:
--
--   cp ~/.config/rex/projects.example.lua ~/.config/rex/projects.lua
--
-- projects.lua is never committed, so it can name private folders. cmd+b
-- lists the projects in the command palette; the one picked names the new
-- session, "<label> · <worktree>", and rex-acp starts in its folder. The file
-- is read on every cmd+b, so an edit needs no reload.
--
-- label  the name in the picker, and the session's
-- dir    the project's folder; a leading ~ is your home folder
return {
  { label = "dotfiles", dir = "~/.dotfiles" },
  -- { label = "notes", dir = "~/notes" },
}
