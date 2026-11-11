# Project Progress Log

## Decisions
| Date | Decision | Reason |
|---|---|---|
| 2026-11-11 | **Option B — local only.** Collibra Edge is not deployed. Edge installation, site registration, capabilities and JDBC ingestion are documented and labelled **CONCEPTUAL** | The workstation can't meet Edge requirements (ARM64, 8 GB RAM, 19 GB free vs x86_64, 64 GB, ~255 GB). No cloud spend |
| 2026-11-11 | Cluster on **k3s v1.36.6** (not the cached 1.35) | kubectl 1.37 ±1 skew policy. Matches the newest Edge k3s line |
| 2026-11-11 | Terraform from `hashicorp/tap` (1.17.2) | Homebrew core is frozen at 1.5.7 (BSL licence change) |
| 2026-11-11 | tflint runs in CI, not locally | Removed from Homebrew core |
| 2026-11-11 | In-cluster Floci endpoint = `host.k3d.internal` | Floci binds 127.0.0.1 on the host. Verified from a pod |
| 2026-11-11 | Plain manifests + Kustomize for the data tier (not a third-party Helm chart) | Transparent for learning. Avoids Bitnami image licensing changes. Helm is taught in Phase 6 with our own chart |
| 2026-11-11 | Separate `collibra_ingest` (metadata-only) and `collibra_profile` (read-only rows) DB roles | Least privilege per Edge capability |
| 2026-11-11 | SQL-native seeded generators (no Faker/pip) | Zero extra dependencies. Byte-identical rebuilds (verified) |
| 2026-11-11 | SQL Server deferred | amd64-only image, ≥2 GB RAM. Not viable on this machine |

## Phase status
| Phase | Status | Date | Output |
|---|---|---|---|
| 1 — Environment assessment | ✅ Done | 2026-11-11 | [phase-1-environment-assessment.md](phase-1-environment-assessment.md) |
| 2 — Collibra Edge research | ✅ Done | 2026-11-11 | [phase-2-collibra-edge-research.md](phase-2-collibra-edge-research.md) |
| 3 — Local platform setup | ✅ Done | 2026-11-11 | [installation/phase-3-local-platform-setup.md](installation/phase-3-local-platform-setup.md) |
| 4 — Synthetic bank data + databases | ✅ Done | 2026-11-11 | [installation/phase-4-data-tier.md](installation/phase-4-data-tier.md) |
| 5 — Terraform + Floci (secrets, storage, queues) | ⏸ Next, awaiting go-ahead | — | — |

## Configuration changes made to the workstation
| Date | Change | Revert |
|---|---|---|
| 2026-11-11 | Pulled then removed `alpine` (amd64 test) | — |
| 2026-11-11 | Docker build cache + dangling images pruned (≈4 GB host disk) | Not reversible (cache only) |
| 2026-11-11 | Stopped `other-project-a-*` (13) and `other-project-b_*` (4) containers | `docker compose --project-directory <dir> start` |
| 2026-11-11 | Docker Desktop Kubernetes disabled. Docker Desktop restarted | Restore `settings.json.bak-2026-11-11` or tick it in Settings |
| 2026-11-11 | Homebrew: kubernetes-cli 1.29.2→1.37.2. Added gh, yq, trivy, argocd, libpq. Tapped `hashicorp/tap`. terraform 1.5.7→1.17.2 | `brew uninstall …` |
| 2026-11-11 | `git init` in project folder. First commit `bd523d6` (phases 1–3) | `rm -rf .git` |
| 2026-11-11 | k3d cluster `cel-lab` created. Context `k3d-cel-lab` added to `~/.kube/config` (current context **unchanged**) | `k3d cluster delete cel-lab` (needs approval) |
| 2026-11-11 | Pulled images `rancher/k3s:v1.36.6-k3s1`, `curlimages/curl:8.11.1` | `docker rmi` |
| 2026-11-11 | Namespace `data` (+quota, limits), Secrets `pg-*`/`mysql-*`, StatefulSets `bank-core-pg`, `crm-mysql`, 2 PVCs (2Gi each), load Jobs | `kubectl --context=k3d-cel-lab delete ns data` (needs approval; deletes data) |

## Blockers and unresolved dependencies
| # | Blocker | Owner | Impact |
|---|---|---|---|
| B1 | No Collibra tenant (Option B) | — | Edge site, capabilities, ingestion stay conceptual |
| B3 | GitHub repo for Actions/Argo CD not yet chosen | User | Blocks Phase 8 |
| B4 | Disk 19 GB free (96%) after DB images | User | Watch it. Keep ≥10 GB free |
| B5 | PostgreSQL not confirmed in Collibra docs for Catalog JDBC ingestion/profiling/classification (lineage is documented) | Collibra | Documented as an open question |
| B6 | Floci Azure state is in-memory | — | Re-apply Azure Terraform after a Floci restart |
| ~~B2~~ | ~~Phase 3 approvals~~ | — | Resolved 2026-11-11 |
