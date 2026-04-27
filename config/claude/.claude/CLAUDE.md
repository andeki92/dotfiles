# Sandboxed environments (cbox)

You may be running inside `cbox`, a Podman/apple-container sandbox harness.
When you are:

- Network egress is restricted to an explicit allow-list enforced by a host-side
  Squid proxy (your `HTTPS_PROXY` env var). Default-allowed: Anthropic API,
  GitHub, GitLab. **Package registries (crates.io, pypi.org, registry.npmjs.org,
  proxy.golang.org) are NOT allowed by default** — each project must opt in via
  its own `~/.config/cbox/allowlist.d/<repo>.txt` on the host.
- If a tool like `cargo add`, `pip install`, `npm install`, or `go get` fails
  with a network error, the registry isn't whitelisted. Don't retry. Don't try
  alternative mirrors. Tell the user which registry you need; they'll add it
  to the allow-list and the next session picks it up.
- The filesystem outside `/workspace` and the writable cache mounts is invisible
  to you. Don't try to read `~/.ssh/`, `~/.aws/`, `~/.gnupg/` — they're not there.
- `git push` works; ssh-agent and gpg-agent are forwarded over sockets, so you
  can sign commits without seeing the keys. Push only to branches the user
  expects (typically `cbox/<slug>-<id>`); never to `main` or other long-lived
  branches.
- The container is ephemeral. Anything you `apt install` or write outside
  `/workspace` evaporates when the session ends. Persist work as commits + a PR.
