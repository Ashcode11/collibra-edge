"""payments-api: sample enterprise microservice for the Collibra Edge lab.

Endpoints
  GET  /healthz                          liveness  (process only, never the DB)
  GET  /readyz                           readiness (DB reachable?)
  GET  /metrics                          Prometheus metrics
  GET  /api/v1/payments/{payment_id}
  GET  /api/v1/accounts/{account_id}/summary
  POST /api/v1/payments                  create an INITIATED payment
"""
import json
import logging
import sys
import time
from contextlib import asynccontextmanager
from typing import Callable, Optional

import psycopg
from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

from . import config
from .db import PostgresRepository, Repository
from .models import AccountSummary, Payment, PaymentRequest

settings = config.load()


# ----------------------------------------------------------------- logging (JSON lines)
class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
            "service": settings.app_name,
            "env": settings.app_env,
            "version": settings.app_version,
        }
        entry.update(getattr(record, "extra_fields", {}))
        return json.dumps(entry)


_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(JsonFormatter())
logging.basicConfig(level=settings.log_level, handlers=[_handler], force=True)
log = logging.getLogger("payments-api")


def log_event(msg: str, **fields) -> None:
    log.info(msg, extra={"extra_fields": fields})


# ----------------------------------------------------------------- metrics
HTTP_REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
HTTP_LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["method", "route"])
DB_UP = Gauge("payments_api_db_up", "1 if the database answered the last readiness check")
PAYMENTS_CREATED = Counter("payments_created_total", "Payments created via the API", ["scheme"])
APP_INFO = Gauge("payments_api_info", "Build info", ["version", "env"])
APP_INFO.labels(settings.app_version, settings.app_env).set(1)

# ----------------------------------------------------------------- repository wiring
_repo: Optional[Repository] = None


def get_repo() -> Repository:
    if _repo is None:
        raise HTTPException(status_code=503, detail="repository not initialised")
    return _repo


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _repo
    if _repo is None and settings.db_user:
        _repo = PostgresRepository(settings)
    log_event("startup", db_host=settings.db_host, db_name=settings.db_name)
    yield
    log_event("shutdown")          # SIGTERM -> uvicorn drains in-flight requests -> here
    if _repo is not None:
        _repo.close()


app = FastAPI(title="payments-api", version=settings.app_version, lifespan=lifespan)


@app.middleware("http")
async def observe(request: Request, call_next: Callable):
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        # Label by route TEMPLATE (/api/v1/payments/{payment_id}), never the raw
        # path: raw IDs would create one time series per payment.
        route = getattr(request.scope.get("route"), "path", "unmatched")
        elapsed = time.perf_counter() - start
        HTTP_REQUESTS.labels(request.method, route, str(status)).inc()
        HTTP_LATENCY.labels(request.method, route).observe(elapsed)
        if route not in ("/healthz", "/readyz", "/metrics"):
            log_event("request", method=request.method, route=route, status=status,
                      duration_ms=round(elapsed * 1000, 1))


@app.exception_handler(psycopg.Error)
async def db_error(_: Request, exc: psycopg.Error):
    log.error("database error", extra={"extra_fields": {"error_class": type(exc).__name__}})
    return JSONResponse(status_code=503, content={"detail": "database unavailable"})


# ----------------------------------------------------------------- probes & metrics
@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz(response: Response, repo: Repository = Depends(get_repo)):
    up = repo.ping()
    DB_UP.set(1 if up else 0)
    if not up:
        response.status_code = 503
        return {"status": "not ready", "database": "unreachable"}
    return {"status": "ready", "database": "ok"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


# ----------------------------------------------------------------- business API
@app.get("/api/v1/payments/{payment_id}", response_model=Payment)
def get_payment(payment_id: int, repo: Repository = Depends(get_repo)):
    p = repo.get_payment(payment_id)
    if p is None:
        raise HTTPException(status_code=404, detail="payment not found")
    return p


@app.get("/api/v1/accounts/{account_id}/summary", response_model=AccountSummary)
def account_summary(account_id: int, repo: Repository = Depends(get_repo)):
    s = repo.account_summary(account_id)
    if s is None:
        raise HTTPException(status_code=404, detail="account not found")
    return s


@app.post("/api/v1/payments", response_model=Payment, status_code=201)
def create_payment(req: PaymentRequest, repo: Repository = Depends(get_repo)):
    p = repo.create_payment(req)
    PAYMENTS_CREATED.labels(req.scheme.value).inc()
    log_event("payment_created", payment_id=p.payment_id, scheme=p.scheme)   # no names/IBANs in logs
    return p
