#!/usr/bin/env bash
# Safe Terraform wrapper for the lab.
#   scripts/tf.sh <env> <terraform args...>      e.g. scripts/tf.sh lab plan
#
# Guarantees:
#  - Only Floci's documented dummy credentials are visible to Terraform.
#    ~/.aws config/credentials and AWS_PROFILE are hidden, so a real AWS
#    identity can never be picked up by accident.
#  - plan/apply/destroy/import/console automatically get <env>.tfvars.
#  - One shared provider cache for all stacks (saves disk and download time).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ENV="${1:?usage: tf.sh <env> <terraform args...>}"; shift
DIR="$REPO/infrastructure/terraform/envs/$ENV"
[ -d "$DIR" ] || { echo "unknown env: $ENV" >&2; exit 2; }

unset AWS_PROFILE AWS_SESSION_TOKEN AWS_DEFAULT_PROFILE
# Global endpoint override: ANY service not listed in the provider endpoints
# block falls back to Floci instead of real AWS (defence in depth).
export AWS_ENDPOINT_URL="${FLOCI_AWS_ENDPOINT:-http://localhost:4566}"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_REGION=eu-west-2
export TF_PLUGIN_CACHE_DIR="$REPO/.cache/terraform-plugins"
export TF_IN_AUTOMATION=1
mkdir -p "$TF_PLUGIN_CACHE_DIR"

cd "$DIR"
cmd="${1:-}"; shift || true
extra=()
case "$cmd" in
  plan|destroy|import|console|refresh)
    [ -f "$ENV.tfvars" ] && extra+=("-var-file=$ENV.tfvars") ;;
  apply)
    # A saved plan already contains its variables; -var-file is then forbidden.
    last="${*: -1}"
    if [ -z "$last" ] || [ ! -f "$last" ] || [[ "$last" == -* ]]; then
      [ -f "$ENV.tfvars" ] && extra+=("-var-file=$ENV.tfvars")
    fi ;;
  init)
    [ -f "backend.hcl" ] && extra+=("-backend-config=backend.hcl") ;;
esac
# Flags must come before positional arguments, so insert them right after the subcommand.
exec terraform "$cmd" ${extra[@]+"${extra[@]}"} "$@"
