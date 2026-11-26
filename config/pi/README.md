# pi — Pi Coding Agent Baseline (Sandbox, Distribution, Usage Insights)

Baseline setup for running the [Pi coding agent](https://docs.pi.dev) (pinned to `1.6.0`) inside a fail-closed [Gondolin](https://github.com/earendil-works/gondolin) Linux micro-VM with pinned extensions, `codemode` enabled by default, and metadata-only usage telemetry.

> Files under `config/pi/` are stowed into `~/.config/sandbox.toml` and `~/.local/` (`~/.local/bin/` and `~/.local/share/pi-team-package/`). `~/.pi/agent/` is intentionally **not** stowed so Pi's credentials (`auth.json`), sessions, trust store (`trust.json`), and managed releases never land in `.dotfiles`.

---

## Layout

```text
config/pi/
├── README.md
├── .config/
│   └── sandbox.toml                        # Default sandbox config (~/.config/sandbox.toml)
└── .local/
    ├── bin/
    │   ├── pi-self-update                  # Pinned self-update wrapper (PI_SELF_UPDATE_COMMAND / selfUpdateCommand)
    │   └── pi-usage-report                 # Summarises usage.jsonl + Atuin author=pi count
    └── share/
        └── pi-team-package/                # Self-contained Pi package (liftable to its own git repo unchanged)
            ├── package.json
            ├── package-lock.json
            ├── pi-pin.json                 # Single source of truth for Pi + third-party package versions
            ├── CHANGELOG.md
            ├── extensions/
            │   ├── gondolin-sandbox/       # Fail-closed micro-VM tool router + sandbox.toml policy loader
            │   └── usage-insights/         # Metadata-only JSONL telemetry (schema v1)
            ├── gondolin-image/             # Custom Alpine KVM guest image (git, gh, kustomize, rg, jq)
            ├── skills/gitops-kustomize/    # Kubernetes + Argo CD + kustomize GitOps skill
            ├── prompts/gitops-review.md    # /gitops-review prompt template
            └── templates/
                ├── AGENTS.md               # Global instructions (build/test + GitOps rule)
                ├── settings.template.json  # defaultProjectTrust: "ask", +codemode, pinned packages
                └── subagents.config.json   # forceTopLevelAsync: true (prevents foreground sandbox bypass)

scripts/
├── pi-bootstrap.sh                         # Idempotent setup for any WSL/Linux/macOS user
├── pi-build-image.sh                       # Builds & tags pi-sandbox:latest guest image (git, gh, kustomize)
└── pi-sandbox-verify.sh                    # Proves decoy isolation, sandbox.toml, git/gh placeholder auth, fail-closed, and usage JSONL
```

---

## Install (Fresh WSL2 User)

### Prerequisites
1. **Nested virtualization + `/dev/kvm` access** (for Gondolin's hardware-accelerated `krun` backend — no QEMU installation required on Linux x86_64):
   ```bash
   sudo usermod -aG kvm "$USER"
   # Then start a fresh WSL login (if using herdr, restart the server from a
   # fresh WSL shell where `id` includes `kvm`: `herdr server stop && herdr`)
   test -r /dev/kvm -a -w /dev/kvm && echo "KVM ready"
   ```
   *(Optional)* Installing `qemu-utils` or `qemu-system-x86` enables writable copy-on-write rootfs mounted at `/workspace`. Without `qemu-img`, Gondolin uses `krun` with a read-only rootfs, writable tmpfs `/tmp` + `/root`, and mounts the project at `/tmp/workspace` (boot + first exec ~370 ms on WSL2).
2. **Node.js >= 22.19**, `curl`, `stow` (installed via `mise` / `brew` in dotfiles).
3. *(Optional)* **Atuin** in local-only mode (`mise install atuin && stow -R atuin`) if you want agent-run command counts in `pi-usage-report`.

### Bootstrap
From the dotfiles repo root:

```bash
stow -R pi zsh atuin
./scripts/pi-bootstrap.sh
```

`scripts/pi-bootstrap.sh` is idempotent and:
1. Stows `config/pi` (`~/.local/bin/pi-self-update`, `~/.local/bin/pi-usage-report`, `~/.local/share/pi-team-package`).
2. Installs pinned Pi `1.6.0` using Pi's official release lockfiles (`https://pi.dev/api/installer/releases/1.6.0/package{,-lock}.json`) into `~/.pi/agent/install/`.
3. Installs the team package's runtime dependencies (`npm ci --ignore-scripts --include=optional`).
4. Links `~/.pi/agent/AGENTS.md` and merges `~/.pi/agent/settings.json` (`defaultProjectTrust: "ask"`, `defaultTools: ["+codemode"]`, `codemode.mode: "on"`, `selfUpdateCommand`, pinned packages) without clobbering personal model/theme preferences.
5. Writes `~/.pi/agent/extensions/subagent/config.json` with `forceTopLevelAsync: true` so `pi-subagents` never launches unsandboxed foreground children.
6. Reconciles pinned third-party packages (`pi update --extensions`).
7. Installs `herdr integration install pi` and Atuin's Pi hook (`atuin setup --only --agent-history --agents pi --no-threads --no-daemon --no-mcp --sync off`) when those CLIs are present.

### Verify
```bash
./scripts/pi-sandbox-verify.sh
```

---

## Updating Pi & Packages

Versions only move when `config/pi/.local/share/pi-team-package/pi-pin.json` (and `templates/settings.template.json`) changes:

1. Edit `piVersion` or `thirdPartyPackages` in `pi-pin.json` (and review source code of any bumped third-party package first).
2. Run:
   ```bash
   ./scripts/pi-bootstrap.sh
   ```
   Running `pi update` directly routes through `pi-self-update` (via `PI_SELF_UPDATE_COMMAND` and `settings.json`'s `selfUpdateCommand`), which refuses to jump ahead of `pi-pin.json` and only syncs to the pinned version.

### Verified Package Pin Syntax (Pi 1.6.0)
- **npm**: `npm:pkg@1.2.3` or `npm:@scope/pkg@1.2.3` (exact versions stay pinned on `pi update --extensions`).
- **git**: `git:github.com/<org>/<repo>@v1.2.3` or `@<commit-sha>` (tags and commits stay pinned).
- **local**: `~/.local/share/pi-team-package` (loaded in-place; swap to the `git:...` URL once moved to its own repo).

---

## Sandbox & Escape Hatch

### Default `pi` (Sandboxed, Fail-Closed)
Running `pi` starts a Gondolin micro-VM with:
- **Mandatory pre-launch fail-closed check**: Both the managed launcher (`~/.pi/agent/bin/pi`, generated by `pi-self-update`) and the zsh launcher (`config/zsh/.config/zsh/eager/47-ai.zsh`) execute `extensions/gondolin-sandbox/preflight.mjs` **before** exec'ing Pi. Because Pi's extension loader logs extension import errors and continues with host tools, this pre-launch check ensures Pi refuses to start (exit `2`) if `@earendil-works/gondolin` cannot import, `--no-extensions` is passed, `settings.json` omits the sandbox package, `sandbox.toml` has invalid entries, or `/dev/kvm` / the krun runner / QEMU binary is missing. Bypassed only for `pi-unsafe` (`PI_SANDBOX_UNSAFE=1`) or non-session CLI commands (`pi list`, `pi install`, `pi update`, `pi auth`, etc.).
- **Workspace guard**: Refuses to start from `/`, `$HOME`, `/mnt/c`, or any directory overlapping `~/.kube`, `~/.oci`, `~/.ssh`, or `~/.pi`.
- **Filesystem**: The current project directory is mounted read-write at `/workspace` (or `/tmp/workspace` on stock `alpine-base` without `qemu-img`). Trusted skill directories loaded by Pi outside the project (such as `skills/gitops-kustomize`) are mounted **read-only** (`ReadonlyProvider`) under `/tmp/pi-skills/...` with path translation so models can read `SKILL.md` and supporting files inside the sandbox without any general host-read fallback. Host `~/.kube`, `~/.oci`, `~/.ssh`, `~/.pi/agent`, `/mnt/c`, and WSL interop binaries (`powershell.exe`, `cmd.exe`) do not exist in the guest.
- **Environment scrubbing**: Strictly allowlisted guest env (`HOME=/root`, `USER=root`, `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`, `TERM`, `LANG`, `LC_ALL`, optional `COLORTERM`/`NO_COLOR`/`CI`). All `OCI_*`, `KUBECONFIG`, cloud, SSH, git token, provider key, and `WSL*` variables are dropped.
- **Network egress policy (default-deny)**: Enforced on the host by Gondolin's `createHttpHooks`:
  - `allowed_hosts`: git hosts (`github.com`, `api.github.com`, `uploads.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `codeload.github.com`, `gitlab.com`) and standard package registries (`registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`, `proxy.golang.org`, `sum.golang.org`, `crates.io`, `static.crates.io`, `index.crates.io`, `repo1.maven.org`, `plugins.gradle.org`, `dl-cdn.alpinelinux.org`).
  - `blockInternalRanges: true` (blocks RFC1918, loopback, link-local, and cloud IMDS `169.254.169.254`).
  - `dns: { mode: "synthetic" }` (blocks DNS exfiltration/tunneling).
  - `allowWebSockets: false` and raw TCP/UDP dropped.
  - Customise via `~/.config/sandbox.toml` (tracked defaults) and `~/.config/sandbox.local.toml` (machine-local overrides, gitignored), or one-off `PI_SANDBOX_*` env vars.

### Explicit Escape Hatch: `pi-unsafe`
When you intentionally need unsandboxed host tools:

```bash
pi-unsafe [args...]
```

`pi-unsafe` prints a loud warning banner, sets `PI_SANDBOX_UNSAFE=1`, displays `SANDBOX OFF (pi-unsafe)` in Pi's footer, and records `sandbox: { active: false, escapeHatchUsed: true }` in `usage.jsonl`.

### Configuration (`~/.config/sandbox.toml` + `~/.config/sandbox.local.toml`)

Sandbox settings live in `~/.config/sandbox.toml` (stowed from `config/pi/.config/sandbox.toml`) with optional machine-local overrides in `~/.config/sandbox.local.toml` (gitignored, so private repo names or local auth preferences never leak into public dotfiles):

```toml
# ~/.config/sandbox.local.toml (machine-local overrides, never committed)
[github]
# Option 1 (recommended): fine-grained repo-scoped PAT stored in a 0600 file
token_file = "~/.config/sandbox-gh-token"
# Option 2 (prototyping): delegate host `gh auth token` via placeholder substitution
use_host_auth = true
# Restrict git/API/GraphQL requests on the host to specific repositories
allowed_repos = ["my-org/my-repo", "my-org/gitops-*"]

[network]
extra_allowed_hosts = ["registry.internal.example"]
```

Environment variables (`PI_SANDBOX_GH_TOKEN`, `PI_SANDBOX_GH_USE_HOST_AUTH`, `PI_SANDBOX_GH_ALLOWED_REPOS`, `PI_SANDBOX_IMAGE`, `PI_SANDBOX_EXTRA_ALLOWED_HOSTS`, `PI_SANDBOX_CONFIG`) still override file settings for one-off invocations.

### GitHub CLI (`gh`) + Git Clone / Push / PR Inside KVM (Zero Real Token in VM)

The custom guest image **`pi-sandbox:latest`** (built automatically by `scripts/pi-bootstrap.sh` when `cpio`, `lz4`, and `e2fsprogs` are installed, or manually via `./scripts/pi-build-image.sh`) ships `git`, `gh` (`github-cli`), `kustomize`, `ripgrep`, `jq`, `make`, `patch`, `node`, `python3`, and `uv`, plus:
- `/workspace` pre-baked on the read-only rootfs (so `readonly` mode mounts directly at `/workspace` with zero `qemu-img` needed)
- `/etc/gitconfig` pre-configured with `credential.https://github.com.helper = !/usr/bin/gh auth git-credential` and `http.sslCAInfo = /run/gondolin/ca-certificates.crt`
- `/etc/resolv.conf` pointed at Gondolin's synthetic DNS gateway (`192.168.127.1`)

#### How GitHub auth works without exposing tokens to the VM
1. **Configure host-side GitHub auth** (recommended: fine-grained repo-scoped PAT, never SSH keys):
   - **Token file (recommended):**
     ```bash
     printf '%s\n' "github_pat_..." > ~/.config/sandbox-gh-token
     chmod 600 ~/.config/sandbox-gh-token
     ```
     *(Files looser than `0600` are rejected fail-closed.)*
   - **Or opt into host `gh` login** in `~/.config/sandbox.local.toml` (`use_host_auth = true`, paired with `allowed_repos = ["org/repo"]`).
   - **Or one-off env var:** `PI_SANDBOX_GH_TOKEN="github_pat_..." pi`.
2. **Inside the VM**, `GH_TOKEN` and `GITHUB_TOKEN` hold **only an opaque random placeholder (`ghp_<36 chars>`)** generated by Gondolin — never the real secret.
3. When the agent runs `gh repo clone`, `git clone`, `git push`, or `gh pr create`:
   - `gh` sends `Authorization: token <placeholder>` (REST/GraphQL) and `git` sends `Authorization: Basic base64(x-access-token:<placeholder>)` via `gh auth git-credential`.
   - Gondolin intercepts HTTPS on the host, decodes Basic/Bearer headers, and substitutes the real token **only** for `github.com`, `api.github.com`, and `uploads.github.com`.
   - Sending `$GH_TOKEN` to any other host (even allowlisted hosts like `registry.npmjs.org`) is blocked with `403 Forbidden`.
   - Setting `[github] allowed_repos` enforces an additional host-side repo allowlist on GitHub git URLs and REST `/repos/<owner>/<repo>` endpoints, and **blocks `/graphql`** (because arbitrary GraphQL documents can target other repos via inline arguments). Invalid `allowed_repos` entries fail closed at startup rather than silently disabling enforcement. For full `gh` GraphQL workflows (like `gh pr create`), use a GitHub **fine-grained repository-scoped PAT** in `token_file` with `allowed_repos = []` so GitHub itself enforces repo scope across Git, REST, and GraphQL.
4. Non-secret `GIT_AUTHOR_NAME`/`EMAIL` and `GIT_COMMITTER_NAME`/`EMAIL` are read from `[git]` in `sandbox.toml` (falling back to host `git config`) so commits inside the VM have proper attribution without mounting `~/.config/git`.

> **Rebuilding the guest image:** run `./scripts/pi-build-image.sh --force` after editing `gondolin-image/build-config.json`. Note: `pi-build-image.sh` also works around an `@earendil-works/gondolin@0.14.0` x86_64 bug where local `gondolin build` omits the 4096-byte ELF64 wrapper header on `krun-kernel`; the workaround becomes a no-op once fixed upstream.

---

## Residual Risk Outside the Gondolin Boundary

Under Gondolin, Pi itself and all extensions run **on the host** with your OS user permissions. Only Pi's built-in tools (`read`, `write`, `edit`, `bash`, `grep`, `find`, `ls`), `user_bash` (`!`), and `codemode` calls to those built-in tools run inside the micro-VM. What remains on the host:

1. **Pi process & credentials**: `~/.pi/agent/auth.json`, session transcripts, settings, and direct LLM provider API requests.
2. **Third-party extension tools** (verified by source audit before pinning):
   - **`pi-web-access@0.48.0`**: Runs HTTP requests on the host (bypasses Gondolin's egress allowlist, though it includes SSRF checks against internal IPs) and can spawn host `gh`, `git clone`, `yt-dlp`, `ffmpeg`, `xdg-open`, or configured `!command` resolvers. Browser cookie extraction (`chrome-cookies.ts`) is verified **off by default** (`allowBrowserCookies: false`).
   - **`pi-subagents@0.90.0`**: Foreground children (`async: false`) do **not** load ambient parent extensions and would bypass Gondolin; mitigated by shipping `forceTopLevelAsync: true` in `subagents.config.json` **and** a `tool_call` block in `gondolin-sandbox` rejecting `async: false`. Background children load Gondolin in their runner, unless an agent definition overrides `extensions: []`.
   - **`@plannotator/pi-extension@0.29.4`**: Starts local loopback HTTP servers, opens the host browser, runs host `git`/`gh`/`glab` for PR review, writes plan files on the host, and has a daily telemetry ping (`https://ping.plannotator.ai/ping`) enabled by default — **disabled** by exporting `NO_ANON_PING=1` and `DO_NOT_TRACK=1` in the `pi` launcher.
   - **`@juicesharp/rpiv-todo@2.15.0`** & **`@juicesharp/rpiv-ask-user-question@2.15.0`**: Pure session/TUI extensions (no network; `ask-user-question` spawns `$VISUAL`/`$EDITOR` only if you invoke external editing).
3. **Built-in MCP servers (`builtin:mcp`)**: Any configured stdio/HTTP MCP servers execute on the host.
4. **Read-write project mount**: Malicious edits inside `/workspace` (e.g. `.git/config` hooks/`core.fsmonitor`, `Makefile`, scripts, or `.pi/` project extensions — gated by `defaultProjectTrust: "ask"`, except `sessionDir`) could affect the host if you later execute them outside the VM.
5. **Host hooks**: `herdr-agent-state.ts` and `atuin.ts` observe Pi tool events on the host.

For untrusted repos or full process-level isolation (including third-party extensions and MCP), run the entire Pi process inside Docker Sandboxes or OpenShell (see `docs.pi.dev/latest/containerization`).

---

## Terminal Compatibility (Alacritty + herdr + WSL2)

Because Pi runs on the host while tools run inside Gondolin, Gondolin does not intercept terminal input or clipboard:
- **Newline**: `Shift+Enter` (or `Ctrl+J`).
- **Follow-up queue**: Pi's WSL default is **`Ctrl+Q`** (`Alt+Enter` is reserved by Windows Terminal; we keep Pi's default here without custom Alacritty bindings).
- **Clipboard**: In fullscreen mode `fullscreenCopyOnSelect` is on by default (`Ctrl+X` copies selection/last message). If clipboard copy through `herdr` doesn't reach Windows clipboard, set `export PI_CLIPBOARD_OSC52=1`.

---

## Usage Insights Event Schema (`schemaVersion: 1`)

Written locally as append-only JSONL (`0600`) to `${XDG_STATE_HOME:-~/.local/state}/pi/usage.jsonl` (override with `PI_USAGE_LOG_PATH`). One `session_summary` event is appended per session shutdown.

**Never recorded**: prompts, model outputs, file contents, command text, full filesystem paths outside `repoName`, or environment variables.

```json
{
  "schemaVersion": 1,
  "eventType": "session_summary",
  "startedAt": "2026-11-25T15:00:00.000Z",
  "endedAt": "2026-11-25T15:04:12.000Z",
  "durationMs": 252000,
  "sessionId": "uuid-or-ephemeral",
  "repoName": "payments-service",
  "piVersion": "1.6.0",
  "teamPackageVersion": "0.1.0",
  "mode": "tui",
  "startReason": "startup",
  "endReason": "quit",
  "provider": "anthropic",
  "model": "claude-sonnet-4-5",
  "modelsUsed": [
    {
      "provider": "anthropic",
      "model": "claude-sonnet-4-5",
      "responses": 4,
      "tokens": { "input": 12000, "output": 1800, "cacheRead": 9000, "cacheWrite": 3000, "total": 25800 },
      "costUsd": { "input": 0.036, "output": 0.027, "cacheRead": 0.0027, "cacheWrite": 0.01125, "total": 0.07695 }
    }
  ],
  "tokens": { "input": 12000, "output": 1800, "cacheRead": 9000, "cacheWrite": 3000, "total": 25800 },
  "costUsd": { "input": 0.036, "output": 0.027, "cacheRead": 0.0027, "cacheWrite": 0.01125, "total": 0.07695 },
  "turnCount": 4,
  "toolCalls": {
    "read": { "calls": 6, "errors": 0 },
    "bash": { "calls": 3, "errors": 1 }
  },
  "totalToolCalls": 9,
  "totalToolErrors": 1,
  "loadedExtensions": ["npm:@juicesharp/rpiv-todo@2.15.0", "pi-team-package"],
  "loadedSkills": ["gitops-kustomize"],
  "invokedSkills": ["gitops-kustomize"],
  "sandbox": {
    "active": true,
    "escapeHatchUsed": false,
    "backend": "krun"
  }
}
```

Notes on collection:
- `loadedExtensions` is derived from `sourceInfo.source` on registered tools and commands (sanitized to package spec or basename only). Pure event-listener extensions that register neither tools nor commands (e.g. `atuin.ts`, `herdr-agent-state.ts`) are not enumerable via Pi's `ExtensionAPI`.
- `exportUsageEvent()` in `extensions/usage-insights/schema.ts` is the single sink seam where a future OTLP/HTTP collector exporter attaches.

### Reporting CLI
```bash
pi-usage-report              # Full local summary + Atuin author=pi count
pi-usage-report --days 7     # Last 7 days
pi-usage-report --json       # Machine-readable JSON
```

---

## To Go Org-Wide Checklist

- [ ] **Lift team package to its own git repository**: Move `config/pi/.local/share/pi-team-package/` verbatim to `github.com/<org>/pi-team-package`, tag `v0.1.0`, and change `"~/.local/share/pi-team-package"` in `settings.template.json` to `"git:github.com/<org>/pi-team-package@v0.1.0"`.
- [ ] **Publish the custom org Gondolin guest image (`gondolin-image/build-config.json`)**: Add org language toolchains (Java/Gradle, Go, etc.), `kubeconform`, and internal CA certs, and distribute the built image via an internal artifact registry instead of building locally on each laptop.
- [ ] **Internal registries & git host in egress policy**: Add internal git servers, Artifactory/OCI registry mirrors, and `allowedInternalHosts` via `~/.config/sandbox.toml` (`[network]`).
- [ ] **Decide policy on host-side third-party extensions**: Review whether `pi-web-access` (bypasses Gondolin egress) and `@plannotator/pi-extension` (host `git`/`gh`) belong in the strict org baseline, or move to whole-process isolation (Docker Sandboxes / OpenShell) for repos with higher sensitivity.
- [ ] **Enforce subagent sandboxing**: Pin custom agent definitions in `pi-subagents` so no agent can set `extensions: []` and drop Gondolin; consider `runnerLaunchers` for OS-level containment of background subagents.
- [ ] **Wire OTLP/HTTP collector**: Implement an async batched OTLP/HTTP exporter inside `exportUsageEvent()` in `extensions/usage-insights/schema.ts` pointing at the internal software-factory OpenTelemetry Collector (with opt-out/offline buffering and schema version validation).
- [ ] **Enterprise Pi model routing & auth**: Configure corporate LLM proxy/gateway in `models.json` or an org provider extension (`pi.registerProvider`) so developers authenticate via SSO instead of personal API keys.
- [ ] **Renovate / Dependabot pin workflow**: Automate PRs against `pi-pin.json` with a 7-day release-age cooldown and mandatory source review for third-party Pi extensions before bumping pins.
- [ ] **Workstation provisioning (WSL2 / macOS)**: Add `usermod -aG kvm` (and optional `qemu-utils`) to the org WSL2 image/setup script; on Apple Silicon Macs, Gondolin's `krun` backend works out of the box with no extra hypervisor config.
- [ ] **Audit `pi-unsafe` usage**: Alert/review `sandbox.escapeHatchUsed: true` trends in the software-factory dashboard to identify workflow gaps that force engineers out of the sandbox.
