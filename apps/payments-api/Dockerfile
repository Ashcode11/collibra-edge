# syntax=docker/dockerfile:1
# ---------------------------------------------------------------- build stage
# Installs dependencies into a virtualenv. pip, caches and build tooling stay
# in this stage and never reach the runtime image.
FROM python:3.12.16-slim-trixie AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
COPY requirements.txt /tmp/requirements.txt
RUN /opt/venv/bin/pip install -r /tmp/requirements.txt && \
    /opt/venv/bin/pip uninstall -y pip    # no package manager in the shipped venv

# ---------------------------------------------------------------- runtime stage
FROM python:3.12.16-slim-trixie AS runtime
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="payments-api" \
      org.opencontainers.image.description="Sample payments microservice for the Collibra Edge lab" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="https://github.com/Ashcode11/collibra-edge"

# Apply OS security updates published after the base image was built
# (Trivy found fixable HIGH CVEs in zlib1g), then drop the apt lists.
# Fixed, unprivileged UID/GID that Kubernetes securityContext can rely on.
RUN apt-get update && apt-get upgrade -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 10001 app && \
    useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

COPY --from=build /opt/venv /opt/venv
COPY app /srv/app
WORKDIR /srv

USER 10001:10001
EXPOSE 8080
# exec form: uvicorn is PID 1 and receives SIGTERM directly (graceful shutdown)
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log", "--timeout-graceful-shutdown", "20"]
