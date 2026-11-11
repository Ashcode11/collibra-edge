#!/usr/bin/env bash
# Sync database credentials FROM Floci Secrets Manager (source of truth)
# INTO Kubernetes Secrets. Discovery is data-driven: every secret tagged
#   k8s-namespace=<ns>  and  k8s-secret=<name>
# is copied to <ns>/<name> with keys "username" and "password"; optional
#   k8s-extra-targets="<ns>/<name> <ns2>/<name2>"
# projects the same credential into other namespaces (Secrets are namespaced).
#
# Safety:
#  - values stream through stdin; never on argv, never written to disk
#  - server-side apply: unlike client-side `kubectl apply`, it does NOT copy
#    the secret into a last-applied-configuration annotation
#  - prints names and versions only, never values
# In production this job belongs to the External Secrets Operator (or CSI
# Secrets Store driver); this script shows exactly what such a controller does.
set -euo pipefail
CTX=k3d-cel-lab
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_REGION=eu-west-2
unset AWS_PROFILE
aws_() { aws --endpoint-url="${FLOCI_AWS_ENDPOINT:-http://localhost:4566}" --output json "$@"; }

# One output line per target: primary (k8s-namespace/k8s-secret) plus any
# space-separated "namespace/secret" pairs in the k8s-extra-targets tag.
list=$(aws_ secretsmanager list-secrets --filters Key=tag-key,Values=k8s-secret |
  jq -r '.SecretList[] | (.Tags|from_entries) as $t
         | ([($t["k8s-namespace"] + "/" + $t["k8s-secret"])] + (($t["k8s-extra-targets"] // "") | split(" ") | map(select(. != ""))))[]
         as $target | [.Name, ($target|split("/")[0]), ($target|split("/")[1])] | @tsv')
[ -n "$list" ] || { echo "no tagged secrets found in Secrets Manager"; exit 1; }

count=0
while IFS=$'\t' read -r name ns k8s; do
  resp=$(aws_ secretsmanager get-secret-value --secret-id "$name")
  version=$(jq -r .VersionId <<<"$resp")
  jq -r '.SecretString | fromjson | "username=\(.username)\npassword=\(.password)"' <<<"$resp" |
    kubectl --context="$CTX" -n "$ns" create secret generic "$k8s" --from-env-file=/dev/stdin --dry-run=client -o yaml |
    kubectl --context="$CTX" label --local -f - -o yaml \
      lab.cel/source=floci-secretsmanager app.kubernetes.io/part-of=bank-data |
    kubectl --context="$CTX" annotate --local -f - -o yaml \
      "lab.cel/secretsmanager-name=$name" "lab.cel/secretsmanager-version=$version" |
    kubectl --context="$CTX" apply --server-side --field-manager=secrets-sync --force-conflicts -f - >/dev/null
  printf '  synced  %-34s -> %s/%s (version %s)\n' "$name" "$ns" "$k8s" "$version"
  count=$((count+1))
done <<<"$list"
echo "synced $count secret(s)"
