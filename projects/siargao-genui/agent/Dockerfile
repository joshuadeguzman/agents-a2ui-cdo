# Siargao agent for Cloud Run. Build context: this folder (agent/).
#
# The image defaults to SIARGAO_MODE=live because the deployed service is the
# live demo. Run it with -e SIARGAO_MODE=offline to serve templates only.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8080 \
    SIARGAO_MODE=live \
    SURFACE_LOG=/tmp/surfaces.jsonl

WORKDIR /app

COPY requirements.txt constraints.txt ./
RUN pip install -r requirements.txt -c constraints.txt

COPY siargao_agent ./siargao_agent
COPY templates ./templates
COPY data ./data

RUN useradd --create-home --uid 10001 agent
USER agent

EXPOSE 8080
CMD ["python", "-m", "siargao_agent"]
