"""Data access. The API depends on the Repository interface, so tests can
swap in a fake without a database."""
from typing import Optional, Protocol

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import Settings
from .models import AccountSummary, Payment, PaymentRequest, Transaction, mask_iban


class Repository(Protocol):
    def ping(self) -> bool: ...
    def get_payment(self, payment_id: int) -> Optional[Payment]: ...
    def account_summary(self, account_id: int) -> Optional[AccountSummary]: ...
    def create_payment(self, req: PaymentRequest) -> Payment: ...
    def close(self) -> None: ...


_PAYMENT_COLS = """payment_id, end_to_end_id, debtor_account_id, creditor_name, creditor_iban,
                   amount, currency_code, scheme, status, initiated_at, settled_at"""


def _to_payment(row: dict) -> Payment:
    return Payment(
        payment_id=row["payment_id"],
        end_to_end_id=row["end_to_end_id"],
        debtor_account_id=row["debtor_account_id"],
        creditor_name=row["creditor_name"],
        creditor_iban_masked=mask_iban(row["creditor_iban"]),
        amount=row["amount"],
        currency=row["currency_code"],
        scheme=row["scheme"],
        status=row["status"],
        initiated_at=row["initiated_at"],
        settled_at=row["settled_at"],
    )


class PostgresRepository:
    def __init__(self, settings: Settings):
        self._timeout = settings.db_timeout_seconds
        # open=False + wait=False: the app starts even if the DB is down;
        # readiness reports it instead of the process crashing.
        self._pool = ConnectionPool(
            conninfo=settings.dsn,
            min_size=settings.db_pool_min,
            max_size=settings.db_pool_max,
            timeout=settings.db_timeout_seconds,
            kwargs={"row_factory": dict_row, "autocommit": False},
            open=False,
        )
        self._pool.open(wait=False)

    def ping(self) -> bool:
        try:
            with self._pool.connection(timeout=self._timeout) as conn:
                conn.execute("SET LOCAL statement_timeout = '2s'")
                conn.execute("SELECT 1")
            return True
        except Exception:
            return False

    def get_payment(self, payment_id: int) -> Optional[Payment]:
        with self._pool.connection() as conn:
            row = conn.execute(
                f"SELECT {_PAYMENT_COLS} FROM payment.payments WHERE payment_id = %s", (payment_id,)
            ).fetchone()
        return _to_payment(row) if row else None

    def account_summary(self, account_id: int) -> Optional[AccountSummary]:
        with self._pool.connection() as conn:
            acct = conn.execute(
                """SELECT account_id, iban, product_code, currency_code, status, current_balance
                   FROM account.accounts WHERE account_id = %s""",
                (account_id,),
            ).fetchone()
            if not acct:
                return None
            txns = conn.execute(
                """SELECT booking_date::text, direction, amount, currency_code, description
                   FROM transactions.transactions WHERE account_id = %s
                   ORDER BY booking_date DESC, transaction_id DESC LIMIT 5""",
                (account_id,),
            ).fetchall()
        return AccountSummary(
            account_id=acct["account_id"],
            iban_masked=mask_iban(acct["iban"]),
            product_code=acct["product_code"],
            currency=acct["currency_code"],
            status=acct["status"],
            current_balance=acct["current_balance"],
            recent_transactions=[
                Transaction(booking_date=t["booking_date"], direction=t["direction"], amount=t["amount"],
                            currency=t["currency_code"], description=t["description"])
                for t in txns
            ],
        )

    def create_payment(self, req: PaymentRequest) -> Payment:
        country = req.creditor_iban[:2]
        with self._pool.connection() as conn:   # commits on success, rolls back on error
            row = conn.execute(
                f"""INSERT INTO payment.payments
                      (end_to_end_id, debtor_account_id, creditor_name, creditor_iban, creditor_country,
                       amount, currency_code, scheme, purpose_code, channel, status, initiated_at)
                    VALUES (gen_random_uuid(), %s, %s, %s, %s, %s, %s, %s, %s, 'API', 'INITIATED', now())
                    RETURNING {_PAYMENT_COLS}""",
                (req.debtor_account_id, req.creditor_name, req.creditor_iban, country,
                 req.amount, req.currency, req.scheme.value, req.purpose_code),
            ).fetchone()
        return _to_payment(row)

    def close(self) -> None:
        self._pool.close()
