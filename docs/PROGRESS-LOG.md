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
| 2026-11-11 | Two Terraform stacks: `bootstrap` (local state) creates the state bucket; `lab` uses S3 backend + `use_lockfile` | Standard chicken-and-egg pattern. S3-native locking replaces DynamoDB |
| 2026-11-11 | DB passwords via ephemeral `random_password` + write-only `secret_string_wo` | Passwords never in state/plan (verified) |
| 2026-11-11 | Secrets Manager = source of truth for 6 service credentials. `postgres`/`root` stay break-glass outside Terraform | Rotating superusers needs the old password. PAM vault in production |
| 2026-11-11 | AWS endpoint `http://localhost:4566` + global `AWS_ENDPOINT_URL` in `tf.sh` | S3 Control needs a hostname. Unlisted services must never reach real AWS |
| 2026-11-11 | GitHub repo `Ashcode11/collibra-edge` (public) is `origin`. History rewritten (author `Ashcode11 <ashwanitiwari.biz@gmail.com>`, personal/environment names redacted), then pushed | Public repo: no personal details. Local backup branch `backup/pre-redaction` keeps the original |
| 2026-11-11 | Azure Terraform not applied | azurerm needs TLS on floci-az + cert trust + vault DNS. Awaiting user decision |

## Phase status
| Phase | Status | Date | Output |
|---|---|---|---|
| 1 — Environment assessment | ✅ Done | 2026-11-11 | [phase-1-environment-assessment.md](phase-1-environment-assessment.md) |
| 2 — Collibra Edge research | ✅ Done | 2026-11-11 | [phase-2-collibra-edge-research.md](phase-2-collibra-edge-research.md) |
| 3 — Local platform setup | ✅ Done | 2026-11-11 | [installation/phase-3-local-platform-setup.md](installation/phase-3-local-platform-setup.md) |
| 4 — Synthetic bank data + databases | ✅ Done | 2026-11-11 | [installation/phase-4-data-tier.md](installation/phase-4-data-tier.md) |
| 5 — Terraform + Floci (secrets, storage, queues) | ✅ Done (AWS). Azure pending decision | 2026-11-11 | [installation/phase-5-terraform-floci.md](installation/phase-5-terraform-floci.md) |
| 6 — Helm + payments-api | ✅ Done | 2026-11-11 | [installation/phase-6-helm.md](installation/phase-6-helm.md) |
| 7–8 — GitHub Actions CI + Argo CD | ⏸ Next. Needs push access to GitHub repo | — | — |

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
| 2026-11-11 | Floci AWS: 64 Terraform-managed resources (3 KMS keys, 4 buckets, 4 queues, 6 secrets, 8 SSM params, IAM role/policy, log group). Lab state in `s3://cel-lab-euw2-tfstate` | `scripts/tf.sh lab destroy` then `bootstrap destroy` (needs approval) |
| 2026-11-11 | DB service passwords rotated from Secrets Manager (`collibra_ingest` rotated twice) | Re-run `create-db-secrets.sh` after deleting Secrets (not recommended) |
| 2026-11-11 | Namespace `bank-apps` (+quota), Helm release `payments-api` (rev 5), image `cel/payments-api:0.1.0` imported into k3d | `helm uninstall payments-api -n bank-apps` |
| 2026-11-11 | Repo-local provider cache `.cache/terraform-plugins` (~750 MB, gitignored) | `rm -rf .cache` |

## Blockers and unresolved dependencies
| # | Blocker | Owner | Impact |
|---|---|---|---|
| B1 | No Collibra tenant (Option B) | — | Edge site, capabilities, ingestion stay conceptual |
| B3 | `gh` CLI not logged in (git push works via keychain) | User | Needed for Actions/PR commands in Phase 8 |
| B4 | Disk 19 GB free (96%) after DB images | User | Watch it. Keep ≥10 GB free |
| B5 | PostgreSQL not confirmed in Collibra docs for Catalog JDBC ingestion/profiling/classification (lineage is documented) | Collibra | Documented as an open question |
| B6 | Floci Azure state is in-memory | — | Re-apply Azure Terraform after a Floci restart |
| B7 | Azure Terraform needs `FLOCI_AZ_TLS_ENABLED=true` on floci-az (your `~/floci` compose) + cert trust | User | Azure IaC not applied. Contained-container option proposed |
| B8 | Floci doesn't evaluate IAM/bucket policies | — | Least-privilege verified by policy inspection, not by deny tests |
| ~~B2~~ | ~~Phase 3 approvals~~ | — | Resolved 2026-11-11 |
