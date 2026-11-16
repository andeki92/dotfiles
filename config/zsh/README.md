# Zsh

## Files

| Path | Read by | Holds |
|------|---------|-------|
| `.zshenv` → `~/.zshenv` | every zsh, scripts and `zsh -c` included | plain exports: XDG dirs, `DO_NOT_TRACK`, the Homebrew switches, `KUBECONFIG` |
| `.zshrc` → `~/.zshrc` | interactive shells | loads `eager/`, then queues `lazy/` |
| `.config/zsh/eager/` | interactive, before the first prompt | numbered `NN-name.zsh`: platform and PATH, history, mise, aliases, tool functions, the prompt |
| `.config/zsh/lazy/` | interactive, after the first prompt | fzf integration, completion, the update reminder, heavier functions |
| `.config/zsh/completions/` | compinit | vendored completion functions (see its README) |
| `.config/zsh/plugins/` | `eager/15-defer.zsh` | zsh-defer, a git submodule |

PATH isn't in `.zshenv`: on macOS, `/etc/zprofile`'s `path_helper` reorders
it after `.zshenv` runs. Neither is the gitlab.com credential
(`GIT_CONFIG_*` in `eager/10-platform.zsh`): the claude launchers strip it
from agent sessions, and `.zshenv` would hand it back to every shell an
agent starts.

## Load order

1. `.zshenv`.
2. `eager/*.zsh` in numeric order.
3. `lazy/*.zsh` in numeric order, as one zsh-defer task once the first prompt
   is drawn. Nothing in `lazy/` exists in `zsh -i -c`, so anything a command
   line or script needs belongs in `eager/`.
4. Tasks the lazy files queue with zsh-defer themselves: compinit, kubectl
   completion, the update reminder.

zsh-defer sends a task's stdout and stderr to /dev/null unless it's queued
with `-1` / `-2`.

## Startup speed

- `eager/16-cached-init.zsh` defines `_cached_init`, which keeps the output
  of an init command (`starship init`, `fzf --zsh`, `kubectl completion`)
  under `$XDG_CACHE_HOME/zsh/init/` and regenerates it when the command's
  binary resolves to a different file. Delete that directory to force a
  refresh.
- compinit runs its full check at most once a day, `compinit -C` otherwise.
  `rm ~/.cache/zsh/zcompdump` picks up a new completion at once.
- `scripts/benchmark.sh` times `zsh -i -c exit`, so it measures `.zshenv`
  and `eager/` only. Profile with `zmodload zsh/zprof`.

## History

`eager/20-history.zsh`: one file, `$XDG_DATA_HOME/zsh/history`, shared live
between shells (`SHARE_HISTORY`), up to 100,000 entries. Duplicates are
trimmed first when it's full and skipped by up-arrow; fzf's Ctrl+R lists
each command once. A command with a leading space isn't saved. Neither is
one that looks like it carries a secret (password, token, api key, bearer,
cookie or authorization headers, `export *_SESSION=` and the like): it stays
in that shell's own history for up-arrow but never reaches the file.

## Keys

| Key | Runs |
|-----|------|
| Ctrl+R | fzf history search |
| Ctrl+T | fzf file picker, inserted at the cursor |
| Alt+C | fzf `cd` |
| Ctrl+P | `fp`: project switcher |
| Ctrl+O | `fcd`: `cd` into a directory below this one |
| Ctrl+F | `fe`: open files in `$EDITOR` |

Ctrl+P/O/F park whatever you were typing and put it back at the next prompt.

## Updates

`lazy/70-updates.zsh` reminds you when Homebrew or mise hasn't been
updated for `UPDATE_REMINDER_DAYS` days (3 by default).

| Command | Alias | Does |
|---------|-------|------|
| `update_brew` | `brewup` | `brew update && brew upgrade && brew cleanup` |
| `update_mise` | `miseup` | `mise upgrade` |
| `update_all` | `updateall` | both |

## Reloading

`rl` is `exec zsh`: a fresh shell, so aliases and functions a newer config
no longer defines don't linger. `typeset -U path` (`eager/10-platform.zsh`)
keeps PATH free of duplicates.

## References
- [zsh-defer](https://github.com/romkatv/zsh-defer)
- [zsh options](https://zsh.sourceforge.io/Doc/Release/Options.html)
