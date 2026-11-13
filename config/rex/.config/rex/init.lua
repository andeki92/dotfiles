rex.bind("cmd+r", "client.config.reload")

local home = os.getenv("HOME")

local function shell_at(dir)
  return rex.layout.block{
    flavor  = "com.superlogical.terminal.shell",
    options = { cwd = dir },
  }
end

-- New work: a small floating pane asks for a worktree's name, such as
-- 123-flaky-tests, then opens a tab of that name running `c -w <name>` in the
-- focused pane's repository. From inside .claude/worktrees/ it uses the main
-- checkout, where `claude -w` belongs. Empty input or ctrl+c cancels.
local new_work_prompt = [=[
print -n "\e[H\e[2J"; print -P "%BNew work%b in ${1:t}  %F{8}(Enter starts it; empty or ctrl+c cancels)%f"
read -r "name?worktree: " || exit 0
[[ -n $name ]] || exit 0
rex window new -s "$REX_SESSION" "$name" -c "$1" -- zsh -ic 'c -w "$1"' new-work "$name" >/dev/null
]=]

rex.action{
  name  = "new_work",
  title = "New Work in a Worktree",
  keywords = "worktree claude branch issue",
  run   = function(ctx, args)
    local cwd = home
    if ctx.block_id ~= nil then
      local p = rex.block.call("com.superlogical.terminal", "process",
        { block_id = ctx.block_id })
      if p ~= nil and p.foreground ~= nil and p.foreground.cwd ~= nil then
        cwd = p.foreground.cwd:gsub("/%.claude/worktrees/.*$", "")
      end
    end
    local l, err = rex.session.new_layer{
      bounds = { 0.2, 0.35, 0.6, 0.15 },
      focus  = true,
      layout = rex.layout.block{
        flavor  = "com.superlogical.terminal.shell",
        options = {
          cwd     = cwd,
          shell   = "none",
          command = { "zsh", "-ic", new_work_prompt, "new-work", cwd },
        },
      },
    }
    if err ~= nil then error(err, 0) end
    return { block_ids = l.block_ids, cwd = cwd }
  end,
}
rex.bind("cmd+b", "new_work")

-- Pinned sessions: each label has a home directory. A new tab (cmd+t) in a
-- pinned session opens there; other sessions keep Rex's own new tab.
-- "Open Pinned Sessions", from the command palette, recreates any that are gone.
--
-- The pins are each machine's own config and are never committed: they live
-- in ~/.config/rex/pinned.lua. Start it from pinned.example.lua beside it.
-- Without that file there are no pins, and cmd+t is Rex's own new tab.
local function load_pins()
  local path = home .. "/.config/rex/pinned.lua"
  local chunk, load_err = loadfile(path)
  if chunk == nil then
    local f = io.open(path, "r")
    if f ~= nil then
      f:close()
      rex.log("warn", "pinned.lua: " .. tostring(load_err))
    end
    return {}
  end
  local ok, list = pcall(chunk)
  if not ok or type(list) ~= "table" then
    rex.log("warn", "pinned.lua: expected a list of { label, dir }")
    return {}
  end
  for _, p in ipairs(list) do
    p.dir = (p.dir or home):gsub("^~", home)
  end
  return list
end
local pinned = load_pins()

local function session_labels()
  local list, err = rex.call("session.list")
  if err ~= nil then error(err, 0) end
  local labels = {}
  for _, s in ipairs(list.sessions or {}) do labels[s.session_id] = s.label end
  return labels
end

rex.action{
  name  = "pinned_tab",
  title = "New Tab in Pinned Directory",
  keywords = "tab new pinned project directory",
  run   = function(ctx, args)
    local label = session_labels()[ctx.session_id]
    for _, p in ipairs(pinned) do
      if p.label == label then
        local w, err = rex.session.new_window{ layout = shell_at(p.dir) }
        if err ~= nil then error(err, 0) end
        return { window_id = w.window_id, block_ids = w.block_ids, cwd = p.dir }
      end
    end
    rex.client.queue("client.tab.new")
  end,
}
rex.bind("cmd+t", "pinned_tab")

rex.action{
  name  = "pinned_sessions",
  title = "Open Pinned Sessions",
  keywords = "pinned sessions default restore",
  run   = function(ctx, args)
    local have = {}
    for _, label in pairs(session_labels()) do have[label] = true end
    local created = {}
    for _, p in ipairs(pinned) do
      if not have[p.label] then
        local s, err = rex.call("session.create", {
          label = p.label,
          initial_windows = { { layout = shell_at(p.dir) } },
        })
        if err ~= nil then error(err, 0) end
        table.insert(created, s.session_id)
      end
    end
    return { created = created }
  end,
}
