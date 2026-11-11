#!/usr/bin/env bash
# Create database credentials as Kubernetes Secrets in namespace "data".
#
# - Passwords are generated locally with openssl and sent straight to the API
#   server; they are never written to disk, echoed, or committed to Git.
# - Idempotent: an existing Secret is left untouched (so running this twice
#   does not silently rotate passwords out from under a running database).
# - Phase 5 moves the source of truth to Floci Secrets Manager / Key Vault.
set -euo pipefail
CTX=k3d-cel-lab
NS=data
k() { kubectl --context="$CTX" -n "$NS" "$@"; }
pw() { openssl rand -base64 33 | tr -d '/+=' | cut -c1-32; }

make_secret() {   # name, then key=value pairs (values may be "@gen" for a random password)
  local name="$1"; shift
  if k get secret "$name" >/dev/null 2>&1; then
    echo "  exists   secret/$name (unchanged)"; return
  fi
  local args=()
  for kv in "$@"; do
    local key="${kv%%=*}" val="${kv#*=}"
    [ "$val" = "@gen" ] && val="$(pw)"
    args+=(--from-literal="$key=$val")
  done
  k create secret generic "$name" "${args[@]}" >/dev/null
  k label secret "$name" app.kubernetes.io/part-of=bank-data lab.cel/managed-by=create-db-secrets >/dev/null
  echo "  created  secret/$name"
}

echo ">> PostgreSQL (bank_core)"
make_secret pg-admin            username=postgres        password=@gen
make_secret pg-migrator         username=bank_migrator   password=@gen
make_secret pg-app              username=bank_app        password=@gen
make_secret pg-collibra-ingest  username=collibra_ingest password=@gen
make_secret pg-collibra-profile username=collibra_profile password=@gen

echo ">> MySQL (crm)"
make_secret mysql-admin            username=root            password=@gen
make_secret mysql-crm-app          username=crm_app         password=@gen
make_secret mysql-collibra-ingest  username=collibra_ingest password=@gen
