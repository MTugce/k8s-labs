# Workstream Status

## Identity

- Workstream ID: helm-chart-authoring-lab
- Phase: content-migration
- Agent/session: Codex `/root`
- Repository: `k8s-labs`
- Branch or worktree: `k8s-feature`

## Ownership

- Owned paths: `README.md`, `advanced/README.md`, `advanced/lab-04-*` through `advanced/lab-08-*`, `.agents/status/helm-chart-authoring-lab.md`
- Explicitly excluded paths: `beginner/`, `intermediate/`, `app/`, `kind-cluster.yaml`, all other repositories
- Shared files requiring integration-agent handoff: none; the user explicitly assigned the feature branch and indexes

## Dependencies

- Requires: the existing root Kind setup and each learner's public Docker Hub `devops-app-pub` image
- Blocks: none

## State

`review-ready`

## Objective and acceptance criteria

- Objective: Add an independent Advanced lab that teaches Helm theory and the complete authoring and release lifecycle for `devops-app`.
- Acceptance criteria: The learner creates the chart from scratch, renders and lints it, installs it on Kind from a public Docker Hub image, verifies it, upgrades and rolls it back, runs a Helm test, packages it, and uninstalls it without relying on another lab.

## Changes

- Files changed: root and Advanced indexes; new `advanced/lab-04-helm-chart-from-scratch/`; renumbered Advanced lab directories and their working-directory commands
- Decisions made: public Docker Hub image is the primary flow; application source is copied into the lab; a working reference chart is kept under `solution/`; existing Advanced labs are renumbered after the new A4 lab

## Verification

- Commands: `helm lint`, invalid values schema lint, `helm template`, `helm install --dry-run=client`, `helm package`, `helm show`, `kubeconform -strict`, README Bash syntax check, JSON parsing, local Markdown link check, stale-path scan, application-copy comparison, `git diff --check`
- Results: all static, render, schema, packaging, link, syntax, and path checks passed
- Evidence: 1 chart linted with 0 failures; invalid `replicaCount: 0` rejected; 4 rendered resources valid under strict kubeconform; package `devops-app-0.1.0.tgz` generated and inspected

## Handoff

- Integration notes: feature branch contains the complete index and path renumbering; do not merge to `main` until the requested external review finishes
- Residual risks: live Docker Hub push and Kind deployment require a user-owned public repository and credentials; the active environment did not provide either and its current kube context is not the lab Kind cluster
- Follow-up work: none currently
