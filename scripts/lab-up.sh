#!/usr/bin/env bash
# Create (first run) or start (later runs) the k3d "cel-lab" cluster.
# Idempotent: safe to run repeatedly. Never touches other clusters or contexts.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER=cel-lab
CTX="k3d-${CLUSTER}"

if k3d cluster list -o json | jq -e --arg n "$CLUSTER" '.[] | select(.name==$n)' >/dev/null; then
  echo ">> Cluster ${CLUSTER} exists - starting it"
  k3d cluster start "$CLUSTER"
else
  echo ">> Creating cluster ${CLUSTER}"
  k3d cluster create \
    --config "${REPO}/kubernetes/cluster/k3d-cel-lab.yaml" \
    --volume "${REPO}/kubernetes/cluster/audit-policy.yaml:/var/lib/rancher/k3s/server/audit-policy.yaml@server:*"
fi

echo ">> Waiting for nodes to be Ready"
kubectl --context "$CTX" wait --for=condition=Ready nodes --all --timeout=180s
echo ">> Waiting for system pods"
kubectl --context "$CTX" -n kube-system wait --for=condition=Available deploy --all --timeout=240s
kubectl --context "$CTX" get nodes -o wide
