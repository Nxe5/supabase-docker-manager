# 🐳 Supabase Docker Manager

> **A powerful, unified management system for running multiple Supabase database instances in Docker containers, with Docker Swarm support coming soon.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg)](https://www.docker.com/)

---

## ✨ Features

- 🚀 **Single Command Management** - One script (`db_manager.sh`) handles everything
- 🔄 **Auto-Generated Compose** - Dynamically generates `docker-compose.yml` from configuration
- 📊 **Multi-Database Support** - Run multiple isolated Supabase instances simultaneously
- 🔌 **Automatic Port Assignment** - No port conflicts, ports auto-increment per database
- 💾 **Resource Management** - Set CPU and memory limits per database
- 🎯 **Lean & Full Modes** - Choose essential services or full Supabase stack
- 🔒 **Secure by Default** - Sensitive data excluded from version control
- 🐝 **Docker Swarm Ready** - Architecture designed for future Swarm deployment

---

## 🎯 What It Does

**Supabase Docker Manager** simplifies running multiple Supabase database instances on a single host. Instead of managing separate `docker-compose.yml` files for each database, you:

1. **Add databases** with a single command
2. **Automatically get** isolated services with unique ports
3. **Manage resources** (CPU/memory) per database
4. **Start/stop** individual databases or all at once
5. **Scale** to Docker Swarm when ready

Perfect for:
- 🧪 **Development** - Multiple project databases on one machine
- 🏢 **Staging** - Isolated environments per feature branch
- 🎓 **Learning** - Experiment with different Supabase configurations
- 🚀 **Production** - Deploy to Docker Swarm for high availability

---

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose installed
- Bash shell (macOS/Linux)
- Git

### Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd supabase-docker-manager

# Copy the example configuration
cp databases.env.example databases.env

# Make the script executable
chmod +x db_manager.sh
```

### Your First Database

```bash
# Add a database (lean mode - essential services only)
./db_manager.sh add my-first-db 2.0 4g

# Or add with full Supabase stack
./db_manager.sh add-full my-first-db 2.0 4g

# View port assignments
./db_manager.sh show-ports

# Start the database
./db_manager.sh start my-first-db

# Or start all databases
./db_manager.sh start-all
```

That's it! Your database is running at `http://localhost:8000` (or the assigned port).

---

## 📖 Commands Reference

### Database Management

| Command | Description | Example |
|---------|-------------|---------|
| `add <name> [cpu] [memory]` | Add database (lean mode) | `./db_manager.sh add my-db 2.0 4g` |
| `add-full <name> [cpu] [memory]` | Add database (full stack) | `./db_manager.sh add-full my-db 2.0 4g` |
| `remove <name>` | Remove database | `./db_manager.sh remove my-db` |
| `remove-all` | Remove all databases | `./db_manager.sh remove-all` |
| `show-ports` | Display port assignments | `./db_manager.sh show-ports` |
| `update-resources <name> <cpu> <memory>` | Update CPU/memory | `./db_manager.sh update-resources my-db 4.0 8g` |
| `validate` | Validate configuration | `./db_manager.sh validate` |

### Container Management

| Command | Description | Example |
|---------|-------------|---------|
| `start <name>` | Start specific database | `./db_manager.sh start my-db` |
| `start-all` | Start all databases | `./db_manager.sh start-all` |
| `stop <name>` | Stop specific database | `./db_manager.sh stop my-db` |
| `stop-all` | Stop all databases | `./db_manager.sh stop-all` |

### Utilities

| Command | Description | Example |
|---------|-------------|---------|
| `generate` | Regenerate docker-compose.yml | `./db_manager.sh generate` |

---

## 🏗️ Architecture

```
supabase-docker-manager/
├── db_manager.sh              # Main management script (the only one you need!)
├── databases.env              # Central configuration (not tracked in git)
├── databases.env.example       # Example configuration template
├── docker-compose.yml         # Auto-generated (DO NOT EDIT)
├── helpers/                   # Helper scripts (auto-called by db_manager.sh)
│   ├── generate_compose.sh   # Generates docker-compose.yml
│   ├── detect_changes.sh      # Detects config changes
│   └── ...
└── databases/                 # Database directories (not tracked in git)
    ├── my-db/                 # Individual database configs
    └── ...
```

### How It Works

1. **Configuration** - All databases defined in `databases.env` (pipe-delimited format)
2. **Generation** - `db_manager.sh` reads config and generates unified `docker-compose.yml`
3. **Isolation** - Each database gets unique ports and isolated volumes
4. **Management** - Single script handles all operations

---

## 🔌 Port Assignment

Ports automatically increment for each database to prevent conflicts:

| Service | First DB | Second DB | Third DB | Pattern |
|---------|----------|-----------|----------|---------|
| **Postgres** | 5432 | 5433 | 5434 | +1 |
| **Kong HTTP** | 8000 | 8001 | 8002 | +1 |
| **Kong HTTPS** | 8443 | 8444 | 8445 | +1 |
| **Pooler** | 6543 | 6544 | 6545 | +1 |
| **Studio** | 3000 | 3001 | 3002 | +1 |

View all assignments:
```bash
./db_manager.sh show-ports
```

---

## ⚙️ Configuration

### Database Entry Format

Each database entry in `databases.env` contains 11 pipe-delimited fields:

```
db-name|postgres-port|kong-http|kong-https|pooler-port|cpu|memory|postgres-pass|jwt-secret|anon-key|service-key
```

**Don't edit manually!** Use `db_manager.sh` commands instead.

### Global Settings

Edit `databases.env` to configure:
- Dashboard credentials
- SMTP settings
- Storage backends
- Auth providers
- And more...

See `databases.env.example` for all available options.

---

## 🎛️ Service Modes

### Lean Mode (Default)
Essential services only:
- PostgreSQL database
- Kong API Gateway
- Auth (GoTrue)
- REST (PostgREST)
- Studio
- Postgres Meta
- Analytics

### Full Mode
All Supabase services:
- Everything in Lean mode, plus:
- Realtime
- Storage
- Imgproxy
- Edge Functions
- Vector
- Supavisor (Connection Pooler)

---

## 🔒 Security

- ✅ `databases.env` excluded from git (contains secrets)
- ✅ `databases.env.example` provided as template
- ✅ Database directories excluded from git
- ✅ Auto-generated passwords for new databases
- ✅ Isolated volumes per database

**Important:** Never commit `databases.env` or database directories to version control!

---

## 🐝 Docker Swarm (Coming Soon)

The architecture is designed with Docker Swarm in mind:
- Single compose file for easy stack deployment
- Resource limits compatible with Swarm
- Service isolation ready for multi-node deployment

---

## 📚 Examples

### Development Workflow

```bash
# Add databases for different projects
./db_manager.sh add project-alpha 2.0 4g
./db_manager.sh add project-beta 2.0 4g

# Start only the one you're working on
./db_manager.sh start project-alpha

# Update resources when needed
./db_manager.sh update-resources project-alpha 4.0 8g
```

### Clean Slate

```bash
# Remove everything and start fresh
./db_manager.sh remove-all

# Add new databases
./db_manager.sh add new-project 2.0 4g
```

---

## 🛠️ Troubleshooting

### Port Conflicts

```bash
# Check what's using a port
lsof -i :5432

# View all assigned ports
./db_manager.sh show-ports
```

### Regenerate Compose File

If `docker-compose.yml` gets out of sync:

```bash
./db_manager.sh generate
docker compose up -d
```

### Validate Configuration

```bash
./db_manager.sh validate
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific database
docker compose logs -f my-db-db my-db-kong
```

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 📝 License

MIT License - see LICENSE file for details

---

## 🙏 Acknowledgments

Built for managing Supabase instances. Uses the official [Supabase Docker setup](https://github.com/supabase/supabase/tree/master/docker).

---

## 📞 Support

- 🐛 **Issues**: [GitHub Issues](https://github.com/your-username/supabase-docker-manager/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/your-username/supabase-docker-manager/discussions)
- 📖 **Documentation**: See `QUICK_START.md` for detailed setup

---

**Made with ❤️ for developers who need to manage multiple databases efficiently.**
