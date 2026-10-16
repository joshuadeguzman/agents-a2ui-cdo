# Siargao MCP server. Build context is mcp/ (run scripts/sync_shared.sh first).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY siargao_mcp/ siargao_mcp/
COPY surfaces/ surfaces/
COPY templates/ templates/
COPY data/ data/
COPY catalog/ catalog/

RUN useradd --create-home --uid 10001 app
USER app

# Cloud Run sets PORT (8080). Locally it defaults to 10003.
EXPOSE 10003
CMD ["python", "-m", "siargao_mcp"]
