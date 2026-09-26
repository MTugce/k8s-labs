# Workstream Status

## Identity

- Workstream ID: k8s-context-kubeconfig-lab
- Phase: content-migration
- Agent/session: Codex `/root`
- Repository: `k8s-labs`
- Branch or worktree: `k8s-feature`

## Ownership

- Owned paths: `beginner/lab-01-cluster-kubectl-namespace-labels/README.md`, `beginner/README.md`, the B1 row in `README.md`, `.agents/status/k8s-context-kubeconfig-lab.md`
- Explicitly excluded paths: all starter manifests, other lab guides, Kind configuration, and other repositories
- Shared files requiring integration-agent handoff: none; the user explicitly assigned the feature branch and B1 indexes

## Dependencies

- Requires: the root README Kind setup and an existing `k8s-labs` cluster
- Blocks: none

## State

`review-ready`

## Objective and acceptance criteria

- Objective: Extend Beginner Lab 1 with Kind cluster lifecycle, kubeconfig structure, multi-cluster context switching, and safe kubeconfig recovery.
- Acceptance criteria: A reader can create and remove a temporary Kind cluster, switch safely between it and `k8s-labs`, explain cluster/user/context relationships, recover a host-usable kubeconfig, inspect the control-plane copy, and continue the existing namespace and label exercises on the correct cluster.

## Changes

- Files changed: B1 learner guide, Beginner index, root B1 summary, and this status record
- Decisions made: extend B1 instead of adding a dependent lab; use a temporary single-node `k8s-test` cluster without the shared port mappings; never delete the primary `k8s-labs` cluster during the exercise

## Verification

- Commands: README Bash block extraction with `bash -n`, targeted cluster-delete scan, local Markdown link check, Kind/kubectl help checks, `git diff --check`
- Results: all static documentation, command availability, link, and scope checks passed
- Evidence: B1 contains exactly one `kind delete cluster` command and it targets only `k8s-test`; no primary-cluster delete command exists in the lab

## Handoff

- Integration notes: the full root Kind installation and setup sections remain unchanged; B1 keeps `k8s-test` alive until final cleanup and returns to `kind-k8s-labs` before workload exercises
- Residual risks: live cluster creation requires a functioning Docker daemon; current environment cannot access its Docker socket without external approval
- Follow-up work: none currently
