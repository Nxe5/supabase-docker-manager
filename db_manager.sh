#!/bin/bash

# Comprehensive Database Management Script
# Handles: add, add-full, remove, show ports, update resources, validate
# Usage: ./db_manager.sh <command> [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENTRAL_ENV="${SCRIPT_DIR}/databases.env"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
# Use supabase/docker as template if supabase-project doesn't exist
if [ -d "${SCRIPT_DIR}/supabase-project" ]; then
    TEMPLATE_DIR="${SCRIPT_DIR}/supabase-project"
elif [ -d "${SCRIPT_DIR}/supabase/docker" ]; then
    TEMPLATE_DIR="${SCRIPT_DIR}/supabase/docker"
else
    TEMPLATE_DIR="${SCRIPT_DIR}/supabase-project"
    print_error "Template directory not found. Please ensure supabase-project/ or supabase/docker/ exists."
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() { echo -e "${RED}✗ $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }
print_header() { echo -e "${BLUE}▶ $1${NC}"; }

# Generate random password
generate_password() { openssl rand -base64 32 | tr -d "=+/" | cut -c1-32; }

# Find next available ports
find_next_ports() {
    local max_postgres=5431 max_kong_http=7999 max_kong_https=8442 max_pooler=6542
    
    while IFS='|' read -r name postgres_port kong_http_port kong_https_port pooler_port rest; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [[ -z "$name" ]] && continue
        [[ "$name" == "DASHBOARD_USERNAME" ]] && break
        
        [ "$postgres_port" -gt "$max_postgres" ] 2>/dev/null && max_postgres=$postgres_port
        [ "$kong_http_port" -gt "$max_kong_http" ] 2>/dev/null && max_kong_http=$kong_http_port
        [ "$kong_https_port" -gt "$max_kong_https" ] 2>/dev/null && max_kong_https=$kong_https_port
        [ "$pooler_port" -gt "$max_pooler" ] 2>/dev/null && max_pooler=$pooler_port
    done < "$CENTRAL_ENV"
    
    echo "$((max_postgres + 1))|$((max_kong_http + 1))|$((max_kong_https + 1))|$((max_pooler + 1))"
}

# Generate docker-compose.yml from databases.env
# Usage: generate_compose [mode] [db_name]
# If db_name is provided, only generates for that database
generate_compose() {
    local mode="${1:-lean}"
    local db_name="${2:-}"
    if [ -n "$db_name" ]; then
        print_info "Generating docker-compose.yml for $db_name (mode: $mode)..."
        "${SCRIPT_DIR}/helpers/generate_compose.sh" "$mode" "$db_name" && print_success "docker-compose.yml generated for $db_name"
    else
        print_info "Generating docker-compose.yml files for all databases (mode: $mode)..."
        "${SCRIPT_DIR}/helpers/generate_compose.sh" "$mode" && print_success "docker-compose.yml files generated"
    fi
}

# Add database (lean - essential services only)
cmd_add() {
    local db_name="$1"
    local cpu_limit="${2:-2.0}"
    local memory_limit="${3:-2g}"
    local full_mode=false
    
    [[ -z "$db_name" ]] && { print_error "Database name required"; exit 1; }
    [[ ! "$db_name" =~ ^[a-zA-Z0-9-]+$ ]] && { print_error "Invalid database name"; exit 1; }
    
    grep -q "^${db_name}|" "$CENTRAL_ENV" && { print_error "Database already exists"; exit 1; }
    
    print_header "Adding database: $db_name"
    
    IFS='|' read -r postgres_port kong_http_port kong_https_port pooler_port <<< "$(find_next_ports)"
    
    local postgres_pass=$(generate_password)
    local jwt_secret=$(generate_password)
    local anon_key="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE"
    local service_key="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q"
    
    local entry="${db_name}|${postgres_port}|${kong_http_port}|${kong_https_port}|${pooler_port}|${cpu_limit}|${memory_limit}|${postgres_pass}|${jwt_secret}|${anon_key}|${service_key}"
    
    # Calculate studio port BEFORE adding entry (3000 + number of existing databases)
    local db_count=$(grep -c "^[a-zA-Z0-9-]\+|" "$CENTRAL_ENV" 2>/dev/null | head -1 || echo "0")
    db_count=${db_count:-0}
    local studio_port=$((3000 + db_count))
    
    # Add entry to databases.env
    print_info "Adding entry to databases.env..."
    sed -i.bak "/^DASHBOARD_USERNAME/i\\
${entry}
" "$CENTRAL_ENV" && rm -f "${CENTRAL_ENV}.bak"
    print_success "Entry added to databases.env"
    
    # Create database directory in databases/ folder
    local db_dir="${SCRIPT_DIR}/databases/${db_name}"
    if [ -d "$db_dir" ]; then
        print_info "Directory '$db_dir' already exists, skipping creation"
    else
        print_info "Creating database directory: $db_dir"
        mkdir -p "$db_dir"
        
        # Copy template files
        if [ -d "$TEMPLATE_DIR" ]; then
            print_info "Copying template files..."
            cp -r "${TEMPLATE_DIR}/docker-compose.yml" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/docker-compose.s3.yml" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/reset.sh" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/README.md" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/versions.md" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/CHANGELOG.md" "$db_dir/" 2>/dev/null || true
            
            # Copy volumes directory structure
            print_info "Copying volumes directory..."
            mkdir -p "${db_dir}/volumes"
            cp -r "${TEMPLATE_DIR}/volumes/api" "${db_dir}/volumes/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/volumes/functions" "${db_dir}/volumes/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/volumes/logs" "${db_dir}/volumes/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/volumes/pooler" "${db_dir}/volumes/" 2>/dev/null || true
            mkdir -p "${db_dir}/volumes/db"
            mkdir -p "${db_dir}/volumes/storage"
            
            # Copy database init files
            if [ -d "${TEMPLATE_DIR}/volumes/db" ]; then
                cp "${TEMPLATE_DIR}/volumes/db"/*.sql "${db_dir}/volumes/db/" 2>/dev/null || true
            fi
            
            # Copy dev directory if it exists
            if [ -d "${TEMPLATE_DIR}/dev" ]; then
                cp -r "${TEMPLATE_DIR}/dev" "${db_dir}/" 2>/dev/null || true
            fi
            
            print_success "Template files copied"
        else
            print_info "Template directory not found, skipping file copy"
        fi
        
        # Generate database-specific .env file
        print_info "Generating database-specific .env file..."
        local env_file="${db_dir}/.env"
        
        cat > "$env_file" << EOF
# Database resource limits
DB_CPU_LIMIT=${cpu_limit}
DB_MEMORY_LIMIT=${memory_limit}

############
# Database: $db_name
# Generated by db_manager.sh
############

POSTGRES_PASSWORD=${postgres_pass}
JWT_SECRET=${jwt_secret}
ANON_KEY=${anon_key}
SERVICE_ROLE_KEY=${service_key}

POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=${postgres_port}

POOLER_PROXY_PORT_TRANSACTION=${pooler_port}
POOLER_DEFAULT_POOL_SIZE=20
POOLER_MAX_CLIENT_CONN=100
POOLER_TENANT_ID=${db_name}-tenant
POOLER_DB_POOL_SIZE=5

KONG_HTTP_PORT=${kong_http_port}
KONG_HTTPS_PORT=${kong_https_port}

PGRST_DB_SCHEMAS=public,storage,graphql_public

SITE_URL=http://localhost:3000
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=http://localhost:${kong_http_port}

MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify
MAILER_URLPATHS_INVITE=/auth/v1/verify
MAILER_URLPATHS_RECOVERY=/auth/v1/verify
MAILER_URLPATHS_EMAIL_CHANGE=/auth/v1/verify

ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=false
SMTP_ADMIN_EMAIL=admin@example.com
SMTP_HOST=supabase-mail
SMTP_PORT=2500
SMTP_USER=fake_mail_user
SMTP_PASS=fake_mail_password
SMTP_SENDER_NAME=fake_sender
ENABLE_ANONYMOUS_USERS=false

ENABLE_PHONE_SIGNUP=true
ENABLE_PHONE_AUTOCONFIRM=true

STUDIO_DEFAULT_ORGANIZATION="Default Organization"
STUDIO_DEFAULT_PROJECT=${db_name}
SUPABASE_PUBLIC_URL=http://localhost:${kong_http_port}

FUNCTIONS_VERIFY_JWT=false

LOGFLARE_PUBLIC_ACCESS_TOKEN=your-super-secret-and-long-logflare-key-public
LOGFLARE_PRIVATE_ACCESS_TOKEN=your-super-secret-and-long-logflare-key-private
DOCKER_SOCKET_LOCATION=/var/run/docker.sock

GOOGLE_PROJECT_ID=GOOGLE_PROJECT_ID
GOOGLE_PROJECT_NUMBER=GOOGLE_PROJECT_NUMBER

IMGPROXY_ENABLE_WEBP_DETECTION=true

OPENAI_API_KEY=

DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=this_password_is_insecure_and_should_be_updated
SECRET_KEY_BASE=UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq
VAULT_ENC_KEY=your-encryption-key-32-chars-min
PG_META_CRYPTO_KEY=your-encryption-key-32-chars-min

############
# External Connection URLs
# Use these URLs to connect from external applications
############

# PostgreSQL direct connection
DATABASE_URL=postgresql://postgres:${postgres_pass}@localhost:${postgres_port}/postgres
POSTGRES_URL=postgresql://postgres:${postgres_pass}@localhost:${postgres_port}/postgres

# Connection pooler (recommended for production)
POOLER_URL=postgresql://postgres:${postgres_pass}@localhost:${pooler_port}/postgres
DATABASE_POOLER_URL=postgresql://postgres:${postgres_pass}@localhost:${pooler_port}/postgres

# Supabase API endpoints
SUPABASE_URL=http://localhost:${kong_http_port}
API_URL=http://localhost:${kong_http_port}
REST_API_URL=http://localhost:${kong_http_port}/rest/v1/
AUTH_API_URL=http://localhost:${kong_http_port}/auth/v1/
STORAGE_API_URL=http://localhost:${kong_http_port}/storage/v1/
REALTIME_URL=ws://localhost:${kong_http_port}/realtime/v1/
FUNCTIONS_URL=http://localhost:${kong_http_port}/functions/v1/

# Studio web dashboard
STUDIO_URL=http://localhost:${studio_port}
EOF
        
        print_success "Database directory and .env file created"
    fi
    
    # Generate docker-compose.yml for this database (lean mode)
    generate_compose "lean" "$db_name"
    
    print_success "Database '$db_name' added successfully!"
    print_info "Directory: $db_dir"
    print_info "Ports: POSTGRES=$postgres_port, KONG_HTTP=$kong_http_port, KONG_HTTPS=$kong_https_port, POOLER=$pooler_port"
    print_info "To start: docker compose up -d ${db_name}-db ${db_name}-kong"
    print_info "Note: Added in lean mode (essential services only)"
    print_info "Use 'add-full' command to include all services (realtime, storage, functions, etc.)"
}

# Add database with full services
cmd_add_full() {
    local db_name="$1"
    local cpu_limit="${2:-2.0}"
    local memory_limit="${3:-2g}"
    
    [[ -z "$db_name" ]] && { print_error "Database name required"; exit 1; }
    [[ ! "$db_name" =~ ^[a-zA-Z0-9-]+$ ]] && { print_error "Invalid database name"; exit 1; }
    
    grep -q "^${db_name}|" "$CENTRAL_ENV" && { print_error "Database already exists"; exit 1; }
    
    print_header "Adding database (FULL): $db_name"
    
    IFS='|' read -r postgres_port kong_http_port kong_https_port pooler_port <<< "$(find_next_ports)"
    
    local postgres_pass=$(generate_password)
    local jwt_secret=$(generate_password)
    local anon_key="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE"
    local service_key="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q"
    
    local entry="${db_name}|${postgres_port}|${kong_http_port}|${kong_https_port}|${pooler_port}|${cpu_limit}|${memory_limit}|${postgres_pass}|${jwt_secret}|${anon_key}|${service_key}"
    
    # Calculate studio port BEFORE adding entry (3000 + number of existing databases)
    local db_count=$(grep -c "^[a-zA-Z0-9-]\+|" "$CENTRAL_ENV" 2>/dev/null | head -1 || echo "0")
    db_count=${db_count:-0}
    local studio_port=$((3000 + db_count))
    
    # Add entry to databases.env
    print_info "Adding entry to databases.env..."
    sed -i.bak "/^DASHBOARD_USERNAME/i\\
${entry}
" "$CENTRAL_ENV" && rm -f "${CENTRAL_ENV}.bak"
    print_success "Entry added to databases.env"
    
    # Create database directory (same as cmd_add)
    local db_dir="${SCRIPT_DIR}/databases/${db_name}"
    if [ -d "$db_dir" ]; then
        print_info "Directory '$db_dir' already exists, skipping creation"
    else
        print_info "Creating database directory: $db_dir"
        mkdir -p "$db_dir"
        
        # Copy template files
        if [ -d "$TEMPLATE_DIR" ]; then
            print_info "Copying template files..."
            cp -r "${TEMPLATE_DIR}/docker-compose.yml" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/docker-compose.s3.yml" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/reset.sh" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/README.md" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/versions.md" "$db_dir/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/CHANGELOG.md" "$db_dir/" 2>/dev/null || true
            
            # Copy volumes directory structure
            print_info "Copying volumes directory..."
            mkdir -p "${db_dir}/volumes"
            cp -r "${TEMPLATE_DIR}/volumes/api" "${db_dir}/volumes/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/volumes/functions" "${db_dir}/volumes/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/volumes/logs" "${db_dir}/volumes/" 2>/dev/null || true
            cp -r "${TEMPLATE_DIR}/volumes/pooler" "${db_dir}/volumes/" 2>/dev/null || true
            mkdir -p "${db_dir}/volumes/db"
            mkdir -p "${db_dir}/volumes/storage"
            
            # Copy database init files
            if [ -d "${TEMPLATE_DIR}/volumes/db" ]; then
                cp "${TEMPLATE_DIR}/volumes/db"/*.sql "${db_dir}/volumes/db/" 2>/dev/null || true
            fi
            
            # Copy dev directory if it exists
            if [ -d "${TEMPLATE_DIR}/dev" ]; then
                cp -r "${TEMPLATE_DIR}/dev" "${db_dir}/" 2>/dev/null || true
            fi
            
            print_success "Template files copied"
        else
            print_info "Template directory not found, skipping file copy"
        fi
        
        # Generate database-specific .env file
        print_info "Generating database-specific .env file..."
        local env_file="${db_dir}/.env"
        
        cat > "$env_file" << EOF
# Database resource limits
DB_CPU_LIMIT=${cpu_limit}
DB_MEMORY_LIMIT=${memory_limit}

############
# Database: $db_name
# Generated by db_manager.sh (FULL mode)
############

POSTGRES_PASSWORD=${postgres_pass}
JWT_SECRET=${jwt_secret}
ANON_KEY=${anon_key}
SERVICE_ROLE_KEY=${service_key}

POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=${postgres_port}

POOLER_PROXY_PORT_TRANSACTION=${pooler_port}
POOLER_DEFAULT_POOL_SIZE=20
POOLER_MAX_CLIENT_CONN=100
POOLER_TENANT_ID=${db_name}-tenant
POOLER_DB_POOL_SIZE=5

KONG_HTTP_PORT=${kong_http_port}
KONG_HTTPS_PORT=${kong_https_port}

PGRST_DB_SCHEMAS=public,storage,graphql_public

SITE_URL=http://localhost:3000
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=http://localhost:${kong_http_port}

MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify
MAILER_URLPATHS_INVITE=/auth/v1/verify
MAILER_URLPATHS_RECOVERY=/auth/v1/verify
MAILER_URLPATHS_EMAIL_CHANGE=/auth/v1/verify

ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=false
SMTP_ADMIN_EMAIL=admin@example.com
SMTP_HOST=supabase-mail
SMTP_PORT=2500
SMTP_USER=fake_mail_user
SMTP_PASS=fake_mail_password
SMTP_SENDER_NAME=fake_sender
ENABLE_ANONYMOUS_USERS=false

ENABLE_PHONE_SIGNUP=true
ENABLE_PHONE_AUTOCONFIRM=true

STUDIO_DEFAULT_ORGANIZATION="Default Organization"
STUDIO_DEFAULT_PROJECT=${db_name}
SUPABASE_PUBLIC_URL=http://localhost:${kong_http_port}

FUNCTIONS_VERIFY_JWT=false

LOGFLARE_PUBLIC_ACCESS_TOKEN=your-super-secret-and-long-logflare-key-public
LOGFLARE_PRIVATE_ACCESS_TOKEN=your-super-secret-and-long-logflare-key-private
DOCKER_SOCKET_LOCATION=/var/run/docker.sock

GOOGLE_PROJECT_ID=GOOGLE_PROJECT_ID
GOOGLE_PROJECT_NUMBER=GOOGLE_PROJECT_NUMBER

IMGPROXY_ENABLE_WEBP_DETECTION=true

OPENAI_API_KEY=

DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=this_password_is_insecure_and_should_be_updated
SECRET_KEY_BASE=UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq
VAULT_ENC_KEY=your-encryption-key-32-chars-min
PG_META_CRYPTO_KEY=your-encryption-key-32-chars-min

############
# External Connection URLs
# Use these URLs to connect from external applications
############

# PostgreSQL direct connection
DATABASE_URL=postgresql://postgres:${postgres_pass}@localhost:${postgres_port}/postgres
POSTGRES_URL=postgresql://postgres:${postgres_pass}@localhost:${postgres_port}/postgres

# Connection pooler (recommended for production)
POOLER_URL=postgresql://postgres:${postgres_pass}@localhost:${pooler_port}/postgres
DATABASE_POOLER_URL=postgresql://postgres:${postgres_pass}@localhost:${pooler_port}/postgres

# Supabase API endpoints
SUPABASE_URL=http://localhost:${kong_http_port}
API_URL=http://localhost:${kong_http_port}
REST_API_URL=http://localhost:${kong_http_port}/rest/v1/
AUTH_API_URL=http://localhost:${kong_http_port}/auth/v1/
STORAGE_API_URL=http://localhost:${kong_http_port}/storage/v1/
REALTIME_URL=ws://localhost:${kong_http_port}/realtime/v1/
FUNCTIONS_URL=http://localhost:${kong_http_port}/functions/v1/

# Studio web dashboard
STUDIO_URL=http://localhost:${studio_port}
EOF
        
        print_success "Database directory and .env file created"
    fi
    
    # Generate docker-compose.yml for this database (full mode)
    generate_compose "full" "$db_name"
    
    print_success "Database '$db_name' added successfully (FULL mode - all services)!"
    print_info "Directory: $db_dir"
    print_info "Ports: POSTGRES=$postgres_port, KONG_HTTP=$kong_http_port, KONG_HTTPS=$kong_https_port, POOLER=$pooler_port"
    print_info "To start: docker compose up -d ${db_name}-db ${db_name}-kong"
}

# Remove database
cmd_remove() {
    local db_name="$1"
    [[ -z "$db_name" ]] && { print_error "Database name required"; exit 1; }
    
    grep -q "^${db_name}|" "$CENTRAL_ENV" || { print_error "Database not found"; exit 1; }
    
    print_header "Removing database: $db_name"
    
    # Confirm removal
    read -p "Are you sure you want to remove '$db_name'? This will remove it from databases.env and regenerate docker-compose.yml (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removal cancelled"
        return 0
    fi
    
    # Remove from databases.env
    print_info "Removing from databases.env..."
    sed -i.bak "/^${db_name}|/d" "$CENTRAL_ENV" && rm -f "${CENTRAL_ENV}.bak"
    print_success "Entry removed from databases.env"
    
    # Remove database directory automatically
    local db_dir="${SCRIPT_DIR}/databases/${db_name}"
    if [ -d "$db_dir" ]; then
        print_info "Removing directory: $db_dir"
        rm -rf "$db_dir"
        print_success "Directory removed"
    fi
    
    # Stop and remove containers using database-specific compose file
    local compose_file="${SCRIPT_DIR}/databases/${db_name}/docker-compose.yml"
    if [ -f "$compose_file" ]; then
        print_info "Stopping containers..."
        docker compose -f "$compose_file" down -v 2>/dev/null || true
        print_success "Containers and volumes removed"
    else
        # Fallback: try to stop/remove by name
        print_info "Stopping containers (fallback method)..."
        docker compose stop ${db_name}-db ${db_name}-kong ${db_name}-auth ${db_name}-rest ${db_name}-studio ${db_name}-meta ${db_name}-analytics ${db_name}-realtime ${db_name}-storage ${db_name}-imgproxy ${db_name}-functions ${db_name}-vector ${db_name}-supavisor 2>/dev/null || true
        docker compose rm -f ${db_name}-db ${db_name}-kong ${db_name}-auth ${db_name}-rest ${db_name}-studio ${db_name}-meta ${db_name}-analytics ${db_name}-realtime ${db_name}-storage ${db_name}-imgproxy ${db_name}-functions ${db_name}-vector ${db_name}-supavisor 2>/dev/null || true
        
        # Remove volumes to ensure clean state on recreation
        print_info "Removing volumes..."
        docker volume rm ${db_name}_${db_name}-db-data ${db_name}_${db_name}-db-config ${db_name}_${db_name}-storage-data 2>/dev/null || true
        docker volume rm ${db_name}-db-data ${db_name}-db-config ${db_name}-storage-data 2>/dev/null || true
        print_success "Volumes removed"
    fi
    
    print_success "Database '$db_name' removed successfully (including containers and volumes)"
}

# Remove all databases
cmd_remove_all() {
    print_header "Removing ALL databases"
    print_error "WARNING: This will remove ALL databases from databases.env and delete ALL database directories!"
    echo ""
    read -p "Are you absolutely sure? Type 'DELETE ALL' to confirm: " confirm
    echo
    
    if [ "$confirm" != "DELETE ALL" ]; then
        print_info "Removal cancelled"
        return 0
    fi
    
    # Get all database names
    local databases
    databases=$(grep -E "^[^#].*\|" "$CENTRAL_ENV" | grep -v "^DASHBOARD_USERNAME" | grep -E "^[a-zA-Z0-9-]+\|" | cut -d'|' -f1)
    
    if [ -z "$databases" ]; then
        print_info "No databases found to remove"
        return 0
    fi
    
    print_info "Found databases to remove:"
    echo "$databases" | sed 's/^/  - /'
    echo ""
    
    read -p "Remove all database directories too? (y/N) " -n 1 -r
    echo
    local remove_dirs=false
    [[ $REPLY =~ ^[Yy]$ ]] && remove_dirs=true
    
    # Remove each database
    local removed=0
    local dirs_removed=0
    
    while IFS= read -r db_name; do
        [ -z "$db_name" ] && continue
        
        print_info "Removing: $db_name"
        
        # Remove from databases.env
        sed -i.bak "/^${db_name}|/d" "$CENTRAL_ENV" && rm -f "${CENTRAL_ENV}.bak"
        ((removed++))
        
        # Remove directory if requested
        if [ "$remove_dirs" = true ]; then
            local db_dir="${SCRIPT_DIR}/databases/${db_name}"
            if [ -d "$db_dir" ]; then
                print_info "  Removing directory: $db_dir"
                rm -rf "$db_dir"
                ((dirs_removed++))
            fi
        fi
    done <<< "$databases"
    
    # Note: Per-database compose files are automatically removed with their directories
    # No need to regenerate - remaining databases already have their compose files
    
    print_success "Removed $removed database(s) from databases.env"
    [ "$remove_dirs" = true ] && print_success "Removed $dirs_removed directory(ies)"
    print_info "Note: Docker containers and volumes are not automatically removed"
    print_info "To remove all containers: docker compose down"
    print_info "To remove all volumes: docker volume ls | grep -E '(db-data|db-config)' | awk '{print \$2}' | xargs docker volume rm"
}

# Show ports
cmd_show_ports() {
    print_header "Database Port Assignments"
    printf "%-25s %-12s %-12s %-12s %-12s %-12s\n" "DATABASE" "POSTGRES" "KONG_HTTP" "KONG_HTTPS" "POOLER" "STUDIO"
    echo "----------------------------------------------------------------------------------------"
    
    studio_port_base=3000
    db_index=0
    
    while IFS='|' read -r name postgres_port kong_http_port kong_https_port pooler_port rest; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [[ -z "$name" ]] && continue
        [[ "$name" == "DASHBOARD_USERNAME" ]] && break
        [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
        
        studio_port=$((studio_port_base + db_index))
        ((db_index++))
        
        printf "%-25s %-12s %-12s %-12s %-12s %-12s\n" "$name" "$postgres_port" "$kong_http_port" "$kong_https_port" "$pooler_port" "$studio_port"
    done < "$CENTRAL_ENV"
    echo ""
    print_info "Studio URLs: http://localhost:3000 (first DB), http://localhost:3001 (second DB), etc."
}

# Update resources
cmd_update_resources() {
    local db_name="$1"
    local cpu_limit="$2"
    local memory_limit="$3"
    
    [[ -z "$db_name" || -z "$cpu_limit" || -z "$memory_limit" ]] && {
        print_error "Usage: update-resources <db-name> <cpu> <memory>"; exit 1;
    }
    
    print_header "Updating resources for: $db_name"
    
    local temp_file=$(mktemp)
    # Preserve header comments (everything before first database entry)
    sed -n '1,/^[^#|]*|/p' "$CENTRAL_ENV" | sed '$d' >> "$temp_file"
    # Process database entries
    while IFS='|' read -r name postgres_port kong_http_port kong_https_port pooler_port cpu mem rest; do
        if [ "$name" == "$db_name" ]; then
            echo "${name}|${postgres_port}|${kong_http_port}|${kong_https_port}|${pooler_port}|${cpu_limit}|${memory_limit}|${rest}" >> "$temp_file"
        else
            echo "${name}|${postgres_port}|${kong_http_port}|${kong_https_port}|${pooler_port}|${cpu}|${mem}|${rest}" >> "$temp_file"
        fi
    done < <(grep -E "^[^#].*\|" "$CENTRAL_ENV" | grep -v "^DASHBOARD_USERNAME")
    # Preserve global config section (everything from DASHBOARD_USERNAME onwards)
    sed -n '/^DASHBOARD_USERNAME/,$p' "$CENTRAL_ENV" >> "$temp_file"
    mv "$temp_file" "$CENTRAL_ENV"
    
    # Regenerate compose files for all databases
    generate_compose "full"
    print_success "Resources updated"
}

# Validate
cmd_validate() {
    print_header "Validating databases.env"
    local errors=0
    
    while IFS='|' read -r name postgres_port kong_http_port kong_https_port pooler_port cpu mem rest; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [[ -z "$name" ]] && continue
        # Stop at global config section (lines with = are config variables, not database entries)
        [[ "$name" =~ = ]] && break
        [[ "$name" == "DASHBOARD_USERNAME" ]] && break
        
        # Only validate lines that look like database entries (contain only alphanumeric and dashes)
        [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
        
        # Expected format: name|postgres|kong_http|kong_https|pooler|cpu|mem|pass|jwt|anon|service (11 fields)
        field_count=$(echo "$name|$postgres_port|$kong_http_port|$kong_https_port|$pooler_port|$cpu|$mem|$rest" | tr '|' '\n' | wc -l | tr -d ' ')
        [ "$field_count" -ne 11 ] && {
            print_error "$name: Invalid field count ($field_count/11)"; ((errors++));
        }
    done < "$CENTRAL_ENV"
    
    [ $errors -eq 0 ] && print_success "Validation passed" || print_error "$errors error(s) found"
    return $errors
}

# Get all services for a database
# Note: This matches the services generated by generate_compose.sh
get_db_services() {
    local db_name="$1"
    local compose_file="${SCRIPT_DIR}/databases/${db_name}/docker-compose.yml"
    
    if [ ! -f "$compose_file" ]; then
        # Fallback: return all possible services
        echo "${db_name}-db ${db_name}-kong ${db_name}-auth ${db_name}-rest ${db_name}-studio ${db_name}-meta ${db_name}-analytics ${db_name}-realtime ${db_name}-storage ${db_name}-imgproxy ${db_name}-functions ${db_name}-vector ${db_name}-supavisor"
        return
    fi
    
    # Check if full services exist in database-specific docker-compose.yml
    if docker compose -f "$compose_file" config --services 2>/dev/null | grep -q "^${db_name}-realtime$"; then
        # Full mode - all services
        echo "${db_name}-db ${db_name}-kong ${db_name}-auth ${db_name}-rest ${db_name}-studio ${db_name}-meta ${db_name}-analytics ${db_name}-realtime ${db_name}-storage ${db_name}-imgproxy ${db_name}-functions ${db_name}-vector ${db_name}-supavisor"
    else
        # Lean mode - essential services only
        echo "${db_name}-db ${db_name}-kong ${db_name}-auth ${db_name}-rest ${db_name}-studio ${db_name}-meta ${db_name}-analytics"
    fi
}

# Check if regeneration is needed
check_and_regenerate() {
    local db_name="$1"
    
    # Check if databases.env changed
    if "${SCRIPT_DIR}/helpers/detect_changes.sh" 2>/dev/null; then
        if [ -n "$db_name" ]; then
            print_info "Changes detected in databases.env, regenerating docker-compose.yml for $db_name..."
            local db_dir="${SCRIPT_DIR}/databases/${db_name}"
            local full_mode="lean"
            if [ -f "${db_dir}/.env" ] && grep -q "FULL mode" "${db_dir}/.env" 2>/dev/null; then
                full_mode="full"
            fi
            generate_compose "$full_mode" "$db_name"
        else
            print_info "Changes detected in databases.env, regenerating all docker-compose.yml files..."
            # Regenerate for all databases
            local needs_full=false
            for db_dir in "${SCRIPT_DIR}/databases"/*/; do
                [ ! -d "$db_dir" ] && continue
                if [ -f "${db_dir}/.env" ] && grep -q "FULL mode" "${db_dir}/.env" 2>/dev/null; then
                    needs_full=true
                    break
                fi
            done 2>/dev/null || true
            generate_compose "$([ "$needs_full" = true ] && echo "full" || echo "lean")"
        fi
    fi
}

# Start database(s)
cmd_start() {
    local databases=("$@")
    
    if [ ${#databases[@]} -eq 0 ]; then
        print_error "Database name(s) required"
        print_info "Usage: $0 start <db-name> [db-name2 ...]"
        print_info "Or use: $0 start-all"
        exit 1
    fi
    local started=0
    local failed=0
    
    print_header "Starting database(s)"
    
    # Check and regenerate if needed (before starting)
    check_and_regenerate "${databases[0]}"
    
    for db_name in "${databases[@]}"; do
        # Validate database exists (support both formats)
        if ! grep -q "^${db_name}|" "$CENTRAL_ENV" && ! grep -q "^\[${db_name}\]" "$CENTRAL_ENV"; then
            print_error "Database '$db_name' not found in databases.env"
            ((failed++))
            continue
        fi
        
        print_info "Starting: $db_name"
        local compose_file="${SCRIPT_DIR}/databases/${db_name}/docker-compose.yml"
        if [ ! -f "$compose_file" ]; then
            print_error "docker-compose.yml not found for $db_name. Regenerating..."
            check_and_regenerate "$db_name"
        fi
        local services=$(get_db_services "$db_name")
        
        if docker compose -f "$compose_file" up -d $services 2>&1 | grep -q "error\|Error\|ERROR"; then
            print_error "Failed to start $db_name"
            ((failed++))
        else
            print_success "$db_name started"
            ((started++))
        fi
    done
    
    echo ""
    [ $started -gt 0 ] && print_success "Started $started database(s)"
    [ $failed -gt 0 ] && print_error "Failed to start $failed database(s)"
}

# Start all databases
cmd_start_all() {
    print_header "Starting ALL databases"
    
    # Check and regenerate if needed
    check_and_regenerate ""
    
    # Get all database names (support both formats)
    local databases
    # Try new section format first
    if grep -q "^\[" "$CENTRAL_ENV"; then
        databases=$(grep -E "^\[[a-zA-Z0-9-]+\]$" "$CENTRAL_ENV" | sed 's/\[//;s/\]//' | grep -v "^global$")
    else
        # Old pipe format
        databases=$(grep -E "^[^#].*\|" "$CENTRAL_ENV" | grep -v "^DASHBOARD_USERNAME" | grep -E "^[a-zA-Z0-9-]+\|" | cut -d'|' -f1)
    fi
    
    if [ -z "$databases" ]; then
        print_info "No databases found to start"
        return 0
    fi
    
    print_info "Found databases:"
    echo "$databases" | sed 's/^/  - /'
    echo ""
    
    local started=0
    local failed=0
    
    while IFS= read -r db_name; do
        [ -z "$db_name" ] && continue
        
        print_info "Starting: $db_name"
        local compose_file="${SCRIPT_DIR}/databases/${db_name}/docker-compose.yml"
        if [ ! -f "$compose_file" ]; then
            print_error "docker-compose.yml not found for $db_name. Regenerating..."
            check_and_regenerate "$db_name"
        fi
        local services=$(get_db_services "$db_name")
        
        if docker compose -f "$compose_file" up -d $services 2>&1 | grep -q "error\|Error\|ERROR"; then
            print_error "Failed to start $db_name"
            ((failed++))
        else
            print_success "$db_name started"
            ((started++))
        fi
    done <<< "$databases"
    
    echo ""
    [ $started -gt 0 ] && print_success "Started $started database(s)"
    [ $failed -gt 0 ] && print_error "Failed to start $failed database(s)"
}

# Stop database(s)
cmd_stop() {
    local databases=("$@")
    
    if [ ${#databases[@]} -eq 0 ]; then
        print_error "Database name(s) required"
        print_info "Usage: $0 stop <db-name> [db-name2 ...]"
        print_info "Or use: $0 stop-all"
        exit 1
    fi
    local stopped=0
    local failed=0
    
    print_header "Stopping database(s)"
    
    for db_name in "${databases[@]}"; do
        # Validate database exists
        grep -q "^${db_name}|" "$CENTRAL_ENV" || {
            print_error "Database '$db_name' not found in databases.env"
            ((failed++))
            continue
        }
        
        print_info "Stopping: $db_name"
        local compose_file="${SCRIPT_DIR}/databases/${db_name}/docker-compose.yml"
        if [ ! -f "$compose_file" ]; then
            print_error "docker-compose.yml not found for $db_name"
            ((failed++))
            continue
        fi
        local services=$(get_db_services "$db_name")
        
        if docker compose -f "$compose_file" stop $services 2>&1 | grep -q "error\|Error\|ERROR"; then
            print_error "Failed to stop $db_name"
            ((failed++))
        else
            print_success "$db_name stopped"
            ((stopped++))
        fi
    done
    
    echo ""
    [ $stopped -gt 0 ] && print_success "Stopped $stopped database(s)"
    [ $failed -gt 0 ] && print_error "Failed to stop $failed database(s)"
}

# Stop all databases
cmd_stop_all() {
    print_header "Stopping ALL databases"
    
    # Get all database names
    local databases
    databases=$(grep -E "^[^#].*\|" "$CENTRAL_ENV" | grep -v "^DASHBOARD_USERNAME" | grep -E "^[a-zA-Z0-9-]+\|" | cut -d'|' -f1)
    
    if [ -z "$databases" ]; then
        print_info "No databases found to stop"
        return 0
    fi
    
    print_info "Found databases:"
    echo "$databases" | sed 's/^/  - /'
    echo ""
    
    local stopped=0
    local failed=0
    
    while IFS= read -r db_name; do
        [ -z "$db_name" ] && continue
        
        print_info "Stopping: $db_name"
        local compose_file="${SCRIPT_DIR}/databases/${db_name}/docker-compose.yml"
        if [ ! -f "$compose_file" ]; then
            print_error "docker-compose.yml not found for $db_name"
            ((failed++))
            continue
        fi
        local services=$(get_db_services "$db_name")
        
        if docker compose -f "$compose_file" stop $services 2>&1 | grep -q "error\|Error\|ERROR"; then
            print_error "Failed to stop $db_name"
            ((failed++))
        else
            print_success "$db_name stopped"
            ((stopped++))
        fi
    done <<< "$databases"
    
    echo ""
    [ $stopped -gt 0 ] && print_success "Stopped $stopped database(s)"
    [ $failed -gt 0 ] && print_error "Failed to stop $failed database(s)"
}

# Main
case "${1:-}" in
    add)
        cmd_add "$2" "$3" "$4"
        ;;
    add-full)
        cmd_add_full "$2" "$3" "$4"
        ;;
    remove|rm)
        cmd_remove "$2"
        ;;
    remove-all|rm-all)
        cmd_remove_all
        ;;
    start)
        shift # Remove 'start' command
        cmd_start "$@"
        ;;
    start-all)
        cmd_start_all
        ;;
    stop)
        shift # Remove 'stop' command
        cmd_stop "$@"
        ;;
    stop-all)
        cmd_stop_all
        ;;
    show-ports|ports)
        cmd_show_ports
        ;;
    update-resources|update)
        cmd_update_resources "$2" "$3" "$4"
        ;;
    validate)
        cmd_validate
        ;;
    generate)
        generate_compose "${2:-lean}" "${3:-}"
        ;;
    *)
        echo "Usage: $0 {add|add-full|remove|remove-all|start|start-all|stop|stop-all|show-ports|update-resources|validate|generate} [options]"
        echo ""
        echo "Commands:"
        echo "  add <name> [cpu] [memory]     Add a new database (lean - essential services only)"
        echo "  add-full <name> [cpu] [memory]  Add a new database with ALL services"
        echo "  remove <name>                 Remove a database"
        echo "  remove-all                    Remove ALL databases (with confirmation)"
        echo "  start <name> [name2 ...]      Start one or more databases"
        echo "  start-all                     Start ALL databases"
        echo "  stop <name> [name2 ...]      Stop one or more databases"
        echo "  stop-all                      Stop ALL databases"
        echo "  show-ports                     Show all port assignments"
        echo "  update-resources <name> <cpu> <memory>  Update database resources"
        echo "  validate                       Validate databases.env"
        echo "  generate [lean|full]          Regenerate docker-compose.yml (default: lean)"
        exit 1
        ;;
esac

