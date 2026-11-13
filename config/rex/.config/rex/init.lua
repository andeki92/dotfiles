rex.bind("cmd+r", "client.config.reload")

local home = os.getenv("HOME")

-- New work: one Rex session per piece of work, the way Rex's agent hook
-- expects (it names the whole session after the agent's task). The session
-- starts as "<Repo> - new work" with a single pane that asks for a worktree's
-- name, such as 123-flaky-tests. Enter renames the session to
-- "<Repo> - <name>", such as "0th - 123-flaky-tests", and runs
-- `c -w <name>` in the focused pane's repository, or in its main checkout
-- from inside .claude/worktrees/. Empty input or ctrl+c cancels. The session
-- removes itself when Claude exits, since Rex keeps a session with no windows.
--
-- The prompt runs in a bare zsh (-f), so it shows at once and ctrl+c is caught
-- from the start; only `c` gets the interactive shell that defines it. Rex
-- exports REX_BIN_DIR into every pane, which finds `rex` without a PATH.
local new_work_prompt = [=[
rex() { command "${REX_BIN_DIR:+$REX_BIN_DIR/}rex" "$@"; }
done_() { rex kill "$REX_SESSION" >/dev/null 2>&1; exit 0; }
trap done_ INT
print -n "\e[H\e[2J"
print -P "%BNew work%b in ${2}  %F{8}(Enter starts it; empty or ctrl+c cancels)%f"
read -r "name?worktree: " || done_
[[ -n $name ]] || done_
rex session rename "$REX_SESSION" "$2 - $name" >/dev/null 2>&1
cd -- "$1" || { read -rk1 "?cannot enter $1; press a key to close "; done_; }
trap ':' INT
zsh -ic 'c -w "$1"' new-work "$name"
st=$?
(( st == 0 )) || read -rk1 "?c exited with status $st; press a key to close "
done_
]=]

rex.action{
  name  = "new_work",
  title = "New Work in a Worktree",
  keywords = "worktree claude branch issue session",
  run   = function(ctx, args)
    local cwd = home
    if ctx.block_id ~= nil then
      local p = rex.block.call("com.superlogical.terminal", "process",
        { block_id = ctx.block_id })
      if p ~= nil and p.foreground ~= nil and p.foreground.cwd ~= nil then
        cwd = p.foreground.cwd:gsub("/%.claude/worktrees/.*$", "")
      end
    end
    -- The repository's folder name, first letter capitalised: notes is Notes.
    local repo = cwd:match("([^/]+)$") or "home"
    local title = repo:sub(1, 1):upper() .. repo:sub(2)
    local s, err = rex.call("session.create", {
      label = title .. " - new work",
      initial_windows = { {
        layout = rex.layout.block{
          flavor  = "com.superlogical.terminal.shell",
          options = {
            cwd     = cwd,
            shell   = "none",
            command = { "zsh", "-f", "-c", new_work_prompt, "new-work", cwd, title },
          },
        },
      } },
    })
    if err ~= nil then error(err, 0) end
    -- Show it. Only an action run from a key or the palette has a client to
    -- ask; from the CLI there may be none, and the session is still made.
    pcall(rex.client.queue, "session.select", { session_id = s.session_id })
    return { session_id = s.session_id, cwd = cwd }
  end,
}
rex.bind("cmd+b", "new_work")
