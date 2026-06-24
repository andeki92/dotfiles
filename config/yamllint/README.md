# yamllint

Global [yamllint](https://yamllint.readthedocs.io/) ruleset.

Stowed: `config/yamllint/.config/yamllint/config` → `~/.config/yamllint/config`.

yamllint auto-discovers this file at `$XDG_CONFIG_HOME/yamllint/config` whenever
a project has no local config (`.yamllint` / `.yamllint.yaml` / `.yamllint.yml`)
at its root. A project that needs different rules ships its own — that wins.

The binary is installed via mise (`pipx:yamllint`, using `uv` — see
`config/mise/.config/mise/config.toml`). It's consumed automatically by the
Claude Code lint-on-edit hook (`config/claude/.claude/hooks/linters/yaml.sh`),
so any YAML Claude writes is linted against this ruleset on the spot.

Edit the source here, never the symlink. No `stow -R` needed for value changes
(it's a symlink), but run it once after adding the file.
