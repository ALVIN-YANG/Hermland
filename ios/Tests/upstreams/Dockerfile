# Disposable upstream integration environment; no user configuration is mounted.
FROM node:24-bookworm-slim
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       openssh-server openssh-client python3 python3-yaml python3-cryptography \
       iproute2 ca-certificates git \
    && rm -rf /var/lib/apt/lists/*
ARG OPENCLAW_VERSION=2026.9.9
RUN npm install --global openclaw@${OPENCLAW_VERSION}
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv \
    && python3 -m venv /opt/hermes-venv \
    && /opt/hermes-venv/bin/pip install 'pyyaml>=6.0' 'cryptography>=42.0' \
    && rm -rf /var/lib/apt/lists/*
ENV HERMLAND_IOS_TEST=isolated PYTHONDONTWRITEBYTECODE=1
