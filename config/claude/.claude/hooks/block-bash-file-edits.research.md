# Enforcing Edit/Write over shell edits in Claude Code — findings

**Question (as asked):** What are the most robust ways to make Claude Code use
its Edit/Write tools instead of editing files through Bash (sed -i, redirects,
tee, inline interpreter writes, cp/mv, scripts that write files), beyond
regex-matching the command text in a PreToolUse hook — how strong is each, what
does the strongest look like on macOS, and what does it cost?

Sources read 2026-10-02. "Docs" = code.claude.com/docs/en/…; "srt" =
github.com/anthropics/sandbox-runtime README.

## Short answer

Only one mechanism enforces this **by what the process does rather than what
the command says**: the Bash sandbox's `sandbox.filesystem.denyWrite`. It is
applied by macOS Seatbelt to the running command and every child it starts,
and Claude's Edit/Write tools run outside the sandbox, so a deny on source
paths stops `sed -i`, redirects, scripts, `cp`, `bash -c` — everything — while
Edit/Write keep working. The cost is that every Bash-side writer of those
paths fails too: `git checkout`/`merge`/`stash`/`reset`, formatters, codegen.
Those need `excludedCommands` entries, and each entry is a hole.

Everything else is detection, not prevention: the existing regex hook (cheap,
blind to indirection), permission `Bash(...)` deny rules (docs call them
fragile), and a before/after `git status` diff around each Bash call (catches
everything, but only after the write, and only tells the model).

Recommendation: keep the regex hook as fast feedback; add the PostToolUse
diff audit as the catch-all (global, no breakage); turn on the sandbox
`denyWrite` per project only where it is worth the git/formatter carve-outs.

## Findings

### 1. Bash sandbox with `denyWrite` — prevention, OS-enforced

- The sandbox is "a boundary that the operating system enforces around the
  shell commands Claude runs … the limits apply to Bash, PowerShell, and
  Monitor commands and the processes they start." — docs/sandboxing
- macOS enforcement is Seatbelt: "sandboxing uses the built-in Seatbelt
  framework"; srt: "Uses `sandbox-exec` with dynamically generated Seatbelt
  profiles". — docs/sandboxing; srt
- "The operating system enforces the sandbox boundary on the running process,
  so it holds regardless of what the model chose to run and even if an
  allowed command does more than its name suggests." — docs/sandboxing
- **Edit/Write are not sandboxed:** "The sandbox covers shell commands only.
  Claude's file tools, MCP servers, and hooks run outside it" and "tools such
  as Read, Edit, Write … follow permission rules instead." — docs/sandboxing
- Default writes: "commands inside the sandbox can write to the working
  directory, per-user temp directory, and any directories you've added".
  — docs/sandboxing
- `sandbox.filesystem.denyWrite` "Block[s] subprocess access to specific
  paths". — docs/sandboxing (settings table); docs/settings-reference index
- **Deny wins for writes:** "`denyWrite` creates exceptions within allowed
  paths (deny takes precedence)"; "`denyWrite` overrides `allowWrite`". — srt.
  So a narrower `allowWrite` cannot re-open a path inside a `denyWrite`
  region; carve the deny list narrowly instead.
- Path syntax: in project `.claude/settings.json` "the relative path `.`
  resolves to the project root"; in `~/.claude/settings.json` it resolves to
  `~/.claude`. — docs/sandboxing. macOS paths "support git-style glob
  patterns … cover existing and new files alike." — srt
- **Do not use `Edit(...)` deny rules for this:** "`Read` and `Edit` deny
  rules — Block access to specific files or directories" apply to the file
  tools as well, so they would block Edit too. — docs/sandboxing settings table
- Escape hatches and how to close them:
  - Unsandboxed retry via `dangerouslyDisableSandbox`; "You can disable
    unsandboxed retry by setting `"allowUnsandboxedCommands": false` … Claude
    Code ignores the `dangerouslyDisableSandbox` parameter." — docs/sandboxing
  - `excludedCommands` "run unsandboxed"; "If you write a pattern that covers
    an interpreter, a script inside the working directory, or a tool that acts
    on a file there … Claude can write the file and then run it outside the
    sandbox." — docs/sandboxing
  - `failIfUnavailable` stops a silent fallback to unsandboxed. — docs/sandboxing
- **Git:** "`git merge`, `git checkout`, and similar commands fail with
  `unable to unlink old` when they need to replace a file the sandbox denies
  writes to … Under one of your `denyWrite` entries". — docs/sandboxing.
  In a linked worktree "the sandbox also allows writes to the main
  repository's shared `.git` directory so commands like `git commit` update
  refs and the index". — docs/sandboxing. So `git commit` works; anything that
  rewrites tracked files under a denied path does not.
- Strength: holds against scripts, functions, variables, `bash -c`, `cp`/`mv`,
  `patch`, `git apply` — all the current hook's blind spots. Gaps: excluded
  commands, commands the user types at `!`, and anything outside the deny list.

### 2. Permission `Bash(...)` deny rules — text matching, weaker than the hook

- A rule like `Bash(rm *)` does not match `/bin/rm`, `bash -c 'rm …'`, or a
  quoted subcommand; the docs warn Bash permission patterns are fragile and
  point to the sandbox for deterministic enforcement. — docs/permissions
  ("What a Bash rule doesn't match" table, as reported by a docs-reading
  agent; not re-fetched)
- Compound commands are matched per subcommand. — docs/permissions (same)
- Verdict: strictly weaker than the existing hook, which already strips
  heredoc bodies and quotes. Not worth adding.

### 3. PostToolUse diff audit — detection of every write, after the fact

- PostToolUse cannot undo: exit 2 "Shows stderr to Claude; the tool already
  ran"; `decision: "block"` with `reason` feeds back; `additionalContext`
  lands "next to the tool result". — docs/hooks
- No hook input lists the files a Bash call changed. The docs' Bash
  PreToolUse example carries `tool_input.command`, `cwd` and `tool_use_id`
  only. — docs/hooks. (A docs agent claimed the docs describe before/after
  snapshotting; no such section was found on the page. Treat the design below
  as inference.)
- Hooks run outside the sandbox with full access, so a hook can run git.
  — docs/sandboxing

### 4. Stop hook audit — end-of-turn backstop

- Stop: exit 2 "Prevents Claude from stopping, continues the conversation";
  `decision: "block"` + `reason` likewise. — docs/hooks
- A block cap via `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (8) was reported by the
  docs agent but could not be confirmed on the fetched page.

### 5. The `if` field

- "Permission rule syntax to filter when this hook runs … Only evaluated on
  tool events" and "Because the `if` filter is best-effort, use the
  permission system rather than a hook to enforce a hard allow or deny."
  — docs/hooks. Useful to keep a hook off irrelevant calls, not to enforce.

### 6. No dedicated switch

- No setting or env var that disables Bash file writes while leaving Edit
  alone was found besides the sandbox lists. — docs/sandboxing,
  docs/settings-reference index.

## Sketches (inference, built from the cited behaviour)

### A. Per-project sandbox deny (strongest; project `.claude/settings.json`)

```json
{
  "sandbox": {
    "enabled": true,
    "allowUnsandboxedCommands": false,
    "failIfUnavailable": true,
    "filesystem": {
      "denyWrite": ["./skills", "./lib", "./hooks", "./docs", "./scripts"]
    },
    "excludedCommands": ["git checkout *", "git merge *", "git switch *",
                         "git stash *", "git reset *", "git restore *",
                         "git rebase *", "git pull *", "git fetch *",
                         "git push *"]
  }
}
```

Name the source directories, not `.`: build outputs, `.specs/`, `target/`,
`node_modules/` and tool caches stay writable. Each excluded git verb can
still rewrite a file (`git checkout <sha> -- f`), but its effect is a
reviewable git operation, which is the thing being protected. Add formatters
(`cargo fmt *`, `prettier --write *`) only if they should write sources; else
let them fail and run them yourself. The sandbox also restricts network, so
git's network verbs need the exclusion (or an allowed domain) regardless.

### B. Global PostToolUse diff audit (catch-all; `~/.claude/settings.json`)

1. PreToolUse, matcher `Bash`: in `cwd`, if it is a git work tree, write
   `git status --porcelain=v1 -z --untracked-files=all` plus mtimes of the
   listed paths to `${TMPDIR}/claude-bash-audit/<tool_use_id>`. Exit 0 always.
2. PostToolUse, matcher `Bash`: take the same snapshot, diff against the saved
   one, drop scratch and ignored paths and commands allowed to write (an
   allowlist: `git *`, `cargo *`, `npm *`, formatters, test runners). If a
   remaining source-looking path changed, exit 2 with "this Bash call changed
   <paths>; redo the change with Edit/Write (or `git restore` it)". Delete the
   snapshot either way.
3. Optional Stop hook: the same diff against a session-start snapshot, to
   catch anything a background command wrote.

Caveat (inference): Claude can issue Edit and Bash calls in parallel, so a
diff can attribute an Edit's change to a Bash call. Record each Edit/Write
`file_path` in a PostToolUse hook and skip paths edited since the Bash call's
PreToolUse.

### C. Keep the existing regex hook

It is the only option that stops the write *before* it happens without the
sandbox, and gives the model the reason immediately. Keep it as the first
line; B covers what it cannot see.

## Trade-offs

| Option | Stops the write | Sees scripts / `bash -c` / cp | Breaks | Cost |
|---|---|---|---|---|
| Regex PreToolUse (current) | yes | no | rare false positives | ~ms |
| `Bash(...)` deny rules | yes | no | — | none; weaker than current |
| Sandbox `denyWrite` | yes | yes | git checkout/merge/stash, formatters, codegen into denied paths | per-project config; excludedCommands are holes |
| PostToolUse diff | no (after) | yes | nothing | two `git status` per Bash call |
| Stop audit | no (end of turn) | yes | nothing | one diff per turn |

## Could not establish

- Whether `denyWrite` can be set once in **user** settings for every project:
  a `.`-relative entry there resolves to `~/.claude`, so it looks per-project
  only.
- The full PostToolUse input schema for Bash (`tool_response` fields) and the
  Stop block cap: the fetched hooks page was truncated before those sections.
- Whether `excludedCommands` patterns match `git -C … checkout` or other
  global-flag forms.
