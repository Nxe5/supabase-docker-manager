#!/bin/bash

# Helper functions to parse section-based databases.env
# Source this file: source ./parse_databases_env.sh

# Get all database names
get_database_names() {
    grep -E "^\[[a-zA-Z0-9-]+\]$" "$CENTRAL_ENV" | sed 's/\[//;s/\]//'
}

# Get a specific database's config value
get_db_config() {
    local db_name="$1"
    local key="$2"
    awk -v db="$db_name" -v key="$key" '
        /^\[' db '\]$/ { in_section=1; next }
        /^\[/ { in_section=0; next }
        in_section && $0 ~ "^" key "=" { print substr($0, length(key)+2); exit }
    ' "$CENTRAL_ENV"
}

# Check if database exists
db_exists() {
    local db_name="$1"
    grep -q "^\[${db_name}\]$" "$CENTRAL_ENV"
}

# Check if database is in full mode
is_full_mode() {
    local db_name="$1"
    local full=$(get_db_config "$db_name" "FULL_SERVICES")
    [[ "$full" == "true" ]]
}

# Get all config for a database as pipe-delimited (for backward compatibility)
get_db_config_pipe() {
    local db_name="$1"
    local postgres_port=$(get_db_config "$db_name" "POSTGRES_PORT")
    local kong_http_port=$(get_db_config "$db_name" "KONG_HTTP_PORT")
    local kong_https_port=$(get_db_config "$db_name" "KONG_HTTPS_PORT")
    local pooler_port=$(get_db_config "$db_name" "POOLER_PORT")
    local cpu_limit=$(get_db_config "$db_name" "CPU_LIMIT")
    local memory_limit=$(get_db_config "$db_name" "MEMORY_LIMIT")
    local postgres_pass=$(get_db_config "$db_name" "POSTGRES_PASSWORD")
    local jwt_secret=$(get_db_config "$db_name" "JWT_SECRET")
    local anon_key=$(get_db_config "$db_name" "ANON_KEY")
    local service_key=$(get_db_config "$db_name" "SERVICE_ROLE_KEY")
    
    echo "${db_name}|${postgres_port}|${kong_http_port}|${kong_https_port}|${pooler_port}|${cpu_limit}|${memory_limit}|${postgres_pass}|${jwt_secret}|${anon_key}|${service_key}"
}

