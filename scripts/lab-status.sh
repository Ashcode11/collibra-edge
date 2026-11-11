#!/usr/bin/env bash
# Read-only status overview of the lab. Changes nothing.
set -uo pipefail
CTX=k3d-cel-lab

echo "== Disk (host) =="; df -h /System/Volumes/Data | tail -1
echo; echo "== Docker VM =="; docker info --format 'CPUs={{.NCPU}} Mem={{.MemTotal}}'
echo; echo "== Containers =="; docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo; echo "== Memory per container =="; docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}'

echo; echo "== Floci =="
printf 'AWS  :4566 ' ; curl -s -m3 http://127.0.0.1:4566/_floci/health | jq -r '"v\(.version) services=\(.services|length)"' 2>/dev/null || echo DOWN
printf 'Azure:4577 ' ; curl -s -m3 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4577/ || echo DOWN
printf 'GCP  :4588 ' ; curl -s -m3 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4588/ || echo DOWN

echo; echo "== Kubernetes (${CTX}) =="
if kubectl --context "$CTX" get nodes >/dev/null 2>&1; then
  kubectl --context "$CTX" get nodes
  kubectl --context "$CTX" top nodes 2>/dev/null || true
  echo; kubectl --context "$CTX" get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | sed 's/^/not-running: /'
else
  echo "cluster not running (scripts/lab-up.sh)"
fi
