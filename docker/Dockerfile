# ───────────────────────────────────────────────────────────
# Monolithic LibreChat image with API, RAG‑API, Mongo, Meili, PGVector
# Base: Debian slim for maximum compatibility with official binaries
# ───────────────────────────────────────────────────────────
FROM debian:bullseye-slim

# 1) System packages, PostgreSQL 15, and Node.js 20 setup
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg ca-certificates wget lsb-release && \
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    apt-key add /usr/share/keyrings/postgresql.gpg && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && apt-get install -y --no-install-recommends \
    git build-essential supervisor python3 python3-pip \
    nodejs \
    postgresql-15 \
    postgresql-client-15 \
    postgresql-contrib-15 \
    postgresql-server-dev-15 \
    libpq-dev && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/postgresql/15/bin:${PATH}"
# 2) MongoDB repo & install (force using 'bullseye' distro)
RUN curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc \
      | gpg --dearmor -o /usr/share/keyrings/mongodb.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/mongodb.gpg] \
      https://repo.mongodb.org/apt/debian bullseye/mongodb-org/6.0 main" \
      > /etc/apt/sources.list.d/mongodb-org.list \
 && apt-get update \
 && apt-get install -y mongodb-org \
 && rm -rf /var/lib/apt/lists/*

# 3) Meilisearch (v1.12.3) download & unpack
RUN wget -qO /usr/local/bin/meilisearch \
      https://github.com/meilisearch/meilisearch/releases/download/v1.12.3/meilisearch-linux-amd64 \
 && chmod +x /usr/local/bin/meilisearch

# 4) pgvector extension build & install
RUN git clone --depth 1 https://github.com/ankane/pgvector.git /tmp/pgvector \
 && cd /tmp/pgvector && make && make install \
 && rm -rf /tmp/pgvector

# 5) Clone & build LibreChat API (stage equivalent)
WORKDIR /opt/librechat
RUN git clone https://github.com/danny-avila/LibreChat.git . \
 && npm ci --legacy-peer-deps \
 && npm run frontend \
 && npm prune --production

# 6) Clone & install RAG‑API
WORKDIR /opt/rag_api
RUN git clone https://github.com/danny-avila/rag_api.git . \
 && pip3 install -r requirements.txt
RUN pip3 install bcrypt
# 7) Supervisor config
COPY docker/supervisord.conf /etc/supervisor/conf.d/librechat.conf
# (Make sure your supervisord.conf has programs: mongod, meilisearch, postgresql, librechat, rag_api)

# 8) Entrypoint for JWT, MONGO_URL, MCP servers, then launch supervisord
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 9) Volumes and ports
#VOLUME [ "/data/db", "/data/jwt_secret", "/data/meili_data", "/data/pgdata" ]
EXPOSE 3080 8000

# ────────────────────────────────────────────────
#  Setting default, in‑container service URLs
# ────────────────────────────────────────────────
# MongoDB (local mongod)
ENV MONGODB_URL="mongodb://127.0.0.1:27017/librechat"
ENV MONGO_URI="mongodb://127.0.0.1:27017/librechat"

# Meilisearch (local binary)
ENV MEILI_HOST="http://127.0.0.1:7700"
ENV MEILI_NO_ANALYTICS="true"

# PostgreSQL + pgvector
ENV POSTGRES_HOST="127.0.0.1"
ENV POSTGRES_DB="librechat"
ENV POSTGRES_USER="librechat"

# RAG‑API (local Python service)
#ENV RAG_API_URL="http://127.0.0.1:8000"
#ENV EMBEDDINGS_PROVIDER=remote
#ENV VECTOR_DB_TYPE=pgvector
#ENV DB_HOST=127.0.0.1
#ENV DB_PORT=5432
# LibreChat API itself
ENV HOST="0.0.0.0"
ENV NODE_ENV="production"
ENV ALLOW_REGISTRATION=true
ENV ALLOW_SOCIAL_REGISTRATION=true


# ────────────────────────────────────────────────
#  Finish up with your entrypoint
# ────────────────────────────────────────────────
ENTRYPOINT ["/entrypoint.sh"]
