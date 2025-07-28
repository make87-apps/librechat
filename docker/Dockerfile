# Stage 1: Build pgvector extension with TLS support
FROM debian:bullseye-slim AS pgvector-build

# Install build tools, Git, PostgreSQL dev headers, and CA certificates
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      build-essential \
      git \
      postgresql-server-dev-all && \
    rm -rf /var/lib/apt/lists/*

# Clone and build pgvector, then clean up
RUN git clone --depth 1 https://github.com/ankane/pgvector.git /tmp/pgvector && \
    cd /tmp/pgvector && make && make install && \
    rm -rf /tmp/pgvector && \
    apt-get purge -y --auto-remove build-essential git postgresql-server-dev-all ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Build LibreChat (Node) on Alpine (Node) on Alpine
FROM node:20-alpine AS node-build

RUN apk add --no-cache git python3 make g++
WORKDIR /app
RUN git clone https://github.com/danny-avila/LibreChat.git . && \
    npm ci --legacy-peer-deps && \
    npm run frontend && \
    npm prune --production && \
    rm -rf .git **/*.ts **/__tests__ **/test

# Stage 3: Build RAG‑API in a Python venv (CPU‑only, slim)
FROM python:3.12-slim AS rag-build

# 1) Install minimal OS deps for cloning and TLS
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# 2) Create virtual environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# 3) Install CPU‑only PyTorch wheels to minimize size (latest versions)
RUN pip install --no-cache-dir \
      torch \
      torchvision \
      torchaudio \
      -f https://download.pytorch.org/whl/cpu/torch_stable.html

# 4) Clone RAG API and install only runtime deps (excluding torch) and install only runtime deps (excluding torch)
WORKDIR /opt/rag_api
RUN git clone https://github.com/danny-avila/rag_api.git . && \
    pip install --no-cache-dir -r requirements.txt bcrypt

# 5) Cleanup build dependencies
RUN apt-get purge -y --auto-remove git && \
    rm -rf /root/.cache

# Stage 4: Grab MongoDB binaries (multi‑arch) (multi‑arch)
FROM mongo:6.0 AS mongo-binaries

# Final: monolithic, minimal runtime image based on MongoDB multi-arch
FROM mongo:6.0 AS final

# 1) Install runtime packages and Node.js v20 from NodeSource
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      wget \
      gnupg \
      lsb-release && \
    # import the PGDG signing key and enable the 13.x repo
    wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    # now install exactly 13.x packages + supervisor, python3, curl
    apt-get install -y --no-install-recommends \
      supervisor \
      python3 \
      postgresql-13 \
      postgresql-client-13 \
      curl && \
    # install Node.js 20
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# 2) Copy pgvector (.so) only
COPY --from=pgvector-build \
     /usr/lib/postgresql/13/lib/vector.so \
     /usr/lib/postgresql/13/lib/vector.so

# 3) Copy LibreChat Node app
COPY --from=node-build /app /opt/librechat

# 4) Copy RAG‑API venv & code
COPY --from=rag-build /opt/venv    /opt/venv
COPY --from=rag-build /opt/rag_api /opt/rag_api
ENV PATH="/opt/venv/bin:${PATH}"
ENV PATH="/usr/lib/postgresql/13/bin:${PATH}"

# 5) Install Meilisearch binary
RUN wget -qO /usr/local/bin/meilisearch \
      https://github.com/meilisearch/meilisearch/releases/download/v1.12.3/meilisearch-linux-amd64 && \
    chmod +x /usr/local/bin/meilisearch

# 6) Supervisor config & entrypoint
COPY docker/supervisord.conf /etc/supervisor/conf.d/librechat.conf
COPY docker/entrypoint.sh     /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 7) Persistent volumes & exposed ports
VOLUME [ "/data/db", "/data/jwt_secret", "/data/meili_data", "/data/pgdata" ]
EXPOSE 3080 8000

# 8) In-image defaults
ENV MONGODB_URL="mongodb://127.0.0.1:27017/librechat" \
    MONGO_URI="mongodb://127.0.0.1:27017/librechat" \
    MEILI_HOST="http://127.0.0.1:7700" \
    POSTGRES_HOST="127.0.0.1" \
    POSTGRES_DB="librechat" \
    POSTGRES_USER="librechat" \
    POSTGRES_PASSWORD="changeme" \
    RAG_API_URL="http://127.0.0.1:8000" \
    HOST="0.0.0.0" \
    NODE_ENV="production" \
    ALLOW_REGISTRATION="true" \
    ALLOW_SOCIAL_REGISTRATION="true"

ENTRYPOINT ["/entrypoint.sh"]
