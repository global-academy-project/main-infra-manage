FROM python:3.12.15-slim AS base

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

#-------------------------[Multi-stage build Qdrant init image]---------------------------------------
FROM base AS qdrant-init

COPY requirements.qdrant-init.txt ./
RUN python -m venv /opt/venv \
    && /opt/venv/bin/python -m pip install --no-cache-dir -r requirements.qdrant-init.txt \
    && /opt/venv/bin/python -m pip check

USER 65003:65003

COPY scripts ./scripts

CMD ["python", "-m", "scripts.init_qdrant"]