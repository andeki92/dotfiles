---
description: Review current workspace changes for correctness, tests, portability, and accidental secrets before opening a PR
---
Review the current changes in this repository:

1. Check logic, edge cases, and error handling across modified files.
2. Verify relevant tests and linters exist and pass for the changed behavior.
3. Check for hardcoded usernames, absolute home paths, machine-local state, or accidentally staged secrets/credentials.
4. Report concrete findings grouped by severity, or confirm the diff is ready for a PR.
