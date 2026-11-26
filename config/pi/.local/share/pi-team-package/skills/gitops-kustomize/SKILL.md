---
name: gitops-kustomize
description: Use when modifying Kubernetes manifests, Argo CD applications, or kustomize bases and overlays.
---

# GitOps Kustomize Workflow

Follow these rules whenever changing Kubernetes resources:

1. **Never mutate clusters directly**: Do not run `kubectl apply`, `kubectl patch`, `kubectl edit`, `kubectl replace`, or `kubectl delete`.
2. **Edit declarative manifests**:
   - Shared changes belong in `base/`.
   - Environment-specific overrides (replicas, image tags, cluster annotations, ConfigMap patches) belong in `overlays/<env>/`.
3. **Validate offline**:
   - Render each modified overlay locally (`kustomize build overlays/<env>` or `kubectl kustomize overlays/<env>`).
   - Run schema/YAML linters (`yamllint`, `kubeconform`) when available in the repo.
4. **Ship via PR**: Summarize which overlays changed, the rendered resource diff, and any Argo CD sync wave or rollout considerations for the PR description.
