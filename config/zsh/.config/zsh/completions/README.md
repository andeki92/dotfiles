# Completions

Completion functions that no installed package provides, on `fpath` ahead of
`compinit` (`lazy/60-completion.zsh`).

| File | From | Why here |
|------|------|----------|
| `_kubectx`, `_kubens` | [ahmetb/kubectx](https://github.com/ahmetb/kubectx) v0.11.0 `completion/`, Apache-2.0 (`LICENSE-kubectx`) | mise installs kubectx/kubens as bare binaries; Homebrew's formula is what normally ships these. Refresh them when `kubectx` in `config/mise` moves to a release that changes them. |

They also complete `kctx` and `kns` (`eager/43-kubectl.zsh`); the `kx`/`kn` aliases
complete as the commands they expand to.
