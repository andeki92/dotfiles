---
name: sandbox-pr-workflow
description: Use when cloning a repository, making changes, and opening a pull request from inside the Gondolin sandbox using git and gh.
---

# Sandbox PR Workflow

Follow these steps when shipping changes from inside the sandbox:

1. **Work on a branch**: Clone over HTTPS (`gh repo clone <owner>/<repo>` or `git clone https://github.com/<owner>/<repo>.git`) and create a focused feature branch (`git checkout -b <type>/<short-name>`).
2. **Keep changes minimal and verified**: Run the repository's own tests and linters inside the VM before committing.
3. **Never inspect or log tokens**: `GH_TOKEN` / `GITHUB_TOKEN` in the VM are host-substituted placeholders; let `git` and `gh` use them transparently without printing credentials.
4. **Push and open a PR**: Push the branch over HTTPS (`git push -u origin <branch>`) and open a pull request with `gh pr create` summarizing the changes and verification performed.
