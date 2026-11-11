# Lab Guide: How to Use the Collibra Edge Enterprise Lab, End to End

This guide explains **what the lab represents**, **how a request flows through it**, and **how to drive it yourself**. Every command here has been run and works.

---

## 1. The story the lab tells

> A bank (think SMBC-style: retail + corporate, UK entity) has customer, account, payment and transaction data spread across systems owned by different teams. Regulators expect it to know **where personal data lives, who can access it, and how reports are derived**. The data governance team uses **Collibra** (SaaS) to build that inventory. Because the data must never leave the bank's network, Collibra reaches it through **Collibra Edge**, a component the bank runs *inside* its own infrastructure.

The lab rebuilds everything **around** Edge for real, and documents Edge itself (Option B: the laptop can't run it).

## 2. The big picture

```
 ┌───────────────────────────── YOUR MAC ──────────────────────────────────────────────┐
 │                                                                                      │
 │  ① DATA SOURCES (real)              ② SECRETS & CLOUD (emulated)                      │
 │  k3d cluster "cel-lab", ns data     Floci AWS :4566  (Terraform-managed)              │
 │  ┌──────────────────────────┐       ┌─────────────────────────────────┐              │
 │  │ PostgreSQL  bank_core    │◄──────│ Secrets Manager cel/lab/...     │ source of    │
 │  │  customers, accounts,    │ sync  │ KMS keys · S3 buckets · SQS     │ truth for    │
 │  │  payments, transactions  │       │ IAM role for Edge (IRSA-style)  │ passwords    │
 │  │ MySQL  crm (PII copies)  │       └─────────────────────────────────┘              │
 │  └──────────▲───────────────┘                                                        │
 │             │ JDBC as collibra_ingest (metadata only) / collibra_profile (rows)      │
 │  ┌──────────┴───────────────┐                                                        │
 │  │ ③ COLLIBRA EDGE          │  CONCEPTUAL here. Needs x86_64 RHEL, 16 cores, 64 GB    │
 │  │  capabilities run as     │  In a bank: dedicated VM (bundled k3s) or EKS/AKS       │
 │  │  jobs inside the bank    │                                                         │
 │  └──────────┬───────────────┘                                                         │
 │             │ outbound HTTPS 443 only, metadata (not data)                            │
 └─────────────┼────────────────────────────────────────────────────────────────────────┘
               ▼
 ④ COLLIBRA PLATFORM (SaaS tenant, conceptual): Data Catalog → schemas, tables,
    columns, PII classifications, lineage, owners, policies
```

Alongside sits the **platform engineering** that keeps this running: Terraform (cloud resources), Kubernetes + Helm (workloads), and, in later phases, GitHub Actions + Argo CD (delivery), Prometheus/Grafana/Loki/OpenTelemetry (operations), and fault injection (resilience).

## 3. The end-to-end flow, step by step

| # | What happens in a real bank | What plays that role in the lab | Status |
|---|---|---|---|
| 1 | Source systems hold customer/payment data | `bank_core` (PostgreSQL) + `crm` (MySQL), ~270k synthetic rows | **Real** |
| 2 | DBAs create **least-privilege** accounts for governance tooling | `collibra_ingest` (metadata only), `collibra_profile` (read-only rows) | **Real** |
| 3 | Credentials go into the bank's **vault**, never into tickets or code | Terraform creates them in Secrets Manager (password never in state) | **Emulated** (Floci) |
| 4 | Edge is given **permission to read only its own secrets** | IAM role `cel-lab-collibra-edge-secrets` → exactly 3 secrets | **Emulated** |
| 5 | Platform team installs **Edge** inside the network, outbound 443 only | Documented in Phase 2 (installer, Edge CLI, statuses) | **Conceptual** |
| 6 | Data team creates a **JDBC connection** in Collibra that points at the vault: *Secret Name* `cel/lab/bank-core-pg/collibra_ingest`, *Field* `/password` | `scripts/tf.sh lab output collibra_edge_vault_references` prints exactly these values | **Conceptual** (values real) |
| 7 | They add the **Catalog JDBC ingestion** capability, register the database and **synchronise** schemas | You can *be* Edge: §5 exercise A shows exactly what that account can see | **Simulated by you** |
| 8 | Collibra shows schemas → tables → columns, with descriptions, in the **Data Catalog** | Column comments like `[PII-DIRECT] Given name.` are what would appear | **Conceptual** |
| 9 | **Profiling/classification** flags PII columns (names, NI numbers, IBANs) | `collibra_profile` can read rows. Comments tag PII/PCI | **Conceptual** |
| 10 | **Lineage** shows `customers + accounts + payments → v_aml_high_risk_payments` | Views in `reporting` schema. SQL published to the `lineage-sql` bucket | **Conceptual** (inputs real) |
| 11 | Security **rotates** the password. Nothing breaks | `password_version` bump → sync → DB re-keyed. Old password rejected | **Real** (proven) |

**The governance "aha":** the `crm` MySQL database holds *copies* of customer names, emails and dates of birth, linked to `bank_core` only by `customer_number`, with no foreign key. Nobody would find that without a catalog. That's the kind of thing Collibra is bought to expose.

## 4. Daily operations

```bash
cd ~/Documents/Collibra-Edge

scripts/lab-status.sh                 # what's running, RAM, Floci health (read-only)
scripts/lab-up.sh                     # start (or create) the k3d cluster
scripts/db-load.sh                    # (re)deploy databases + sync secrets + reload data (~1 min)

scripts/db-verify.sh                  # 28 checks: privileges, synthetic data, integrity, logs
scripts/tf-verify.sh                  # 15 checks: no secrets in state, controls, drift
infrastructure/floci/smoke-test.sh    # 24 checks: Floci AWS + Azure services
```

Free the laptop when you're done (data is kept on the cluster's volumes):
```bash
k3d cluster stop cel-lab
```
Bring your other projects back:
```bash
docker compose --project-directory <other-project-a-dir> start
docker compose --project-directory <other-project-b-dir> start
```
Floci keeps running on its own (`~/floci`). Its web UI is at http://127.0.0.1:4500.

## 5. Hands-on tour

### A. Be Collibra Edge: see exactly what ingestion would see
Edge connects over the network with `collibra_ingest`. Do the same:
```bash
kubectl --context=k3d-cel-lab -n data port-forward svc/bank-core-pg 15432:5432
```
In a second terminal:
```bash
export PGPASSWORD=$(kubectl --context=k3d-cel-lab -n data get secret pg-collibra-ingest -o jsonpath='{.data.password}' | base64 -d)
/opt/homebrew/opt/libpq/bin/psql -h 127.0.0.1 -p 15432 -U collibra_ingest -d bank_core
```
Then try:
```sql
\dt customer.*                                   -- tables: visible
\d+ customer.customers                           -- columns, types, [PII-…] descriptions: visible
SELECT first_name FROM customer.customers LIMIT 1;   -- ERROR: permission denied  ← by design
\q
```
That's least privilege per capability: **metadata ingestion never needs to read a customer's name.** (Profiling would use `collibra_profile`, which can.)

### B. Find the PII sprawl
```bash
kubectl --context=k3d-cel-lab -n data exec crm-mysql-0 -- bash -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot crm -e "SELECT column_name, column_comment FROM information_schema.columns WHERE table_schema=\"crm\" AND column_comment LIKE \"[PII%\""'
```
The same kinds of personal data as `bank_core`, in a different system, owned by a different team.

### C. Follow a credential from vault to database
```bash
scripts/tf.sh lab output collibra_edge_vault_references   # what you'd type into the Edge JDBC connection
kubectl --context=k3d-cel-lab -n data get secret pg-collibra-ingest -o jsonpath='{.metadata.annotations}' | jq   # which Secrets Manager version it came from
```

### D. Rotate a password (the full loop)
1. In `infrastructure/terraform/envs/lab/lab.tfvars`, bump a version, e.g. `"bank-core-pg/collibra_profile" = 2`.
2. Run:
```bash
scripts/tf.sh lab plan -out=tfplan && scripts/tf.sh lab apply tfplan
scripts/db-load.sh && scripts/db-verify.sh
```

### E. Look at the audit trail
```bash
docker exec k3d-cel-lab-server-0 sh -c 'tail -3 /var/log/kubernetes/audit.log' | jq -c '{user: .user.username, verb, resource: .objectRef.resource, name: .objectRef.name}'
kubectl --context=k3d-cel-lab -n data logs bank-core-pg-0 | grep 'connection authorized' | tail -3
```

## 6. Where everything lives

| Path | What |
|---|---|
| `docs/phase-*.md`, `docs/installation/` | One write-up per phase: why, how, troubleshooting, interview Q&A |
| `docs/PROGRESS-LOG.md` | Decisions, every change made to your machine (with undo), blockers |
| `database/` | Schemas, generators, Kubernetes manifests for the data tier |
| `infrastructure/terraform/` | Modules + `bootstrap` and `lab` stacks (Floci AWS) |
| `kubernetes/` | Cluster definition, namespaces |
| `apps/payments-api/` | Sample microservice (Phase 6) |
| `scripts/` | Everything you run |

## 7. What's built and what's next

| Phase | Status |
|---|---|
| 1–2 Assessment, Edge research | ✅ |
| 3 Cluster, tools, Floci | ✅ |
| 4 Bank data tier | ✅ |
| 5 Terraform + secrets | ✅ (Azure IaC pending your decision) |
| 6 Helm + `payments-api` | 🔄 service, tests, image done; chart next |
| 7–8 GitHub Actions CI + Argo CD GitOps | needs GitHub push access to `Ashcode11/collibra-edge` |
| 9 Security hardening (NetworkPolicies, TLS) | — |
| 10 Observability (Prometheus, Grafana, Loki, OTel) | — |
| 11 Fault injection (10 scenarios) | — |
| 12 Final demo script | — |
