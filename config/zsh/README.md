# Zsh Configuration

## Structure
- **eager/**: Eagerly loaded config files (core, platform, env, history, Homebrew, aliases)
- **lazy/**: Lazily loaded plugins and heavy config (using zsh-defer)
- **plugins/**: Bundled plugins (e.g., zsh-defer)
- `.zshrc`: Entrypoint, sources all config in order

## Load Order
1. Eager files: `*.zsh` in numeric order
2. Lazy files: `lazy/*.zsh` in numeric order (using zsh-defer)
3. Aliases: Always last

## Optimization Checklist
- [ ] Use `zprof` to profile startup and identify slow segments
- [ ] Defer all plugins and heavy config with `zsh-defer`
- [ ] Avoid running external commands at startup (e.g., `uname`, `git`)
- [ ] Minimize the number of sourced files (combine small files if possible)
- [ ] Use `zcompile` to precompile config files for faster loading
- [ ] Set environment variables as early as possible
- [ ] Only load what is needed for interactive shells
- [ ] Use autoload for rarely-used functions
- [ ] Keep aliases minimal and load them last

## Stow Ignore for Markdown
To prevent stow from symlinking markdown files (like this README), add the following to your `.stowrc`:

```
--ignore=README.md
--ignore=*.md
```

## References
- [zsh-defer](https://github.com/romkatv/zsh-defer)
- [zsh XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
- [zsh startup optimization](https://zsh.sourceforge.io/Doc/Release/Options.html) 