"""Unit tests: run without a database by overriding the repository dependency."""
from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app import main
from app.models import AccountSummary, Payment, PaymentRequest, mask_iban


class FakeRepo:
    def __init__(self, up: bool = True):
        self.up = up
        self.created: list[PaymentRequest] = []

    def ping(self) -> bool:
        return self.up

    def get_payment(self, payment_id: int):
        if payment_id != 42:
            return None
        return Payment(payment_id=42, end_to_end_id=uuid4(), debtor_account_id=7, creditor_name="A. Smith",
                       creditor_iban_masked="GB**************5678", amount=Decimal("10.50"), currency="GBP",
                       scheme="FPS", status="SETTLED", initiated_at=datetime.now(timezone.utc))

    def account_summary(self, account_id: int):
        if account_id != 7:
            return None
        return AccountSummary(account_id=7, iban_masked="GB**************1234", product_code="CA01",
                              currency="GBP", status="ACTIVE", current_balance=Decimal("100.00"),
                              recent_transactions=[])

    def create_payment(self, req: PaymentRequest) -> Payment:
        self.created.append(req)
        return Payment(payment_id=1001, end_to_end_id=uuid4(), debtor_account_id=req.debtor_account_id,
                       creditor_name=req.creditor_name, creditor_iban_masked=mask_iban(req.creditor_iban),
                       amount=req.amount, currency=req.currency, scheme=req.scheme.value,
                       status="INITIATED", initiated_at=datetime.now(timezone.utc))

    def close(self) -> None:
        pass


@pytest.fixture
def repo():
    return FakeRepo()


@pytest.fixture
def client(repo):
    main.app.dependency_overrides[main.get_repo] = lambda: repo
    with TestClient(main.app) as c:
        yield c
    main.app.dependency_overrides.clear()


VALID = {"debtor_account_id": 7, "creditor_name": "Acme Supplies Ltd", "creditor_iban": "GB29SYNT99000112345678",
         "amount": "250.00", "currency": "GBP", "scheme": "FPS"}


def test_liveness_does_not_touch_database(client, repo):
    repo.up = False
    assert client.get("/healthz").status_code == 200          # DB down must NOT fail liveness


def test_readiness_reflects_database(client, repo):
    assert client.get("/readyz").status_code == 200
    repo.up = False
    r = client.get("/readyz")
    assert r.status_code == 503 and r.json()["database"] == "unreachable"


def test_get_payment_found_and_not_found(client):
    assert client.get("/api/v1/payments/42").json()["status"] == "SETTLED"
    assert client.get("/api/v1/payments/1").status_code == 404


def test_account_summary_masks_iban(client):
    body = client.get("/api/v1/accounts/7/summary").json()
    assert body["iban_masked"].startswith("GB") and "*" in body["iban_masked"]


def test_create_payment_success(client, repo):
    r = client.post("/api/v1/payments", json=VALID)
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "INITIATED"
    assert body["creditor_iban_masked"] == "GB****************5678"
    assert len(repo.created) == 1


@pytest.mark.parametrize("field,value", [
    ("amount", "-5"), ("amount", "0"), ("scheme", "CASH"),
    ("creditor_iban", "not-an-iban"), ("currency", "pounds"), ("debtor_account_id", 0),
])
def test_create_payment_rejects_invalid_input(client, repo, field, value):
    r = client.post("/api/v1/payments", json={**VALID, field: value})
    assert r.status_code == 422
    assert repo.created == []                                  # nothing reached the repository


def test_metrics_use_route_templates_not_raw_ids(client):
    client.get("/api/v1/payments/42")
    text = client.get("/metrics").text
    assert 'route="/api/v1/payments/{payment_id}"' in text
    assert 'route="/api/v1/payments/42"' not in text


@pytest.mark.parametrize("iban,expected", [
    ("GB29SYNT99000112345678", "GB****************5678"), ("", "****"), ("GB12", "****"),
])
def test_mask_iban(iban, expected):
    assert mask_iban(iban) == expected
