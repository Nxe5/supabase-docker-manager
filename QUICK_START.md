# Quick Start Guide

## Essential Files

- `db_manager.sh` - Main management script (use this for everything)
- `generate_compose.sh` - Generates docker-compose.yml (called automatically)
- `databases.env` - Central configuration (all database credentials)
- `docker-compose.yml` - Auto-generated (DO NOT EDIT)
- `supabase-project/` - Template directory for new databases

## Common Commands

### Add a Database
```bash
./db_manager.sh add my-db 2.0 4g
```
Creates directory, adds to databases.env, regenerates docker-compose.yml

### Remove a Database
```bash
./db_manager.sh remove my-db
```
Removes from databases.env, asks to delete directory, regenerates docker-compose.yml

### Remove ALL Databases (Fresh Start)
```bash
./db_manager.sh remove-all
```
Type `DELETE ALL` to confirm. Removes all databases and optionally all directories.

### Show Ports
```bash
./db_manager.sh show-ports
```

### Update Resources
```bash
./db_manager.sh update my-db 4.0 8g
```

### Start Everything
```bash
docker compose up -d
```

### Manage Ollama
```bash
./db_manager.sh ollama start
./db_manager.sh ollama stop
./db_manager.sh ollama status
```

## Clean Root Directory

To remove old/unused files:
```bash
./cleanup_root.sh
```

This removes:
- Old scripts (add_db.sh, manage_dbs.sh, etc.)
- Old documentation files
- Orphaned database directories (with confirmation)

## Fresh Start

To start completely fresh:
```bash
# Remove all databases
./db_manager.sh remove-all
# Type: DELETE ALL
# Answer: y (to remove directories)

# Clean up old files
./cleanup_root.sh

# Add your first database
./db_manager.sh add my-first-db
```

