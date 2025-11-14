# Docker Swarm - Multi-Database Management

Unified management system for multiple Supabase databases with a single docker-compose.yml file.

## Quick Start

**You only need to use one script: `db_manager.sh`**

All helper scripts are automatically called by `db_manager.sh` and are located in the `helpers/` directory.

```bash
# Add a database
./db_manager.sh add my-db 2.0 4g

# Show all ports
./db_manager.sh show-ports

# Start all services
docker compose up -d

# Manage Ollama
./db_manager.sh ollama start
```

## Architecture

- **Single `docker-compose.yml`** - All databases and services in one file (auto-generated)
- **`databases.env`** - Central configuration for all databases
- **`db_manager.sh`** - **Main script** - The only script you need to use
- **`helpers/`** - Helper scripts (automatically called by `db_manager.sh`)

## Commands

### Database Management

```bash
# Add a new database
./db_manager.sh add <name> [cpu] [memory]
./db_manager.sh add my-db 2.0 4g

# Remove a database
./db_manager.sh remove <name>
./db_manager.sh remove my-db

# Show port assignments
./db_manager.sh show-ports

# Update database resources
./db_manager.sh update-resources <name> <cpu> <memory>
./db_manager.sh update-resources my-db 4.0 8g

# Validate databases.env
./db_manager.sh validate

# Regenerate docker-compose.yml
./db_manager.sh generate
```

### Ollama Management

```bash
# Start Ollama
./db_manager.sh ollama start

# Stop Ollama
./db_manager.sh ollama stop

# Restart Ollama
./db_manager.sh ollama restart

# Check status
./db_manager.sh ollama status

# View logs
./db_manager.sh ollama logs
```

### Docker Compose

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f

# Start specific database services
docker compose up -d <db-name>-db <db-name>-kong
```

## Port Assignment

Ports are automatically assigned and increment for each database:

| Database | POSTGRES | KONG_HTTP | KONG_HTTPS | POOLER |
|----------|----------|-----------|------------|--------|
| supabase-project | 5432 | 8000 | 8443 | 6543 |
| fish-finder | 5433 | 8001 | 8444 | 6544 |
| next-db | 5434 | 8002 | 8445 | 6545 |

Ollama uses port **11434** (shared by all databases).

## File Structure

```
docker-swarm/
├── docker-compose.yml      # Auto-generated (DO NOT EDIT)
├── databases.env            # Central configuration
├── db_manager.sh           # Main management script
├── generate_compose.sh     # Docker compose generator
└── supabase-project/      # Template directory
    └── volumes/           # Shared volume templates
```

## Configuration

Edit `databases.env` to configure:
- Database credentials
- Port assignments
- Resource limits
- Global settings

**Important**: After editing `databases.env`, run:
```bash
./db_manager.sh generate
```

## Migration from Old System

If you were using the old separate docker-compose files:

1. Run cleanup (backs up old files):
   ```bash
   ./cleanup_old_files.sh
   ```

2. Generate new docker-compose.yml:
   ```bash
   ./db_manager.sh generate
   ```

3. Start services:
   ```bash
   docker compose up -d
   ```

## Troubleshooting

### Port Conflicts
```bash
# Check what's using a port
lsof -i :5432

# View all assigned ports
./db_manager.sh show-ports
```

### Regenerate Compose File
If docker-compose.yml gets out of sync:
```bash
./db_manager.sh generate
docker compose up -d
```

### Validate Configuration
```bash
./db_manager.sh validate
```

## Notes

- `docker-compose.yml` is auto-generated - don't edit it manually
- Use `db_manager.sh` for all database operations
- Each database gets isolated services with unique ports
- Ollama is shared across all databases
- Volumes are persisted per database

