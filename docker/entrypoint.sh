#!/bin/sh
set -e

# ──────────────────────────────────────────────────────────────
# Ensure required data directories exist
# ──────────────────────────────────────────────────────────────
mkdir -p /data/db /data/pgdata /data/jwt_secret
chown -R postgres:postgres /data/pgdata

# ──────────────────────────────────────────────────────────────
# 1) JWT secret (persisted under /data/jwt_secret)
# ──────────────────────────────────────────────────────────────
SECRET_FILE=/data/jwt_secret/secret
if [ ! -f "$SECRET_FILE" ]; then
  echo "Generating new JWT secret…"
  head -c 32 /dev/urandom | base64 > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
fi
export JWT_SECRET="$(cat "$SECRET_FILE")"

# ──────────────────────────────────────────────────────────────
# 2) Default in‑container Mongo URL
# ──────────────────────────────────────────────────────────────
: "${MONGODB_URL:=mongodb://127.0.0.1:27017/librechat}"
export MONGODB_URL

# ──────────────────────────────────────────────────────────────
# 3) Initialize Postgres if necessary
# ──────────────────────────────────────────────────────────────
# Load Postgres password from MAKE87_CONFIG or fallback
DEFAULT_PG_PW="changeme"
if [ -n "$MAKE87_CONFIG" ]; then
  POSTGRES_PASSWORD=$(printf '%s' "$MAKE87_CONFIG" | jq -r '.config.postgres_password // empty')
fi
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$DEFAULT_PG_PW}"
export POSTGRES_PASSWORD

if [ ! -f /data/pgdata/PG_VERSION ]; then
  echo "Initializing PostgreSQL data directory…"
  su postgres -c "/usr/lib/postgresql/13/bin/initdb -D /data/pgdata"
fi

# ──────────────────────────────────────────────────────────────
# 4) Generate /opt/librechat/librechat.yaml from $MAKE87_CONFIG or write default
# ──────────────────────────────────────────────────────────────
echo "⟳ Generating /opt/librechat/librechat.yaml…"
cat <<EOF > /opt/librechat/librechat.yaml
version: 1.2.8

EOF

if [ -n "$MAKE87_CONFIG" ]; then
  echo "→ Populating MCP servers and Ollama config from MAKE87_CONFIG"
  clients=$(printf '%s' "$MAKE87_CONFIG" | jq -c '.interfaces["mcp_servers"].clients[]')
  echo "mcpServers:" >> /app/librechat.yaml
  for client in $clients; do
    name=$(printf '%s' "$client" | jq -r '.name')
    ip=$(printf '%s' "$client" | jq -r '.vpn_ip')
    port=$(printf '%s' "$client" | jq -r '.vpn_port')
    cat <<EOL >> /app/librechat.yaml
  $name:
    url: "http://$ip:$port/sse"
EOL
  done

  ollama_client=$(printf '%s' "$MAKE87_CONFIG" | jq -c '.interfaces["ollama"].clients[]? | select(.name == "ollama")')
  if [ -n "$ollama_client" ]; then
    ollama_ip=$(printf '%s' "$ollama_client" | jq -r '.vpn_ip')
    ollama_port=$(printf '%s' "$ollama_client" | jq -r '.vpn_port')
    cat <<EOL >> /app/librechat.yaml

ollama:
  baseURL: "http://$ollama_ip:$ollama_port"
  models:
    - model: llama3
EOL
  fi
else
  echo "→ MAKE87_CONFIG not set; writing default minimal config"
fi

echo "✔ /app/librechat.yaml:"
sed 's/^/   /' /opt/librechat/librechat.yaml

# ──────────────────────────────────────────────────────────────
# 5) Start Supervisor
# ──────────────────────────────────────────────────────────────
ENV_FILE="/opt/librechat/.env"

# 1. Copy example env if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    cp /opt/librechat/.env.example "$ENV_FILE"
fi

# 2. Function to set default env vars if missing
set_env_if_missing() {
    KEY=$1
    VALUE=$2
    FILE=$3
    grep -q "^$KEY=" "$FILE" || echo "$KEY=$VALUE" >> "$FILE"
}

# 3. Patch critical values from container env (adjust to your config system)
set_env_if_missing "JWT_SECRET" "${JWT_SECRET:-$(openssl rand -hex 32)}" "$ENV_FILE"
set_env_if_missing "JWT_REFRESH_SECRET" "${JWT_REFRESH_SECRET:-$(openssl rand -hex 32)}" "$ENV_FILE"
set_env_if_missing "MONGO_URI" "${MONGO_URI:-mongodb://127.0.0.1:27017/LibreChat}" "$ENV_FILE"
set_env_if_missing "OPENAI_API_KEY" "${OPENAI_API_KEY:-user_provided}" "$ENV_FILE"
set_env_if_missing "POSTGRES_PASSWORD" "${POSTGRES_PASSWORD:-librechat}" "$ENV_FILE"
set_env_if_missing "ALLOW_REGISTRATION" "true" "$ENV_FILE"
set_env_if_missing "ALLOW_UNVERIFIED_EMAIL_LOGIN" "true" "$ENV_FILE"


# Now launch supervisord
exec supervisord -n -c /etc/supervisor/conf.d/librechat.conf

