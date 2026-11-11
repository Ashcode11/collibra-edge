# Collibra Edge Enterprise Lab

A local, enterprise-style lab that shows how a large bank could architect, secure and operate **Collibra Edge** across hybrid infrastructure. It uses Kubernetes, Floci cloud emulators, Terraform, Helm, GitHub Actions, Argo CD and an observability stack.

> **Lab mode: Option B (local only).** The workstation (Apple M2, 8 GB RAM) can't meet Collibra Edge's official requirements (x86_64, 16 cores, 64 GB, RHEL). So Collibra Edge itself and its tenant-side steps are **documented and labelled CONCEPTUAL**. Everything around Edge is built for real. See [docs/phase-1-environment-assessment.md](docs/phase-1-environment-assessment.md).

## Real vs emulated vs conceptual

| Component | Status |
|---|---|
| k3d/k3s cluster, Helm releases, PostgreSQL/MySQL, Argo CD, Prometheus/Grafana/Loki/OTel | **Real** (local) |
| AWS (S3, SQS, Secrets Manager, KMS) and Azure (Blob, Queue, Key Vault) | **Emulated** by Floci |
| GitHub Actions, GHCR | **Real** (GitHub) |
| Collibra Edge site, capabilities, JDBC ingestion, profiling, classification, lineage | **Conceptual** |

## Layout

| Path | Contents |
|---|---|
| `docs/` | Phase write-ups, architecture, security, troubleshooting, interview prep. [Progress log](docs/PROGRESS-LOG.md) |
| `infrastructure/terraform/` | Reusable modules + per-environment roots targeting Floci |
| `infrastructure/floci/` | Floci endpoint notes and smoke tests |
| `kubernetes/cluster/` | k3d cluster definition |
| `kubernetes/` | Namespaces, policies, app and monitoring manifests |
| `helm/` | Lab Helm charts (never Collibra's Edge chart) |
| `database/` | Schemas and synthetic data generators (no real customer data) |
| `cicd/github-actions/`, `gitops/argocd/` | CI pipeline and GitOps definitions |
| `observability/` | Dashboards, alert rules, OTel config |
| `scripts/` | Helper scripts (`lab-up.sh`, `lab-status.sh`, …) |

## Quick start
```bash
scripts/lab-status.sh      # what is running
scripts/lab-up.sh          # create/start the k3d lab cluster
```

## Safety rules
- Every kubectl/helm command uses `--context k3d-cel-lab`. Never the real `<real-aks-context>`.
- Terraform uses Floci endpoints and dummy credentials only. Real `~/.aws` credentials are never used.
- No secrets in Git (see `.gitignore`). All ports bind to `127.0.0.1`.
