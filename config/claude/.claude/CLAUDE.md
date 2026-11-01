# ship runs build in a worktree

Every `ship` run builds in an isolated git worktree. This line is the standing
instruction `EnterWorktree` needs, so `ship` enters one without asking as soon
as it has the feature name, and says so in one line. To keep a particular run
in the current checkout, say so when starting it.

# Scratch files go in .scratch/

Put scratch files, downloads and probes in `.scratch/` at the root of the
folder you work in, a checkout or a worktree, and name them by relative path.
This replaces the default instruction to use `$TMPDIR`. Git ignores `.scratch/`
everywhere. This Mac's Claude Code floor checks each shell command's text
before it runs, and stops a command that reaches the network for approval when
one of its paths goes through `$TMPDIR` or another variable.

- Give each download a new folder of its own:
  `curl -o .scratch/downloads/<name>/page.html <url>`.
- Keep probes apart from downloads, in `.scratch/probes/`:
  `python3 .scratch/probes/check.py .scratch/downloads/<name>/page.html`.

