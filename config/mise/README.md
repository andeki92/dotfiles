# mise-en-place

[mise](https://mise.jdx.dev/) manages every developer tool and language
runtime outside Homebrew: one global config here, plus a `mise.toml` in each
project that needs its own.

## Structure

- `.config/mise/config.toml` — the global toolset and settings, stowed to
  `~/.config/mise/config.toml`.
- `config/zsh/.config/zsh/eager/50-mise.zsh` — `mise activate zsh` runs eagerly
  so PATH is right before the first prompt; completions are deferred.
- `config/zsh/.config/zsh/lazy/70-updates.zsh` — `miseup` (`mise upgrade`) and
  the weekly "updates available" nudge.
- `.github/renovate.json` — Renovate's `mise` manager proposes version bumps
  for the global config (lua is held back for LazyVim).

## Conventions

- **Pin exact versions.** Renovate moves them; `latest` is the exception
  (node), not the rule.
- **One-week release cooldown.** `minimum_release_age = "7d"` means a fuzzy
  version (`latest`, `3`, `stable`) never resolves to a release younger than a
  week, matching Renovate's own cooldown. Exact pins are not filtered.
- **Prefer prebuilt binaries.** Use the registry short name, or `aqua:` /
  `github:` for tools that publish release assets. `cargo:` tools go through
  `cargo-binstall` when the crate publishes binaries; binstall's
  cargo-quickinstall fallback (third-party rebuilds) stays off.
- **Python CLIs use `pypi:`** (the backend formerly called `pipx:`), installed
  with `uv tool` via `[settings.pypi] uvx = true`.
- **Projects commit a `mise.lock`** when they need the exact asset a developer
  and CI install to be the same: `lockfile = true` and `lockfile_platforms` in
  the project's `[settings]`, then `mise lock`. CI installs with
  `mise install --locked`, which uses only the locked URLs and checksums and
  makes no GitHub API calls.

## Usage

```bash
mise install                # install what the current directory's configs ask for
mise use -g <tool>@<ver>    # add a tool to the global config (then commit config.toml)
mise outdated --bump        # list newer versions, including outside pinned ranges
mise upgrade --bump         # bump pins in config files and install
mise prune                  # remove installed versions no tracked config uses
mise lock                   # (re)write a project's mise.lock
mise doctor                 # diagnose activation, PATH and config problems
```

## Documentation

- [Configuration](https://mise.jdx.dev/configuration.html)
- [Settings](https://mise.jdx.dev/configuration/settings.html)
- [Lockfiles](https://mise.jdx.dev/dev-tools/mise-lock.html)
