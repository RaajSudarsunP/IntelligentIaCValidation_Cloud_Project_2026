# ==============================================================================
# Dockerfile for Intelligent IaC Assurance - ML Validation Engine
# ==============================================================================
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    CHECKOV_EXECUTABLE=checkov

WORKDIR /app

# Install system dependencies including git (needed by checkov) and curl
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies including checkov static analysis tool
COPY requirements.txt /app/
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir checkov

# Copy ML pipeline and shared codebase
COPY src/ /app/src/

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1

CMD ["python", "-m", "uvicorn", "src.ml_model.api:app", "--host", "0.0.0.0", "--port", "9000"]
