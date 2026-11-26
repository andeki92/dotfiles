---
description: Review current workspace changes against GitOps (kustomize + Argo CD) and safety rules
---
Review the current changes in this repository:

1. Verify no imperative cluster commands (`kubectl apply/patch/delete`) were introduced into scripts, docs, or CI steps where GitOps should be used.
2. For any kustomize bases or overlays touched, check resource naming, namespace scoping, image tag pinning, and patch validity.
3. Check for hardcoded usernames, absolute home paths, or accidentally staged secrets/kubeconfigs/OCI configs.
4. Report concrete findings grouped by severity, or confirm the diff is clean.
