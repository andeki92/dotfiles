# Global Agent Instructions

## Build and test conventions
- Read existing repo docs (`README.md`, `AGENTS.md`, `Taskfile.yml`, `Makefile`) and follow the repository's own toolchain, formatting, and test commands before editing.
- Keep changes minimal, scoped to the request, and verified by running the relevant unit tests and linters before finishing.
- Never hardcode personal usernames, absolute home paths, or machine-local state in tracked files.
- Never commit secrets, tokens, kubeconfigs, or cloud credentials.

## Kubernetes and GitOps rule (Argo CD + kustomize)
- **Never run `kubectl apply`, `kubectl patch`, `kubectl edit`, `kubectl delete`, or Helm mutating commands against any cluster.**
- All cluster and workload changes go strictly through GitOps:
  1. Edit the appropriate kustomize base or environment overlay (`overlays/<env>/...`).
  2. Validate manifests locally (for example `kustomize build overlays/<env>` or `kubectl kustomize`) without touching live cluster credentials.
  3. Open a pull request so Argo CD reconciles the merged change.

## Sandbox awareness
- Default Pi sessions route built-in file and shell tools into a Gondolin micro-VM where only the current project directory is mounted.
- Host credentials (`~/.kube`, `~/.oci`, `~/.ssh`) and non-allowlisted network hosts are intentionally unavailable inside the sandbox. Do not attempt to bypass sandbox boundaries.
