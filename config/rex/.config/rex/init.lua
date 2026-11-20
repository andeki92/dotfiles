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

-- New work: a new Rex session for one piece of work in one project. Two
-- questions in the command palette (rex.ui) pick it: the project, then a
-- worktree, one Claude Code already made under .claude/worktrees, the main
-- checkout, or a new name typed into the filter, such as 123-flaky-tests
-- (spaces become dashes, a leading # goes). Esc at either cancels, before any
-- session exists. The session is then named "<project> · <worktree>", or just
-- "<project>", and rex-acp starts in the project's folder with its `c` agent,
-- Claude Code as `c` starts it, in that worktree (`-w <name>`). The session
-- removes itself when rex-acp exits, since Rex keeps a session with no
-- windows.
--
-- `project=` and `worktree=` skip the questions (worktree= alone for the main
-- checkout), so `rex do new_work project=rex-acp worktree=` needs no app.
-- rex.ui only asks from an action the server loaded: `rex do init.lua
-- --action new_work` gets "unsupported" unless both are given.

local function tilde(p) return (p:gsub("^" .. home:gsub("%p", "%%%0"), "~")) end

-- The folder a project sits in, as a quiet second line: "bache-klever", "~".
local function parent(p)
  local d = tilde(p):match("^(.*)/[^/]+$") or "~"
  return d:match("[^/]+$") or d
end

-- The worktrees Claude Code made with -w, as { name, branch }, from
-- <dir>/.claude/worktrees/<name>. None when dir isn't a git repository.
local function worktrees(dir)
  local r = rex.exec({ "git", "-C", dir, "worktree", "list", "--porcelain" }, { timeout = 5 })
  local found = {}
  if r == nil or not r.ok then return found end
  local cur
  for line in (r.stdout .. "\n"):gmatch("([^\n]*)\n") do
    local path = line:match("^worktree (.+)$")
    if path then
      cur = { name = path:match("/%.claude/worktrees/([^/]+)$") }
    elseif cur and cur.name then
      cur.branch = line:match("^branch refs/heads/(.+)$") or cur.branch
      if line == "detached" then cur.branch = "detached" end
      if line == "" then table.insert(found, cur); cur = nil end
    end
  end
  return found
end

-- The session's one pane: rex-acp in the project, then the session goes. It
-- runs in a bare zsh (-f); only rex-acp gets the interactive shell, so Claude
-- sees what every other terminal sees. Rex exports REX_BIN_DIR into every
-- pane, which finds `rex` without a PATH. $1 is the folder, $2 the worktree.
local new_work_run = [=[
rex() { command "${REX_BIN_DIR:+$REX_BIN_DIR/}rex" "$@"; }
done_() { rex kill "$REX_SESSION" >/dev/null 2>&1; exit 0; }
trap done_ INT
cd -- "$1" || { read -rk1 "?cannot enter $1; press a key to close "; done_; }
trap ':' INT
args=()
[[ -n $2 ]] && args=(-- -w "$2")
# +m: no job control, so the interactive shell leaves the terminal with this
# one and the failure prompt below can still read a key.
zsh +m -ic 'rex-acp c "$@"' new-work "${args[@]}"
st=$?
if (( st != 0 )); then
  while read -rs -t 0.05 -k 1 _; do :; done
  read -rk1 "?rex-acp exited with status $st; press a key to close "
fi
done_
]=]

rex.action{
  name  = "new_work",
  title = "New Work in a Project",
  keywords = "project worktree claude rex-acp session new",
  args  = { project = "string?", worktree = "string?" },
  run   = function(ctx, args)
    local projects = load_projects()
    if #projects == 0 then
      error("no projects: list them in ~/.config/rex/projects.lua", 0)
    end

    local project
    if args.project ~= nil then
      for _, p in ipairs(projects) do
        if p.label == args.project or p.dir == args.project then project = p end
      end
      if project == nil then error("no project named " .. args.project, 0) end
    else
      local items = {}
      for _, p in ipairs(projects) do
        table.insert(items, { id = p.label, title = p.label, subtitle = parent(p.dir), icon = "folder" })
      end
      local label = rex.ui.pick{
        title = "New work", placeholder = "Search projects", confirm = "Choose", items = items,
      }
      if label == nil then return end
      for _, p in ipairs(projects) do
        if p.label == label then project = p end
      end
    end

    local name = args.worktree
    if name == nil then
      -- "." can't be a worktree's name, so it stands for the main checkout.
      local items = { { id = ".", title = "Main checkout", subtitle = tilde(project.dir), icon = "folder" } }
      for _, w in ipairs(worktrees(project.dir)) do
        table.insert(items, { id = w.name, icon = "branch", detail = w.branch })
      end
      local picked = rex.ui.pick{
        title = project.label .. " · new work", placeholder = "Pick a worktree, or type a new name",
        confirm = "Start", items = items, allow_other = true,
      }
      if picked == nil then return end
      if type(picked) == "table" then name = picked.text
      elseif picked == "." then name = ""
      else name = picked end
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-"):gsub("^#", "")

    local title = project.label
    if name ~= "" then title = project.label .. " · " .. name end
    local s, err = rex.call("session.create", {
      label = title,
      initial_windows = { {
        layout = rex.layout.block{
          flavor  = "com.superlogical.terminal.shell",
          options = {
            cwd     = project.dir,
            shell   = "none",
            command = { "zsh", "-f", "-c", new_work_run, "new-work", project.dir, name },
          },
        },
      } },
    })
    if err ~= nil then error(err, 0) end
    -- Show it. Only an action run from a key or the palette has a client to
    -- ask; from the CLI there may be none, and the session is still made.
    pcall(rex.client.queue, "session.select", { session_id = s.session_id })
    return { session_id = s.session_id, label = title }
  end,
}
rex.bind("cmd+b", "new_work")

-- rex-acp's questions in the command palette: the acp_ask action, from the
-- file `rex-acp rex-setup` writes beside this one, when there is one.
do
  local acp = loadfile(home .. "/.config/rex/rex-acp.lua")
  if acp ~= nil then acp() end
end
