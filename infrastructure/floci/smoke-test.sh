#!/usr/bin/env bash
# Floci capability smoke test: proves each emulated service actually works
# (create -> read -> delete) before the lab relies on it.
#
# SAFETY: credentials are Floci's documented dummy values, passed as env vars
# for this process only. AWS_PROFILE/config files are disabled so real ~/.aws
# credentials can never be picked up, and every call has an explicit endpoint.
set -uo pipefail

export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-2
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
unset AWS_PROFILE AWS_SESSION_TOKEN
AWS="aws --endpoint-url=${FLOCI_AWS:-http://127.0.0.1:4566} --output json"
AZ_BASE="${FLOCI_AZ:-http://127.0.0.1:4577}"
# Azurite/Floci well-known PUBLIC development key (not a secret)
AZ_CONN="DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=${AZ_BASE}/devstoreaccount1;QueueEndpoint=${AZ_BASE}/devstoreaccount1-queue;"
P=cel-smoke-$$
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
ko(){ echo "  FAIL  $1  ($2)"; fail=$((fail+1)); }
chk(){ local name="$1"; shift; local out; if out=$("$@" 2>&1); then ok "$name"; else ko "$name" "$(echo "$out" | tail -1 | cut -c1-120)"; fi; }

echo "== AWS (Floci) =="
chk "S3 create bucket"        $AWS s3api create-bucket --bucket "$P" --create-bucket-configuration LocationConstraint=eu-west-2
echo "synthetic" > "/tmp/$P.txt"
chk "S3 put object (SSE)"     $AWS s3api put-object --bucket "$P" --key t.txt --body "/tmp/$P.txt" --server-side-encryption AES256
chk "S3 get object"           $AWS s3api get-object --bucket "$P" --key t.txt "/tmp/$P.out"
chk "S3 versioning"           $AWS s3api put-bucket-versioning --bucket "$P" --versioning-configuration Status=Enabled
Q=$($AWS sqs create-queue --queue-name "$P" 2>/dev/null | jq -r .QueueUrl)
[ -n "$Q" ] && [ "$Q" != null ] && ok "SQS create queue" || ko "SQS create queue" "no url"
chk "SQS send message"        $AWS sqs send-message --queue-url "$Q" --message-body '{"event":"ingestion-finished"}'
M=$($AWS sqs receive-message --queue-url "$Q" 2>/dev/null | jq -r '.Messages[0].Body')
[ "$M" = '{"event":"ingestion-finished"}' ] && ok "SQS receive message" || ko "SQS receive message" "got: $M"
KEY=$($AWS kms create-key --description "$P" 2>/dev/null | jq -r .KeyMetadata.KeyId)
[ -n "$KEY" ] && [ "$KEY" != null ] && ok "KMS create key" || ko "KMS create key" "no id"
chk "KMS encrypt"             $AWS kms encrypt --key-id "$KEY" --plaintext "$(printf hello | base64)"
# Secret in the exact JSON shape a Collibra Edge AWS Secrets Manager vault would read (Field = /password)
chk "SecretsManager create"   $AWS secretsmanager create-secret --name "$P/bank-core/collibra_ingest" --kms-key-id "$KEY" --secret-string '{"username":"collibra_ingest","password":"smoke-only"}'
S=$($AWS secretsmanager get-secret-value --secret-id "$P/bank-core/collibra_ingest" 2>/dev/null | jq -r .SecretString | jq -r .username)
[ "$S" = collibra_ingest ] && ok "SecretsManager get (JSON field)" || ko "SecretsManager get" "got: $S"
chk "SecretsManager rotate value" $AWS secretsmanager put-secret-value --secret-id "$P/bank-core/collibra_ingest" --secret-string '{"username":"collibra_ingest","password":"rotated"}'
chk "SSM put parameter"       $AWS ssm put-parameter --name "/$P/db/host" --value bank-core-pg --type String
chk "CloudWatch Logs group"   $AWS logs create-log-group --log-group-name "/$P/app"
chk "IAM create role"         $AWS iam create-role --role-name "$P" --assume-role-policy-document '{"Version":"2012-10-17","Statement":[]}'
chk "RDS API (describe)"      $AWS rds describe-db-instances
chk "EKS API (list)"          $AWS eks list-clusters

echo "== Azure (Floci AZ) =="
chk "Blob create container"   az storage container create -n "$P" --connection-string "$AZ_CONN" --only-show-errors
chk "Blob upload"             az storage blob upload -c "$P" -n t.txt -f "/tmp/$P.txt" --connection-string "$AZ_CONN" --only-show-errors --overwrite
chk "Blob list"               az storage blob list -c "$P" --connection-string "$AZ_CONN" --only-show-errors
chk "Queue create"            az storage queue create -n "$P" --connection-string "$AZ_CONN" --only-show-errors
chk "Queue put message"       az storage message put -q "$P" --content ingestion-finished --connection-string "$AZ_CONN" --only-show-errors
KV="${AZ_BASE}/devstoreaccount1-keyvault"
code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$KV/secrets/$P-pg?api-version=7.4" -H 'Authorization: Bearer floci' -H 'Content-Type: application/json' -d '{"value":"smoke-only","contentType":"text/plain"}')
[ "$code" = 200 ] && ok "Key Vault set secret" || ko "Key Vault set secret" "HTTP $code"
v=$(curl -s "$KV/secrets/$P-pg?api-version=7.4" -H 'Authorization: Bearer floci' | jq -r .value)
[ "$v" = smoke-only ] && ok "Key Vault get secret" || ko "Key Vault get secret" "got: $v"

echo "== Cleanup (only resources created by this run: $P) =="
$AWS s3 rb "s3://$P" --force >/dev/null 2>&1
$AWS sqs delete-queue --queue-url "$Q" >/dev/null 2>&1
$AWS secretsmanager delete-secret --secret-id "$P/bank-core/collibra_ingest" --force-delete-without-recovery >/dev/null 2>&1
$AWS kms schedule-key-deletion --key-id "$KEY" --pending-window-in-days 7 >/dev/null 2>&1
$AWS ssm delete-parameter --name "/$P/db/host" >/dev/null 2>&1
$AWS logs delete-log-group --log-group-name "/$P/app" >/dev/null 2>&1
$AWS iam delete-role --role-name "$P" >/dev/null 2>&1
az storage container delete -n "$P" --connection-string "$AZ_CONN" --only-show-errors >/dev/null 2>&1
az storage queue delete -n "$P" --connection-string "$AZ_CONN" --only-show-errors >/dev/null 2>&1
curl -s -o /dev/null -X DELETE "$KV/secrets/$P-pg?api-version=7.4" -H 'Authorization: Bearer floci'
rm -f "/tmp/$P.txt" "/tmp/$P.out"
echo; echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
