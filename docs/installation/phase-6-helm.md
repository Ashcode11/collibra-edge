# Phase 6 — Helm and the payments-api Microservice

**Status:** ✅ Deployed via Helm, `helm test` passing, upgrade → failed release → rollback demonstrated.

## Helm in one minute
| Term | Meaning | Here |
|---|---|---|
| **Chart** | Package of templated Kubernetes manifests | `helm/payments-api/` |
| **Values** | Inputs to the templates. Layered: `values.yaml` ← `values-lab.yaml` ← `--set` | secure defaults + lab overrides |
| **Schema** | `values.schema.json` validates inputs *before* rendering | rejects `image.tag=latest`, bad `LOG_LEVEL` |
| **Release** | A named install of a chart in a namespace, versioned by **revision** | `payments-api` in `bank-apps` |
| **Rollback** | Re-applies an earlier revision as a *new* revision | rev 4 = "Rollback to 2" |

**Helm vs Kustomize (used in Phase 4):** Kustomize *patches* plain YAML; Helm *templates* it and tracks releases (history and rollback). **Helm vs Argo CD (Phase 7):** Helm renders and installs; Argo CD continuously makes the cluster match Git, and can use Helm to render.

## What was built
```
apps/payments-api/      FastAPI service · 15 unit tests (no DB needed) · Dockerfile
helm/payments-api/      Chart.yaml · values.yaml · values-lab.yaml · values.schema.json
  templates/            deployment · service · configmap · serviceaccount · hpa · pdb · ingress · NOTES · tests/
kubernetes/namespaces/bank-apps.yaml   PSA restricted + quota (created by platform, not by Helm)
```
- **Image** `cel/payments-api:0.1.0`: multi-stage, non-root (uid 10001), no `pip` at runtime, 189 MB. Trivy: **0 fixable HIGH/CRITICAL** (2 zlib CVEs fixed by `apt-get upgrade` in the build).
- **DB credential:** Terraform tag `k8s-extra-targets=bank-apps/payments-api-db` → `secrets-sync.sh` projects `bank_app` into this namespace (Secrets are namespaced).
- **URL:** `http://payments.lab.localhost:18000/api/v1/...` (Traefik ingress; only `/api` is exposed).

## Kubernetes features in the chart (and why)
| Feature | Setting | Why |
|---|---|---|
| Liveness `/healthz` | process only | A DB outage must *not* restart every pod |
| Readiness `/readyz` | checks the DB | Not ready → removed from the Service, no traffic |
| Startup probe | 60 s budget | Slow start isn't mistaken for a hang |
| Rolling update | `maxUnavailable: 0`, `maxSurge: 1` | Capacity never drops during a deploy |
| Config checksum annotation | `sha256` of the ConfigMap | Config change ⇒ automatic rolling restart |
| HPA | CPU 70 %, 2–4 pods; `replicas` omitted when enabled | Helm doesn't fight the autoscaler |
| PDB | `minAvailable: 1` | Node drains keep the service up |
| Security | non-root, read-only root FS, no capabilities, no SA token | Passes PSA `restricted` |
| `preStop: sleep 5` | — | Ingress stops routing before SIGTERM |
| ConfigMap vs Secret | config in ConfigMap; DB creds via `existingSecret` | Secrets never in values files or Git |

StatefulSets and PVCs were covered in Phase 4 (databases). This service is stateless by design.

## Commands
```bash
helm lint helm/payments-api -f helm/payments-api/values-lab.yaml
helm template payments-api helm/payments-api -f helm/payments-api/values-lab.yaml | less       # see rendered YAML
helm --kube-context k3d-cel-lab -n bank-apps upgrade --install payments-api helm/payments-api \
     -f helm/payments-api/values-lab.yaml --wait                                               # install/upgrade
helm --kube-context k3d-cel-lab -n bank-apps test payments-api
helm --kube-context k3d-cel-lab -n bank-apps history payments-api
helm --kube-context k3d-cel-lab -n bank-apps rollback payments-api <REVISION> --wait
curl http://payments.lab.localhost:18000/api/v1/payments/1
```
Rebuilding the image locally: `docker build -t cel/payments-api:0.1.0 apps/payments-api && k3d image import cel/payments-api:0.1.0 -c cel-lab` (Phase 8 replaces this with CI + a registry).

## Proven
| Check | Result |
|---|---|
| Unit tests | 15/15 |
| `helm lint`, schema rejects bad values, `--dry-run=server` | ✅ |
| `helm test` (pod calls `/readyz`) | Succeeded |
| API via ingress: GET, POST (201), invalid POST (422), `/metrics` not exposed (404) | ✅ |
| Rev 2 config change → pods rolled | ✅ |
| Rev 3 bad image → `ImagePullBackOff`, **API stayed HTTP 200** | ✅ |
| `helm rollback 2` → rev 4 deployed | ✅ |

## Troubleshooting
- **Pods stuck `ImagePullBackOff`:** wrong tag, or image not imported into k3d. Run `kubectl -n bank-apps describe pod`, then `helm rollback`.
- **`UPGRADE FAILED: context deadline exceeded`:** `--wait` timed out because pods never became ready. Check readiness (`/readyz` → DB credentials?).
- **Release stuck in `pending-upgrade`:** an interrupted upgrade. Run `helm history`, then `helm rollback` to the last `deployed` revision.
- **HPA `cpu: <unknown>`:** metrics-server has no samples yet, or the pods have no CPU *requests*.

## Interview
**Q: Liveness vs readiness: what goes wrong if liveness checks the database?** A DB blip makes every pod fail liveness, so Kubernetes restarts them all at once. That's a self-inflicted outage and a thundering herd on recovery. Liveness = "is this process wedged"; readiness = "can I serve right now".
**Q: How does Helm roll back, and what doesn't it roll back?** It re-applies the manifests of an earlier revision as a new revision. It does **not** undo database migrations, external resources, or data changes. Those need backward-compatible (expand/contract) migrations.

## Checkpoint
1. Why is `replicas` left out of the Deployment when the HPA is enabled?
2. Rev 3 failed, yet users saw no errors. Which two settings made that true?
