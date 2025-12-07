#!/bin/bash

# Helper script to generate per-database docker-compose.yml files
# This is called by db_manager.sh

# Get the project root (parent of helpers directory)
HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${HELPER_DIR}/.." && pwd)"
CENTRAL_ENV="${SCRIPT_DIR}/databases.env"
# Use supabase/docker as template if supabase-project doesn't exist
if [ -d "${SCRIPT_DIR}/supabase-project" ]; then
    TEMPLATE_DIR="${SCRIPT_DIR}/supabase-project"
elif [ -d "${SCRIPT_DIR}/supabase/docker" ]; then
    TEMPLATE_DIR="${SCRIPT_DIR}/supabase/docker"
else
    TEMPLATE_DIR="${SCRIPT_DIR}/supabase-project"
    echo "Warning: Template directory not found. Using supabase/docker if available."
fi

if [ ! -f "$CENTRAL_ENV" ]; then
    echo "Error: databases.env not found"
    exit 1
fi

# Read global config
source <(grep -E "^[A-Z_]+=" "$CENTRAL_ENV" | grep -v "^#")

# Check if full services mode (default: lean)
FULL_SERVICES="${1:-lean}"

# Optional: generate for specific database only
TARGET_DB="${2:-}"

# Function to generate compose file for a single database
generate_db_compose() {
    local db_name="$1"
    local postgres_port="$2"
    local kong_http_port="$3"
    local kong_https_port="$4"
    local pooler_port="$5"
    local cpu_limit="$6"
    local memory_limit="$7"
    local postgres_pass="$8"
    local jwt_secret="$9"
    local anon_key="${10}"
    local service_key="${11}"
    local studio_port="${12}"
    local db_mode="${13:-full}"
    
    local db_dir="${SCRIPT_DIR}/databases/${db_name}"
    local compose_file="${db_dir}/docker-compose.yml"
    
    # Ensure directory exists
    mkdir -p "$db_dir"
    
    # Use template directory volumes if it exists
    local volumes_path="${TEMPLATE_DIR}/volumes"
    
    cat > "$compose_file" << EOF
# Auto-generated docker-compose.yml for ${db_name}
# DO NOT EDIT MANUALLY - Use ./db_manager.sh to manage databases
# Generated from databases.env

name: ${db_name}

services:
  ${db_name}-db:
    container_name: ${db_name}-db
    image: supabase/postgres:15.8.1.085
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '${cpu_limit}'
          memory: ${memory_limit}
        reservations:
          cpus: '0.5'
          memory: 512m
    ports:
      - "${postgres_port}:5432"
    volumes:
      - ${volumes_path}/db/realtime.sql:/docker-entrypoint-initdb.d/migrations/99-realtime.sql:Z
      - ${volumes_path}/db/webhooks.sql:/docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql:Z
      - ${volumes_path}/db/roles.sql:/docker-entrypoint-initdb.d/init-scripts/99-roles.sql:Z
      - ${volumes_path}/db/jwt.sql:/docker-entrypoint-initdb.d/init-scripts/99-jwt.sql:Z
      - ${db_name}-db-data:/var/lib/postgresql/data:Z
      - ${volumes_path}/db/_supabase.sql:/docker-entrypoint-initdb.d/migrations/97-_supabase.sql:Z
      - ${volumes_path}/db/logs.sql:/docker-entrypoint-initdb.d/migrations/99-logs.sql:Z
      - ${volumes_path}/db/pooler.sql:/docker-entrypoint-initdb.d/migrations/99-pooler.sql:Z
      - ${db_name}-db-config:/etc/postgresql-custom
    environment:
      POSTGRES_HOST: /var/run/postgresql
      POSTGRES_PORT: 5432
      POSTGRES_PASSWORD: ${postgres_pass}
      POSTGRES_DB: postgres
      JWT_SECRET: ${jwt_secret}
      JWT_EXP: 3600
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres", "-h", "localhost"]
      interval: 5s
      timeout: 5s
      retries: 10
    command:
      - postgres
      - -c
      - config_file=/etc/postgresql/postgresql.conf
      - -c
      - log_min_messages=fatal
EOF

    # Add vector dependency only in full mode (use service_started instead of healthy since vector healthcheck can be flaky)
    if [ "$db_mode" = "full" ]; then
        cat >> "$compose_file" << EOF
    depends_on:
      ${db_name}-vector:
        condition: service_started
EOF
    fi

    # Kong entrypoint command with proper escaping
    local kong_entrypoint_cmd="bash -c 'eval \"echo \\\"\$(cat ~/temp.yml)\\\"\" > ~/kong.yml && /docker-entrypoint.sh kong docker-start'"
    
    cat >> "$compose_file" << EOF

  ${db_name}-kong:
    container_name: ${db_name}-kong
    image: kong:2.8.1
    restart: unless-stopped
    ports:
      - "${kong_http_port}:8000"
      - "${kong_https_port}:8443"
    volumes:
      - ${volumes_path}/api/kong.yml:/home/kong/temp.yml:ro,z
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /home/kong/kong.yml
      KONG_DNS_ORDER: LAST,A,CNAME
      KONG_PLUGINS: request-transformer,cors,key-auth,acl,basic-auth,request-termination,ip-restriction
      SUPABASE_ANON_KEY: ${anon_key}
      SUPABASE_SERVICE_KEY: ${service_key}
      DASHBOARD_USERNAME: ${DASHBOARD_USERNAME:-supabase}
      DASHBOARD_PASSWORD: ${DASHBOARD_PASSWORD:-supabase}
    entrypoint: ${kong_entrypoint_cmd}
    depends_on:
      ${db_name}-db:
        condition: service_healthy

  ${db_name}-auth:
    container_name: ${db_name}-auth
    image: supabase/gotrue:v2.182.1
    restart: unless-stopped
    environment:
      GOTRUE_API_HOST: 0.0.0.0
      GOTRUE_API_PORT: 9999
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://supabase_auth_admin:${postgres_pass}@${db_name}-db:5432/postgres
      GOTRUE_SITE_URL: http://localhost:${studio_port}
      API_EXTERNAL_URL: http://localhost:${kong_http_port}
      GOTRUE_JWT_SECRET: ${jwt_secret}
      GOTRUE_JWT_EXP: 3600
    depends_on:
      ${db_name}-db:
        condition: service_healthy

  ${db_name}-rest:
    container_name: ${db_name}-rest
    image: postgrest/postgrest:v13.0.7
    restart: unless-stopped
    environment:
      PGRST_DB_URI: postgres://authenticator:${postgres_pass}@${db_name}-db:5432/postgres
      PGRST_DB_SCHEMAS: public,storage,graphql_public
      PGRST_DB_ANON_ROLE: anon
      PGRST_JWT_SECRET: ${jwt_secret}
    depends_on:
      ${db_name}-db:
        condition: service_healthy

  ${db_name}-studio:
    container_name: ${db_name}-studio
    image: supabase/studio:2025.11.10-sha-5291fe3
    restart: unless-stopped
    ports:
      - "${studio_port}:3000"
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://localhost:3000/api/platform/profile').then((r) => {if (r.status !== 200) throw new Error(r.status)})"
        ]
      timeout: 10s
      interval: 5s
      retries: 3
    depends_on:
      ${db_name}-db:
        condition: service_healthy
    environment:
      HOSTNAME: "::"
      STUDIO_PG_META_URL: http://${db_name}-meta:8080
      POSTGRES_PORT: ${postgres_port}
      POSTGRES_HOST: ${db_name}-db
      POSTGRES_DB: postgres
      POSTGRES_PASSWORD: ${postgres_pass}
      PG_META_CRYPTO_KEY: ${PG_META_CRYPTO_KEY}
      DEFAULT_ORGANIZATION_NAME: ${STUDIO_DEFAULT_ORGANIZATION}
      DEFAULT_PROJECT_NAME: ${db_name}
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      SUPABASE_URL: http://${db_name}-kong:8000
      SUPABASE_PUBLIC_URL: http://localhost:${kong_http_port}
      SUPABASE_ANON_KEY: ${anon_key}
      SUPABASE_SERVICE_KEY: ${service_key}
      AUTH_JWT_SECRET: ${jwt_secret}
      LOGFLARE_API_KEY: ${LOGFLARE_PUBLIC_ACCESS_TOKEN}
      LOGFLARE_PUBLIC_ACCESS_TOKEN: ${LOGFLARE_PUBLIC_ACCESS_TOKEN}
      LOGFLARE_PRIVATE_ACCESS_TOKEN: ${LOGFLARE_PRIVATE_ACCESS_TOKEN}
      LOGFLARE_URL: http://${db_name}-analytics:4000
      NEXT_PUBLIC_ENABLE_LOGS: true
      NEXT_ANALYTICS_BACKEND_PROVIDER: postgres

  ${db_name}-meta:
    container_name: ${db_name}-meta
    image: supabase/postgres-meta:v0.93.1
    restart: unless-stopped
    depends_on:
      ${db_name}-db:
        condition: service_healthy
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: ${db_name}-db
      PG_META_DB_PORT: 5432
      PG_META_DB_NAME: postgres
      PG_META_DB_USER: supabase_admin
      PG_META_DB_PASSWORD: ${postgres_pass}
      CRYPTO_KEY: ${PG_META_CRYPTO_KEY}

  ${db_name}-analytics:
    container_name: ${db_name}-analytics
    image: supabase/logflare:1.22.6
    restart: unless-stopped
    healthcheck:
      test:
        [
          "CMD",
          "curl",
          "http://localhost:4000/health"
        ]
      timeout: 5s
      interval: 5s
      retries: 10
    depends_on:
      ${db_name}-db:
        condition: service_healthy
    environment:
      LOGFLARE_NODE_HOST: 127.0.0.1
      DB_USERNAME: supabase_admin
      DB_DATABASE: _supabase
      DB_HOSTNAME: ${db_name}-db
      DB_PORT: 5432
      DB_PASSWORD: ${postgres_pass}
      DB_SCHEMA: _analytics
      LOGFLARE_PUBLIC_ACCESS_TOKEN: ${LOGFLARE_PUBLIC_ACCESS_TOKEN}
      LOGFLARE_PRIVATE_ACCESS_TOKEN: ${LOGFLARE_PRIVATE_ACCESS_TOKEN}
      LOGFLARE_SINGLE_TENANT: true
      LOGFLARE_SUPABASE_MODE: true
      POSTGRES_BACKEND_URL: postgresql://supabase_admin:${postgres_pass}@${db_name}-db:5432/_supabase
      POSTGRES_BACKEND_SCHEMA: _analytics
      LOGFLARE_FEATURE_FLAG_OVERRIDE: multibackend=true

EOF

    # Add full services only if db_mode=full
    if [ "$db_mode" = "full" ]; then
        cat >> "$compose_file" << EOF

  ${db_name}-realtime:
    container_name: ${db_name}-realtime
    image: supabase/realtime:v2.63.0
    restart: unless-stopped
    depends_on:
      ${db_name}-db:
        condition: service_healthy
      ${db_name}-analytics:
        condition: service_healthy
    healthcheck:
      test:
        [
          "CMD",
          "curl",
          "-sSfL",
          "--head",
          "-o",
          "/dev/null",
          "-H",
          "Authorization: Bearer ${anon_key}",
          "http://localhost:4000/api/tenants/realtime-dev/health"
        ]
      timeout: 5s
      interval: 5s
      retries: 3
    environment:
      PORT: 4000
      DB_HOST: ${db_name}-db
      DB_PORT: 5432
      DB_USER: supabase_admin
      DB_PASSWORD: ${postgres_pass}
      DB_NAME: postgres
      DB_AFTER_CONNECT_QUERY: 'SET search_path TO _realtime'
      DB_ENC_KEY: supabaserealtime
      API_JWT_SECRET: ${jwt_secret}
      SECRET_KEY_BASE: ${SECRET_KEY_BASE:-UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq}
      ERL_AFLAGS: -proto_dist inet_tcp
      DNS_NODES: "''"
      RLIMIT_NOFILE: "10000"
      APP_NAME: realtime
      SEED_SELF_HOST: true
      RUN_JANITOR: true

  ${db_name}-storage:
    container_name: ${db_name}-storage
    image: supabase/storage-api:v1.29.0
    restart: unless-stopped
    volumes:
      - ${db_name}-storage-data:/var/lib/storage:z
    healthcheck:
      test:
        [
          "CMD",
          "wget",
          "--no-verbose",
          "--tries=1",
          "--spider",
          "http://storage:5000/status"
        ]
      timeout: 5s
      interval: 5s
      retries: 3
    depends_on:
      ${db_name}-db:
        condition: service_healthy
      ${db_name}-rest:
        condition: service_started
      ${db_name}-imgproxy:
        condition: service_started
    environment:
      ANON_KEY: ${anon_key}
      SERVICE_KEY: ${service_key}
      POSTGREST_URL: http://${db_name}-rest:3000
      PGRST_JWT_SECRET: ${jwt_secret}
      DATABASE_URL: postgres://supabase_storage_admin:${postgres_pass}@${db_name}-db:5432/postgres
      FILE_SIZE_LIMIT: 52428800
      STORAGE_BACKEND: file
      FILE_STORAGE_BACKEND_PATH: /var/lib/storage
      TENANT_ID: stub
      REGION: stub
      GLOBAL_S3_BUCKET: stub
      ENABLE_IMAGE_TRANSFORMATION: "true"
      IMGPROXY_URL: http://${db_name}-imgproxy:5001

  ${db_name}-imgproxy:
    container_name: ${db_name}-imgproxy
    image: darthsim/imgproxy:v3.8.0
    restart: unless-stopped
    volumes:
      - ${db_name}-storage-data:/var/lib/storage:z
    healthcheck:
      test:
        [
          "CMD",
          "imgproxy",
          "health"
        ]
      timeout: 5s
      interval: 5s
      retries: 3
    environment:
      IMGPROXY_BIND: ":5001"
      IMGPROXY_LOCAL_FILESYSTEM_ROOT: /
      IMGPROXY_USE_ETAG: "true"
      IMGPROXY_ENABLE_WEBP_DETECTION: ${IMGPROXY_ENABLE_WEBP_DETECTION}

  ${db_name}-functions:
    container_name: ${db_name}-edge-functions
    image: supabase/edge-runtime:v1.69.23
    restart: unless-stopped
    volumes:
      - ${volumes_path}/functions:/home/deno/functions:Z
    depends_on:
      ${db_name}-analytics:
        condition: service_healthy
    environment:
      JWT_SECRET: ${jwt_secret}
      SUPABASE_URL: http://${db_name}-kong:8000
      SUPABASE_ANON_KEY: ${anon_key}
      SUPABASE_SERVICE_ROLE_KEY: ${service_key}
      SUPABASE_DB_URL: postgresql://postgres:${postgres_pass}@${db_name}-db:5432/postgres
      VERIFY_JWT: "${FUNCTIONS_VERIFY_JWT}"
    command:
      [
        "start",
        "--main-service",
        "/home/deno/functions/main"
      ]

  ${db_name}-vector:
    container_name: ${db_name}-vector
    image: timberio/vector:0.28.1-alpine
    restart: unless-stopped
    volumes:
      - ${volumes_path}/logs/vector.yml:/etc/vector/vector.yml:ro,z
      - ${DOCKER_SOCKET_LOCATION:-/var/run/docker.sock}:/var/run/docker.sock:ro,z
    healthcheck:
      test:
        [
          "CMD",
          "wget",
          "--no-verbose",
          "--tries=1",
          "--spider",
          "http://vector:9001/health"
        ]
      timeout: 5s
      interval: 5s
      retries: 3
    environment:
      LOGFLARE_PUBLIC_ACCESS_TOKEN: ${LOGFLARE_PUBLIC_ACCESS_TOKEN:-your-super-secret-and-long-logflare-key-public}
    command:
      [
        "--config",
        "/etc/vector/vector.yml"
      ]
    security_opt:
      - "label=disable"

  ${db_name}-supavisor:
    container_name: ${db_name}-pooler
    image: supabase/supavisor:2.7.4
    restart: unless-stopped
    ports:
      - "${pooler_port}:6543"
    volumes:
      - ${volumes_path}/pooler/pooler.exs:/etc/pooler/pooler.exs:ro,z
    healthcheck:
      test:
        [
          "CMD",
          "curl",
          "-sSfL",
          "--head",
          "-o",
          "/dev/null",
          "http://127.0.0.1:4000/api/health"
        ]
      interval: 10s
      timeout: 5s
      retries: 5
    depends_on:
      ${db_name}-db:
        condition: service_healthy
      ${db_name}-analytics:
        condition: service_healthy
    environment:
      PORT: 4000
      POSTGRES_PORT: 5432
      POSTGRES_DB: postgres
      POSTGRES_PASSWORD: ${postgres_pass}
      DATABASE_URL: ecto://supabase_admin:${postgres_pass}@${db_name}-db:5432/_supabase
      CLUSTER_POSTGRES: true
      SECRET_KEY_BASE: ${SECRET_KEY_BASE:-UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq}
      VAULT_ENC_KEY: ${VAULT_ENC_KEY:-your-encryption-key-32-chars-min}
      API_JWT_SECRET: ${jwt_secret}
      METRICS_JWT_SECRET: ${jwt_secret}
      REGION: local
      ERL_AFLAGS: -proto_dist inet_tcp
      POOLER_TENANT_ID: ${db_name}-tenant
      POOLER_DEFAULT_POOL_SIZE: ${POOLER_DEFAULT_POOL_SIZE:-20}
      POOLER_MAX_CLIENT_CONN: ${POOLER_MAX_CLIENT_CONN:-100}
      POOLER_POOL_MODE: transaction
      DB_POOL_SIZE: ${POOLER_DB_POOL_SIZE:-5}
    command:
      [
        "/bin/sh",
        "-c",
        "/app/bin/migrate && /app/bin/supavisor eval \"\$(cat /etc/pooler/pooler.exs)\" && /app/bin/server"
      ]

EOF
    fi

    cat >> "$compose_file" << EOF

volumes:
  ${db_name}-db-data:
  ${db_name}-db-config:
  ${db_name}-storage-data:

EOF

    echo "Generated docker-compose.yml for ${db_name}"
}

# Generate compose files for all databases or specific database
studio_port_base=3000
db_index=0

while IFS='|' read -r db_name postgres_port kong_http_port kong_https_port pooler_port cpu_limit memory_limit postgres_pass jwt_secret anon_key service_key rest; do
    [[ "$db_name" =~ ^#.*$ ]] && continue
    [[ -z "$db_name" ]] && continue
    # Stop at global config section (lines with = are config variables, not database entries)
    [[ "$db_name" =~ = ]] && break
    [[ "$db_name" == "DASHBOARD_USERNAME" ]] && break
    
    # If TARGET_DB is set, only generate for that database
    if [ -n "$TARGET_DB" ] && [ "$db_name" != "$TARGET_DB" ]; then
        ((db_index++))
        continue
    fi
    
    studio_port=$((studio_port_base + db_index))
    
    # Determine if this database needs full services
    db_dir="${SCRIPT_DIR}/databases/${db_name}"
    db_mode="$FULL_SERVICES"
    if [ -f "${db_dir}/.env" ] && grep -q "FULL mode" "${db_dir}/.env" 2>/dev/null; then
        db_mode="full"
    fi
    
    generate_db_compose "$db_name" "$postgres_port" "$kong_http_port" "$kong_https_port" "$pooler_port" "$cpu_limit" "$memory_limit" "$postgres_pass" "$jwt_secret" "$anon_key" "$service_key" "$studio_port" "$db_mode"
    
    ((db_index++))
done < "$CENTRAL_ENV"

echo "docker-compose.yml files generated successfully"
