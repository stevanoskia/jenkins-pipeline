# syntax=docker/dockerfile:1

# ---- base: runtime dependencies only (shared by test + runtime) ----------
FROM python:3.14-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

# ---- test: lint + unit tests (Jenkins runs this image, then copies /app/reports out)
FROM base AS test
COPY requirements-dev.txt .
RUN pip install -r requirements-dev.txt
COPY pyproject.toml ./
COPY app/ app/
COPY tests/ tests/
CMD ["sh", "-c", "ruff check . && pytest --junitxml=reports/junit.xml --cov=app --cov-report=term-missing"]

# ---- runtime: what gets pushed and deployed ------------------------------
FROM base AS runtime
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.source="https://github.com/stevanoskia/jenkins-pipeline" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"
ENV APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}
RUN useradd --create-home --uid 10001 appuser
COPY app/ app/
USER appuser
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "app:create_app()"]
