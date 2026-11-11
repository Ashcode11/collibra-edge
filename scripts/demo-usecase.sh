#!/usr/bin/env bash
# End-to-end use case in 6 steps: "Can Collibra Edge safely catalogue our
# customer data?" Run it and read along. Read-only except step 1 (one payment).
set -uo pipefail
CTX=k3d-cel-lab
k() { kubectl --context="$CTX" "$@"; }
step() { printf '\n\033[1m%s\033[0m\n%s\n' "$1" "$2"; }
pg_admin() { k -n data exec bank-core-pg-0 -- psql -X -qAt -U postgres -d bank_core -c "$1" 2>/dev/null; }
pg_as_edge() {  # connect exactly like Collibra Edge would: as collibra_ingest, over TCP
  { k -n data get secret pg-collibra-ingest -o jsonpath='{.data.password}' | base64 -d; echo; } |
    k -n data exec -i bank-core-pg-0 -- sh -c \
      'read -r PW; PGPASSWORD="$PW" psql -X -h 127.0.0.1 -U collibra_ingest -d bank_core -c "'"$1"'" 2>&1' 2>/dev/null
}
API=http://payments.lab.localhost:18000/api/v1

# A high-risk customer's current account, so the payment trips the AML report
ACCT=$(pg_admin "select a.account_id from account.accounts a join customer.customers c using (customer_id)
                 where c.risk_rating='HIGH' and a.product_code in ('CA01','CA02') and a.status='ACTIVE' order by 1 limit 1")

step "1. A customer makes a payment" \
     "The banking app (payments-api) receives a £12,500 transfer from account $ACCT and stores it in PostgreSQL."
P=$(curl -s -X POST "$API/payments" -H 'content-type: application/json' \
  -d "{\"debtor_account_id\":$ACCT,\"creditor_name\":\"Pacific Traders Pte\",\"creditor_iban\":\"GB29SYNT99000112345678\",\"amount\":\"12500.00\",\"currency\":\"GBP\",\"scheme\":\"CHAPS\"}")
PID=$(jq -r .payment_id <<<"$P"); echo "$P" | jq -c '{payment_id, amount, scheme, status, creditor_iban_masked}'

step "2. The data flows into a report" \
     "Compliance has a view (reporting.v_aml_high_risk_payments) built from payments + accounts + customers.
The new payment appears there. That chain of tables is the LINEAGE Collibra would draw."
pg_admin "select 'payment '||payment_id||': '||amount||' '||currency_code||', customer risk '||risk_rating from reporting.v_aml_high_risk_payments where payment_id=$PID"

step "3. Governance asks: where is our customer data?" \
     "Collibra Edge connects as its own account 'collibra_ingest' and reads the STRUCTURE: tables, columns, descriptions."
pg_as_edge "select a.attname as column_name, col_description(a.attrelid,a.attnum) as description from pg_attribute a where a.attrelid='customer.customers'::regclass and a.attname in ('first_name','national_insurance_number','email','date_of_birth')" | sed -n '1,7p'
echo "-> Collibra would catalogue these columns and tag them as personal data (PII)."

step "4. ...but Edge cannot read the customers themselves" \
     "Least privilege: metadata ingestion never needs actual names or balances."
pg_as_edge "select first_name, email from customer.customers limit 1" | head -1

step "5. The surprise: the same personal data lives in another system" \
     "The CRM (MySQL, owned by Marketing) keeps its own copy of names, emails and birth dates."
k -n data exec crm-mysql-0 -- bash -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot crm -t -e "select table_name, column_name, column_comment from information_schema.columns where table_schema=\"crm\" and column_comment like \"[PII%\" order by 1,2"' 2>/dev/null
echo "-> A catalog makes this 'PII sprawl' visible, so it can be owned, minimised or protected."

step "6. Where did Edge's password come from?" \
     "From the vault (Secrets Manager, managed by Terraform). This is what you'd type into the Edge connection:"
k -n data get secret pg-collibra-ingest -o jsonpath='{.metadata.annotations.lab\.cel/secretsmanager-name}'; echo "   field: /password   (the value itself is never shown)"

printf '\n\033[1mSummary\033[0m\n'
cat <<EOF
  payment (app) -> PostgreSQL -> AML report        real, just happened
  Edge account sees structure, not data            real, just proven
  same PII also in CRM                             real
  password from vault, not code                    real (emulated AWS)
  Collibra Edge + Catalog showing all of this      conceptual (needs x86 Linux + tenant)
EOF
