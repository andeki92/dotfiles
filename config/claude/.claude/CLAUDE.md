# ship runs build in a worktree

Every `ship` run builds in an isolated git worktree. This line is the standing
instruction `EnterWorktree` needs, so `grill` enters one without asking and
says so in one line. To keep a particular run in the current checkout, say so
when starting it.
