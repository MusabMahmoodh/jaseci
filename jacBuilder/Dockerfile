# JAC Builder Studio — production image
# Mirrors the build steps performed by the GitHub Actions deploy pipeline.
#
# Prerequisites before building:
#   - jac_coder/ directory must be present in this folder (cloned from jaseci-labs/jac-code)
#     e.g. git clone https://<token>@github.com/jaseci-labs/jac-code.git /tmp/jac-code
#          cp -r /tmp/jac-code/jac_coder ./jac_coder
#
# Build:
#   docker build -t jac-builder:latest .
#
# Run locally:
#   docker run -p 8000:8000 \
#     -e OPENAI_API_KEY=... \
#     -e HOST=http://localhost:8000 \
#     jac-builder:latest

ARG TARGETPLATFORM=linux/amd64
FROM --platform=${TARGETPLATFORM} python:3.12-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    unzip && \
    rm -rf /var/lib/apt/lists/*

# Install Jaseci Python packages
RUN pip install --no-cache-dir jaclang jac-scale jac-client jac-byllm jac-super

# Install Bun (required for npm dependency management)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

# Install kubectl (required for jac-scale sandbox management)
RUN curl -sL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

# Copy jac.toml first to leverage layer caching for npm install
COPY jac.toml* ./

# Install npm dependencies declared in jac.toml
RUN if [ -f jac.toml ]; then jac install; fi

# Copy jac_coder (must be pre-cloned from jaseci-labs/jac-code before building)
COPY jac_coder/ ./jac_coder/

# Copy remaining application source
COPY . .

# Pre-compile and cache Jac modules for faster startup
RUN jac check main.jac || true

EXPOSE 8000

CMD ["jac", "start", "main.jac"]
