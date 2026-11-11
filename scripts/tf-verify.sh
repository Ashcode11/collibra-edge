#!/usr/bin/env bash
# Verify the Terraform "lab" stack against Floci. Read-only.
#  1. No database password is present in Terraform state
#  2. No drift: plan reports no changes
#  3. Resources really have the controls the code declares
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_REGION=eu-west-2
unset AWS_PROFILE
aws_() { aws --endpoint-url=http://localhost:4566 --output json "$@"; }
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass+1)); }
ko() { echo "  FAIL  $1  -> $2"; fail=$((fail+1)); }

echo "== 1. Secrets never stored in Terraform state"
STATE=$("$REPO/scripts/tf.sh" lab state pull)
[ -n "$STATE" ] && ok "remote state readable ($(printf %s "$STATE" | jq '.resources|length') resources)" || ko "remote state readable" "empty"
names=$(aws_ secretsmanager list-secrets --filters Key=name,Values=cel/lab/ | jq -r '.SecretList[].Name')
checked=0; leaks=0
for n in $names; do
  pw=$(aws_ secretsmanager get-secret-value --secret-id "$n" | jq -r '.SecretString | fromjson | .password')
  [ "${#pw}" -ge 32 ] || ko "$n has a 32+ char password" "length ${#pw}"
  checked=$((checked+1))
  grep -qF -- "$pw" <<<"$STATE" && { leaks=$((leaks+1)); ko "$n password absent from state" "FOUND IN STATE"; }
done
[ "$checked" -eq 6 ] && ok "checked all 6 credentials (not a vacuous pass)" || ko "checked all 6 credentials" "checked $checked"
[ "$leaks" -eq 0 ] && [ "$checked" -gt 0 ] && ok "0 of $checked passwords present in state"
wo=$(printf %s "$STATE" | jq -c '[.. | objects | select(has("secret_string_wo")) | .secret_string_wo] | unique')
[ "$wo" = "[null]" ] && ok "secret_string_wo recorded as null in state" || ko "secret_string_wo null in state" "$wo"

echo "== 2. Edge vault format"
s=$(aws_ secretsmanager get-secret-value --secret-id cel/lab/bank-core-pg/collibra_ingest | jq -c '.SecretString | fromjson | del(.password)')
[ "$s" = '{"dbname":"bank_core","engine":"postgres","host":"bank-core-pg.data.svc.cluster.local","port":5432,"username":"collibra_ingest"}' ] \
  && ok "JSON fields /username /password /host /port /dbname present" || ko "Edge JSON shape" "$s"
kms=$(aws_ secretsmanager describe-secret --secret-id cel/lab/bank-core-pg/collibra_ingest | jq -r .KmsKeyId)
[[ "$kms" == *":key/"* ]] && ok "secret encrypted with customer-managed KMS key" || ko "secret CMK" "$kms"

echo "== 3. Storage, queues, keys, IAM"
for b in landing lineage-sql metadata-exports; do
  enc=$(aws_ s3api get-bucket-encryption --bucket "cel-lab-euw2-$b" | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm')
  ver=$(aws_ s3api get-bucket-versioning --bucket "cel-lab-euw2-$b" | jq -r .Status)
  pab=$(aws_ s3api get-public-access-block --bucket "cel-lab-euw2-$b" | jq '[.PublicAccessBlockConfiguration[]] | all')
  [ "$enc/$ver/$pab" = "aws:kms/Enabled/true" ] && ok "bucket $b: SSE-KMS, versioned, public access blocked" || ko "bucket $b controls" "$enc/$ver/$pab"
done
n=$(aws_ s3api list-objects-v2 --bucket cel-lab-euw2-lineage-sql | jq '[.Contents[]?] | length')   # Floci omits KeyCount (fidelity gap); count Contents instead
[ "$n" = 2 ] && ok "lineage SQL files published (2)" || ko "lineage SQL files" "$n"
q=$(aws_ sqs get-queue-url --queue-name cel-lab-euw2-ingestion-events | jq -r .QueueUrl)
rp=$(aws_ sqs get-queue-attributes --queue-url "$q" --attribute-names RedrivePolicy | jq -r '.Attributes.RedrivePolicy | fromjson | .maxReceiveCount')
[ "$rp" = 5 ] && ok "ingestion-events redrives to DLQ after 5 receives" || ko "redrive policy" "$rp"
for a in cel-lab-secrets cel-lab-storage; do
  kid=$(aws_ kms describe-key --key-id "alias/$a" | jq -r .KeyMetadata.KeyId)
  rot=$(aws_ kms get-key-rotation-status --key-id "$kid" | jq -r .KeyRotationEnabled)
  [ "$rot" = true ] && ok "KMS alias/$a rotation enabled" || ko "KMS $a rotation" "$rot"
done
pol=$(aws_ iam list-attached-role-policies --role-name cel-lab-collibra-edge-secrets | jq -r '.AttachedPolicies[0].PolicyArn')
doc=$(aws_ iam get-policy-version --policy-arn "$pol" --version-id "$(aws_ iam get-policy --policy-arn "$pol" | jq -r .Policy.DefaultVersionId)" | jq -c '.PolicyVersion.Document | if type=="string" then fromjson else . end')
nres=$(jq '[.Statement[] | select(.Sid=="ReadNamedSecretsOnly") | .Resource] | flatten | length' <<<"$doc")
wild=$(jq '[.Statement[].Resource] | flatten | map(select(test("\\*$"))) | length' <<<"$doc")
[ "$nres" = 3 ] && [ "$wild" = 0 ] && ok "Edge role reads exactly 3 collibra_* secrets, no wildcards" || ko "Edge role scope" "resources=$nres wildcards=$wild"

echo "== 4. Drift"
"$REPO/scripts/tf.sh" lab plan -input=false -no-color -detailed-exitcode >/tmp/tf-verify-plan.$$ 2>&1; rc=$?
[ "$rc" = 0 ] && ok "plan: no changes (code == reality)" || ko "plan: no changes" "exit $rc: $(grep -E 'Plan:|Error' /tmp/tf-verify-plan.$$ | head -2)"
rm -f /tmp/tf-verify-plan.$$

echo; echo "RESULT: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
