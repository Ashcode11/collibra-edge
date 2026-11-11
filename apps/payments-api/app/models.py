"""Request/response models. Validation happens here, before any SQL runs."""
from datetime import datetime
from decimal import Decimal
from enum import Enum
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


class Scheme(str, Enum):
    FPS = "FPS"
    BACS = "BACS"
    CHAPS = "CHAPS"
    SEPA_CT = "SEPA_CT"
    SWIFT = "SWIFT"


class PaymentRequest(BaseModel):
    debtor_account_id: int = Field(gt=0)
    creditor_name: str = Field(min_length=1, max_length=120)
    # ISO 13616 shape: 2 letters, 2 digits, up to 30 alphanumerics
    creditor_iban: str = Field(pattern=r"^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$")
    amount: Decimal = Field(gt=0, max_digits=18, decimal_places=2)
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    scheme: Scheme
    purpose_code: str = Field(default="OTHR", pattern=r"^[A-Z]{4}$")


class Payment(BaseModel):
    payment_id: int
    end_to_end_id: UUID
    debtor_account_id: int
    creditor_name: str
    creditor_iban_masked: str
    amount: Decimal
    currency: str
    scheme: str
    status: str
    initiated_at: datetime
    settled_at: Optional[datetime] = None


class Transaction(BaseModel):
    booking_date: str
    direction: str
    amount: Decimal
    currency: str
    description: Optional[str] = None


class AccountSummary(BaseModel):
    account_id: int
    iban_masked: str
    product_code: str
    currency: str
    status: str
    current_balance: Decimal
    recent_transactions: list[Transaction]


def mask_iban(iban: str) -> str:
    """Data minimisation: expose only country code and last 4 characters."""
    if not iban or len(iban) < 8:
        return "****"
    return f"{iban[:2]}{'*' * (len(iban) - 6)}{iban[-4:]}"
