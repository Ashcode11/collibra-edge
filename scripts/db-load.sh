#!/usr/bin/env bash
# Deploy the data tier and (re)load schemas + synthetic data.
# Safe to re-run: StatefulSets/PVCs are kept, load Jobs are recreated,
# data is regenerated deterministically (same seed => same rows).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CTX=k3d-cel-lab
k() { kubectl --context="$CTX" "$@"; }

echo ">> Namespace, quota, limits"
k apply -f "$REPO/kubernetes/namespaces/data.yaml"

echo ">> Secrets"
"$REPO/scripts/create-db-secrets.sh"

echo ">> Recreate load Jobs (Jobs are immutable)"
k -n data delete job bank-core-pg-load crm-mysql-load --ignore-not-found --wait=true

echo ">> Apply data tier"
k apply -k "$REPO/database"

echo ">> Waiting for databases"
k -n data rollout status statefulset/bank-core-pg --timeout=300s
k -n data rollout status statefulset/crm-mysql --timeout=420s

# Wait until a Job is Complete OR Failed. `kubectl wait --for=condition=complete`
# alone would sit until its timeout on a Job that has already failed.
wait_job() {
  local job="$1" deadline=$((SECONDS + 600)) state
  while (( SECONDS < deadline )); do
    state=$(k -n data get job "$job" -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type}{" "}{end}')
    case " $state " in
      *" Complete "*) echo "  $job: Complete"; k -n data logs "job/$job" | tail -12; return 0 ;;
      *" Failed "*)   echo "  $job: FAILED"; k -n data logs "job/$job" --tail=25; return 1 ;;
    esac
    sleep 5
  done
  echo "  $job: timed out"; return 1
}

echo ">> Waiting for load Jobs"
rc=0
wait_job crm-mysql-load || rc=1
wait_job bank-core-pg-load || rc=1
exit $rc
