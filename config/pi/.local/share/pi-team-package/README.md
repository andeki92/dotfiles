# pi-team-package

Self-contained Pi package for a baseline coding-agent setup. Designed to be installed locally during prototyping (`~/.local/share/pi-team-package`) and lifted unchanged into its own git repository (`git:github.com/<org>/pi-team-package@vX.Y.Z`).

## Contents

- `extensions/gondolin-sandbox/` — Fail-closed Gondolin micro-VM sandbox for Pi's built-in file/shell tools and `!` commands, configured via `~/.config/sandbox.toml`, with allowlisted environment variables and default-deny HTTP(S) egress.
- `extensions/usage-insights/` — Metadata-only local JSONL usage recorder (`schemaVersion: 1`) with a single isolated `exportUsageEvent()` sink ready for an OTLP/HTTP collector.
- `gondolin-image/` — Custom Alpine guest image definition (`pi-sandbox:latest`) with `git`, `gh`, `kustomize`, `ripgrep`, `jq`, `node`, `python3`, and `uv`.
- `skills/gitops-kustomize/` — GitOps skill for Kubernetes + Argo CD + kustomize.
- `prompts/gitops-review.md` — `/gitops-review` diff review template.
- `templates/` — Reference `AGENTS.md`, `settings.template.json` (`defaultProjectTrust: "ask"`, `codemode` enabled, pinned third-party packages), and `subagents.config.json`.
- `pi-pin.json` — Single source of truth for the pinned Pi version and third-party package pins.

## Tests

```bash
npm test
```

## Installing from a git repo (once lifted out of dotfiles)

```bash
pi install git:github.com/<org>/pi-team-package@v0.1.0
```
