#!/bin/bash

# Migration script to convert pipe-delimited format to section-based format
# Usage: ./migrate_to_sections.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENTRAL_ENV="${SCRIPT_DIR}/databases.env"
BACKUP_ENV="${CENTRAL_ENV}.backup.$(date +%Y%m%d_%H%M%S)"

print_info() { echo -e "\033[1;33mℹ $1\033[0m"; }
print_success() { echo -e "\033[0;32m✓ $1\033[0m"; }

if [ ! -f "$CENTRAL_ENV" ]; then
    echo "Error: databases.env not found"
    exit 1
fi

# Backup original
cp "$CENTRAL_ENV" "$BACKUP_ENV"
print_success "Backed up to: $BACKUP_ENV"

# Create new format
TEMP_FILE=$(mktemp)

# Process database entries
while IFS='|' read -r db_name postgres_port kong_http_port kong_https_port pooler_port cpu_limit memory_limit postgres_pass jwt_secret anon_key service_key rest; do
    [[ "$db_name" =~ ^#.*$ ]] && continue
    [[ -z "$db_name" ]] && continue
    [[ "$db_name" == "DASHBOARD_USERNAME" ]] && break
    [[ "$db_name" =~ = ]] && break
    [[ ! "$db_name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    
    # Check if this database has full services (check docker-compose.yml)
    full_services="false"
    if docker compose config --services 2>/dev/null | grep -q "^${db_name}-realtime$"; then
        full_services="true"
    fi
    
    cat >> "$TEMP_FILE" << EOF

# ============================================
# Database: $db_name
# ============================================
[$db_name]
POSTGRES_PORT=$postgres_port
KONG_HTTP_PORT=$kong_http_port
KONG_HTTPS_PORT=$kong_https_port
POOLER_PORT=$pooler_port
CPU_LIMIT=$cpu_limit
MEMORY_LIMIT=$memory_limit
POSTGRES_PASSWORD=$postgres_pass
JWT_SECRET=$jwt_secret
ANON_KEY=$anon_key
SERVICE_ROLE_KEY=$service_key
FULL_SERVICES=$full_services

EOF
done < "$CENTRAL_ENV"

# Add global config section
cat >> "$TEMP_FILE" << 'EOF'

# ============================================
# Global Configuration (applies to all databases)
# ============================================
[global]
EOF

# Copy global config
grep -E "^[A-Z_]+=" "$CENTRAL_ENV" | grep -v "^#" >> "$TEMP_FILE"

# Replace original
mv "$TEMP_FILE" "$CENTRAL_ENV"
print_success "Migration complete! Format converted to section-based."
print_info "Backup saved to: $BACKUP_ENV"

