#!/usr/bin/env bash
# Verify the data tier: privileges per role, synthetic-data guarantees,
# data integrity and log hygiene. Read-only (all writes are rolled back
# or expected to be refused). Prints PASS/FAIL per check.
set -uo pipefail
CTX=k3d-cel-lab
k() { kubectl --context="$CTX" -n data "$@"; }
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass+1)); }
ko() { echo "  FAIL  $1  -> $2"; fail=$((fail+1)); }
secret() { k get secret "$1" -o jsonpath='{.data.password}' | base64 -d; }

# Run SQL in the Postgres pod as <role>. The password travels over stdin.
pg() {  # role, sql
  local role="$1" sql="$2" sec
  case "$role" in
    postgres) sec=pg-admin;; bank_app) sec=pg-app;; bank_migrator) sec=pg-migrator;;
    collibra_ingest) sec=pg-collibra-ingest;; collibra_profile) sec=pg-collibra-profile;;
  esac
  { secret "$sec"; echo; printf '%s\n' "$sql"; } | k exec -i bank-core-pg-0 -- sh -c \
    'read -r PW; PGPASSWORD="$PW" psql -X -qAt -h 127.0.0.1 -U '"$role"' -d bank_core -v ON_ERROR_STOP=1 2>&1' 2>/dev/null
}
my() {  # user, sql
  local user="$1" sql="$2" sec
  case "$user" in root) sec=mysql-admin;; crm_app) sec=mysql-crm-app;; collibra_ingest) sec=mysql-collibra-ingest;; esac
  { secret "$sec"; echo; printf '%s\n' "$sql"; } | k exec -i crm-mysql-0 -- bash -c \
    'read -r PW; MYSQL_PWD="$PW" mysql -h 127.0.0.1 -u '"$user"' -N -B crm 2>&1' 2>/dev/null
}
expect_eq()   { [ "$2" = "$3" ] && ok "$1" || ko "$1" "expected '$3', got '$2'"; }
expect_like() { echo "$2" | grep -qiE "$3" && ok "$1" || ko "$1" "$(echo "$2" | head -1)"; }

echo "== PostgreSQL: collibra_ingest (metadata only)"
expect_eq   "can connect"                               "$(pg collibra_ingest 'select 1')" "1"
expect_eq   "sees all 11 tables via pg_catalog (JDBC metadata path)" \
            "$(pg collibra_ingest "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and n.nspname in ('reference','customer','account','payment','transactions')")" "11"
expect_eq   "sees column definitions via pg_catalog" \
            "$(pg collibra_ingest "select count(*) from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and n.nspname='customer' and a.attnum>0 and not a.attisdropped")" "36"
expect_eq   "sees column comments (descriptions)" \
            "$(pg collibra_ingest "select col_description('customer.customers'::regclass, 9) like '[PII-DIRECT]%'")" "t"
expect_eq   "information_schema.columns hides privilege-less tables" \
            "$(pg collibra_ingest "select count(*) from information_schema.columns where table_schema='customer'")" "0"
expect_like "CANNOT read customer rows"                "$(pg collibra_ingest 'select first_name from customer.customers limit 1')" "permission denied"
expect_like "CANNOT write (read-only transactions)"    "$(pg collibra_ingest "create table public.x(i int)")" "read-only|permission denied"

echo "== PostgreSQL: collibra_profile (profiling / classification)"
expect_eq   "can read rows for profiling"              "$(pg collibra_profile 'select count(*) from customer.customers')" "5000"
expect_eq   "can read reporting views"                 "$(pg collibra_profile 'select count(*) > 0 from reporting.v_customer_360')" "t"
expect_like "CANNOT modify data"                       "$(pg collibra_profile "update customer.customers set email='x' where customer_id=1")" "read-only"

echo "== PostgreSQL: bank_app (application)"
expect_eq   "can insert a payment (rolled back)" \
            "$(pg bank_app "begin; insert into payment.payments(end_to_end_id,debtor_account_id,creditor_name,creditor_iban,creditor_country,amount,currency_code,scheme,purpose_code,channel,status,initiated_at) values (gen_random_uuid(),1,'Test','GB00TEST','GB',1,'GBP','FPS','OTHR','API','INITIATED',now()) returning 'ok'; rollback;")" "ok"
expect_like "CANNOT change customer master"           "$(pg bank_app "update customer.customers set email='x' where customer_id=1")" "permission denied"
expect_like "CANNOT create tables (no DDL)"           "$(pg bank_app "create table payment.x(i int)")" "permission denied"

echo "== PostgreSQL: synthetic-data guarantees and integrity"
expect_eq "all NI numbers use never-issued QQ prefix" "$(pg postgres "select count(*) from customer.customers where national_insurance_number is not null and national_insurance_number not like 'QQ%'")" "0"
expect_eq "all emails on reserved example.* domains"  "$(pg postgres "select count(*) from customer.customers where email !~ '@example\.(com|org)$'")" "0"
expect_eq "no full card numbers stored"               "$(pg postgres "select count(*) from account.cards where pan_masked !~ '^400000\*{6}[0-9]{4}$'")" "0"
expect_eq "every account IBAN passes ISO 13616 mod-97" \
          "$(pg postgres "select count(*) from account.accounts a where (select string_agg(case when ch ~ '[A-Z]' then (ascii(ch)-55)::text else ch end, '' order by ord) from regexp_split_to_table(substr(a.iban,5)||substr(a.iban,1,4), '') with ordinality t(ch, ord))::numeric % 97 <> 1")" "0"
expect_eq "no orphan accounts"                        "$(pg postgres "select count(*) from account.accounts a left join customer.customers c using (customer_id) where c.customer_id is null")" "0"
expect_eq "every settled payment has a ledger debit"  "$(pg postgres "select count(*) from payment.payments p where status='SETTLED' and not exists (select 1 from transactions.transactions t where t.payment_id=p.payment_id)")" "0"
expect_eq "AML view returns alerts"                   "$(pg postgres "select count(*) > 0 from reporting.v_aml_high_risk_payments")" "t"

echo "== PostgreSQL: log hygiene"
logs=$(k logs bank-core-pg-0 --tail=-1)
grep -qiE "password '|identified by|PASSWORD '" <<<"$logs" && ko "no passwords in server log" "found password text" || ok "no passwords in server log"
grep -q "connection authorized: user=collibra_ingest" <<<"$logs" && ok "connections are logged (audit trail)" || ko "connections are logged" "not found"

echo "== MySQL: collibra_ingest (metadata only)"
expect_eq   "sees 5 CRM tables in information_schema" "$(my collibra_ingest "select count(*) from information_schema.tables where table_schema='crm' and table_type='BASE TABLE'")" "5"
expect_eq   "sees column definitions + comments"      "$(my collibra_ingest "select count(*) > 0 from information_schema.columns where table_schema='crm' and column_comment like '[PII%'")" "1"
expect_like "CANNOT read contact rows"                "$(my collibra_ingest 'select email from contacts limit 1')" "denied"
echo "== MySQL: crm_app"
expect_like "CANNOT drop tables"                      "$(my crm_app 'drop table complaints')" "denied"
expect_eq   "can read contacts"                       "$(my crm_app 'select count(*) from contacts')" "4600"

echo "== Network exposure"
expect_eq "no NodePort/LoadBalancer services in data" "$(k get svc -o jsonpath='{range .items[*]}{.spec.type}{"\n"}{end}' | grep -cvE '^ClusterIP$')" "0"

echo; echo "RESULT: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
