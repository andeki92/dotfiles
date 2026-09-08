# DO_NOT_TRACK — the cross-tool convention (consoledonottrack.com) for "do not
# send usage data anywhere". Set once here so every tool that honours it is
# opted out without a switch of its own; tools that ignore it still need
# theirs, so HOMEBREW_NO_ANALYTICS (30-brew.zsh) and HEADROOM_BEACON
# (lazy/81-herdr-claude.zsh) stay where they are. headroom does read
# DO_NOT_TRACK, and ranks it above its own flag.
export DO_NOT_TRACK=1
