# Helper Scripts

This directory contains helper scripts used by `db_manager.sh`. These scripts are not meant to be run directly by users.

## Scripts

- **`generate_compose.sh`** - Generates `docker-compose.yml` from `databases.env`
- **`detect_changes.sh`** - Detects if `databases.env` has changed and needs regeneration
- **`parse_databases_env.sh`** - Helper functions for parsing section-based `databases.env` format (for future use)
- **`migrate_to_sections.sh`** - Migration script to convert from pipe-delimited to section-based format (for future use)

## Usage

All helper scripts are automatically called by `db_manager.sh`. You should never need to run these directly.

