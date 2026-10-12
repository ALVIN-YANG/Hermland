ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       openssh-server openssh-client python3 iproute2 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
ENV HERMLAND_ONBOARDING_TEST=isolated PYTHONDONTWRITEBYTECODE=1
CMD ["bash", "/src/tests/onboarding-linux-check.sh", "/src"]
