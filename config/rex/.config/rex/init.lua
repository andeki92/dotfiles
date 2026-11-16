rex.bind("cmd+r", "client.config.reload")

local home = os.getenv("HOME")

-- Projects: this machine's own list of { label, dir }, read from
-- ~/.config/rex/projects.lua (never committed; start it from
-- projects.example.lua beside it). Read on every launch, so an edit needs no
-- reload.
local function load_projects()
  local path = home .. "/.config/rex/projects.lua"
  local chunk, load_err = loadfile(path)
  if chunk == nil then
    local f = io.open(path, "r")
    if f ~= nil then
      f:close()
      error("projects.lua: " .. tostring(load_err), 0)
    end
    return {}
  end
  local ok, list = pcall(chunk)
  if not ok or type(list) ~= "table" then
    error("projects.lua: expected a list of { label, dir }", 0)
  end
  local projects = {}
  for _, p in ipairs(list) do
    if type(p) == "table" and type(p.label) == "string" and p.label ~= ""
        and type(p.dir) == "string" then
      table.insert(projects, { label = p.label, dir = (p.dir:gsub("^~", home)) })
    else
      rex.log("warn", "projects.lua: skipped an entry without a label and a dir")
    end
  end
  return projects
end

-- New work: a new Rex session for one piece of work in one project. Its one
-- pane shows the projects in fzf; Enter asks for a worktree's name, such as
-- 123-flaky-tests, or nothing for the main checkout. The session is then named
-- "<project> · <worktree>", or just "<project>", and rex-acp starts in the
-- project's folder with its `c` agent, Claude Code as `c` starts it, in
-- that worktree (`-w <name>`). Esc, empty input at fzf or ctrl+c cancels.
-- The session removes itself when rex-acp exits, since Rex keeps a session
-- with no windows.
--
-- The prompt runs in a bare zsh (-f), so it shows at once and ctrl+c is caught
-- from the start; only rex-acp gets the interactive shell, so Claude sees what
-- every other terminal sees. A session made by an action gets the server's
-- PATH, which lacks mise's tools, so path_prepend adds mise's shims for fzf.
-- Rex exports REX_BIN_DIR into every pane, which finds `rex` without a PATH.
-- $1 is the projects, one "label<TAB>dir" a line.
local new_work_prompt = [=[
rex() { command "${REX_BIN_DIR:+$REX_BIN_DIR/}rex" "$@"; }
done_() { rex kill "$REX_SESSION" >/dev/null 2>&1; exit 0; }
trap done_ INT
print -n "\e[H\e[2J"
pick=$(print -r -- "$1" | fzf --delimiter=$'\t' --with-nth=1 --reverse \
  --prompt='project > ' --header='New work in rex-acp  (Enter picks; Esc cancels)') || done_
label=${pick%%$'\t'*} dir=${pick#*$'\t'}
print -n "\e[H\e[2J"
print -P "%BNew work%b in ${label//\%/%%}  %F{8}(a worktree's name, or empty for the main checkout; ctrl+c cancels)%f"
read -r "name?worktree: " || done_
title=$label
[[ -n $name ]] && title="$label · $name"
rex session rename "$REX_SESSION" "$title" >/dev/null 2>&1
cd -- "$dir" || { read -rk1 "?cannot enter $dir; press a key to close "; done_; }
trap ':' INT
args=()
[[ -n $name ]] && args=(-- -w "$name")
zsh -ic 'rex-acp c "$@"' new-work "${args[@]}"
st=$?
(( st == 0 )) || read -rk1 "?rex-acp exited with status $st; press a key to close "
done_
]=]

rex.action{
  name  = "new_work",
  title = "New Work in a Project",
  keywords = "project worktree claude rex-acp session new",
  run   = function(ctx, args)
    local projects = load_projects()
    if #projects == 0 then
      error("no projects: list them in ~/.config/rex/projects.lua", 0)
    end
    local lines = {}
    for _, p in ipairs(projects) do
      table.insert(lines, p.label .. "\t" .. p.dir)
    end
    local s, err = rex.call("session.create", {
      label = "new work",
      initial_windows = { {
        layout = rex.layout.block{
          flavor  = "com.superlogical.terminal.shell",
          options = {
            cwd     = home,
            shell   = "none",
            path_prepend = { home .. "/.local/share/mise/shims" },
            command = { "zsh", "-f", "-c", new_work_prompt, "new-work",
                        table.concat(lines, "\n") },
          },
        },
      } },
    })
    if err ~= nil then error(err, 0) end
    -- Show it. Only an action run from a key or the palette has a client to
    -- ask; from the CLI there may be none, and the session is still made.
    pcall(rex.client.queue, "session.select", { session_id = s.session_id })
    return { session_id = s.session_id }
  end,
}
rex.bind("cmd+b", "new_work")
