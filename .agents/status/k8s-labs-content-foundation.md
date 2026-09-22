# Workstream: k8s-labs-content-foundation

- Repository: `devops-practitioner-labs/k8s-labs`
- Branch: `agent/k8s-labs-content-foundation`
- Owned paths: repository root, `platform/`, `app/`, `labs/`, `slides/`, `docs/`, `cheat-sheets/`, `curriculum.yaml`
- Excluded paths: Azure student-platform repository and existing `kubernetes-labs` repository
- Dependency: existing Azure Edge Nginx/DNS routing remains unchanged
- State: ready to publish
- Validation: shell syntax, YAML parse, Markdown link/placeholder audit, Kind configuration inspection, Git whitespace check
- Handoff: the new repository contains an Azure-slot-compatible nine-lab curriculum, lesson-to-lab presentation notes, and a separate Kind/kubectl cheat sheet. No student infrastructure configuration is modified. Runtime deployment was deliberately not run during content authoring.
