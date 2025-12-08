# Contexus Platform - Database Schema for Docker Deployment

## Overview

This document describes the database schema creation process for Docker container deployment of the Contexus IoT Platform.

## Database Architecture

The platform uses PostgreSQL with 40 tables organized into the following categories:

### Core Tables (Multi-tenancy Foundation)
| Table | Purpose |
|-------|---------|
| `workspaces` | Multi-tenant workspace isolation |
| `subscription_plans` | SaaS subscription tier management |
| `users` | User authentication and profiles |
| `workspace_users` | User-workspace membership junction |
| `admin_users` | Admin-specific authentication |
| `regular_users` | Regular user profiles with approval |
| `session` | Session storage for connect-pg-simple |

### IoT Device Management
| Table | Purpose |
|-------|---------|
| `drivers` | MQTT/protocol driver definitions |
| `products` | Product catalog and specifications |
| `thing_models` | Device capability models |
| `devices` | Device registry with workspace isolation |
| `mqtt_discovered_devices` | MQTT device discovery staging |
| `mqtt_message_buffer` | Recent MQTT message buffer |
| `device_data` | Time-series sensor data |
| `device_property_cache` | Cached device property values |

### Dashboard & Visualization
| Table | Purpose |
|-------|---------|
| `dashboards` | Dashboard configurations and widgets |
| `floor_plans` | Floor plan layouts with device markers |
| `floor_plan_templates` | Reusable floor plan templates |
| `hmi_diagrams` | HMI diagram storage (legacy) |

### Automation & Rules
| Table | Purpose |
|-------|---------|
| `rules` | Condition-based automation rules |
| `rule_executions` | Rule execution history |
| `alerts` | System and device alerts |
| `scenes` | Scene automation configurations |

### Flow Engine
| Table | Purpose |
|-------|---------|
| `flows` | Visual workflow definitions |
| `flow_execution_logs` | Flow execution history |
| `node_red_flows` | Legacy Node-RED flow storage |
| `virtual_points` | Calculated virtual data points |
| `virtual_point_data` | Virtual point time-series data |

### Control System
| Table | Purpose |
|-------|---------|
| `control_devices` | Controllable device registry |
| `control_commands` | Command queue and history |

### Energy Management
| Table | Purpose |
|-------|---------|
| `energy_meters` | Energy meter configurations |
| `energy_readings` | Energy consumption readings |
| `energy_consumption` | Aggregated consumption data |

### Space Management
| Table | Purpose |
|-------|---------|
| `spaces` | Hierarchical space organization |
| `space_meters` | Space-meter associations |

### System Configuration
| Table | Purpose |
|-------|---------|
| `system_config` | Key-value system configuration |
| `system_branding` | White-label branding settings |
| `system_metrics` | System performance metrics |
| `database_connections` | External database connections |
| `data_integration_jobs` | Data integration job definitions |

## Docker Deployment

### Files Involved

1. **`init-multiple-databases.sh`** - PostgreSQL initialization script
   - Mounted at `/docker-entrypoint-initdb.d/`
   - Creates all 40 tables with proper constraints
   - Sets up performance indexes
   - Inserts default data

2. **`start.sh`** - Application startup script
   - Waits for PostgreSQL readiness
   - Verifies schema existence
   - Falls back to Drizzle db:push if needed
   - Starts the application

3. **`docker-compose.yml`** - Container orchestration
   - PostgreSQL service with health checks
   - Redis service for caching
   - Application service with dependencies

4. **`drizzle.config.ts`** - Drizzle ORM configuration
   - Schema synchronization settings
   - Migration tracking

### Initialization Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Docker Compose Up                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 PostgreSQL Container Starts                      │
│  1. Runs init-multiple-databases.sh (first-time only)           │
│  2. Creates all 40 tables + indexes                              │
│  3. Inserts default workspace and branding                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Redis Container Starts                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Application Container Starts                     │
│  1. start.sh waits for PostgreSQL + Redis                       │
│  2. Verifies schema exists (40 tables expected)                  │
│  3. If schema missing: runs npm run db:push                      │
│  4. Starts Node.js application                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Common Issues and Solutions

#### Issue: "Skipping initialization" - Schema Not Created

**Root Cause:**
PostgreSQL init scripts (`/docker-entrypoint-initdb.d/`) **only run on first initialization** when the data directory is completely empty. If any data exists from a previous attempt, init scripts are skipped entirely.

**Symptoms:**
- PostgreSQL logs show: "PostgreSQL Database directory appears to contain a database; Skipping initialization"
- Application shows 0 tables in schema verification
- Infinite retry loop in application startup

**Solution - Complete Volume Reset:**
```bash
# 1. Stop all containers and remove volumes
docker-compose down -v

# 2. Remove the bind-mounted data directory
rm -rf ./data/postgres/*

# 3. Ensure script has execute permissions
chmod +x init-multiple-databases.sh

# 4. Restart fresh
docker-compose up -d

# 5. Watch the logs
docker-compose logs -f postgres contexus
```

**Alternative - Manual Schema Creation (if reset not possible):**
```bash
# Run manual schema SQL directly
docker exec -i contexus-postgres psql -U contexus -d contexus < manual-schema.sql

# Verify tables were created
docker exec contexus-postgres psql -U contexus -d contexus -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"

# Restart the application container
docker-compose restart contexus
```

#### Issue: Application Startup Loop

**Symptoms:**
- Logs show "verification attempts 4/10, 5/10..." repeating
- Schema verification keeps failing

**Root Cause:**
The application's `start.sh` has multiple fallback strategies. If all fail, check:
1. Database connection is valid
2. User has CREATE TABLE permissions
3. Drizzle schema file exists

**Solution:**
The updated `start.sh` has three fallback strategies:
1. **Drizzle db:push** - Uses ORM to create tables
2. **manual-schema.sql** - Runs backup SQL file
3. **Inline SQL** - Creates essential tables directly

If still failing:
```bash
# Check what tables exist
docker exec contexus-postgres psql -U contexus -d contexus -c "
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' ORDER BY table_name;"

# Check database user permissions
docker exec contexus-postgres psql -U contexus -d contexus -c "
SELECT has_database_privilege('contexus', 'contexus', 'CREATE');"
```

#### Issue: Permission Denied on Init Script

**Symptoms:**
- PostgreSQL logs show permission errors for init script
- Script doesn't execute

**Solution:**
```bash
# On host machine
chmod +x init-multiple-databases.sh

# Rebuild if using Dockerfile
docker-compose build --no-cache contexus
```

#### Issue: Drizzle Migrations Conflict

**Symptoms:**
- "relation already exists" errors
- Schema mismatch between init script and Drizzle

**Solutions:**
```bash
# 1. Use db:push --force for schema sync
docker exec -it contexus-app npm run db:push --force

# 2. Reset and let init script create schema
docker-compose down -v
docker-compose up -d
```

### Environment Variables

Required for database initialization:

```env
POSTGRES_USER=contexus
POSTGRES_PASSWORD=<secure-password>
POSTGRES_DB=contexus

# Application database URL
DATABASE_URL=postgresql://contexus:<password>@postgres:5432/contexus
```

### Verification Commands

```bash
# Check table count
docker exec -it contexus-postgres psql -U contexus -d contexus -c "
SELECT COUNT(*) as table_count FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
"

# List all tables
docker exec -it contexus-postgres psql -U contexus -d contexus -c "
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;
"

# Check for key tables
docker exec -it contexus-postgres psql -U contexus -d contexus -c "
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('users', 'workspaces', 'devices', 'dashboards', 'flows', 'rules');
"
```

### Schema Synchronization Strategy

The platform uses a dual-strategy approach:

1. **Docker Init Script (Primary)**
   - Creates complete schema on first PostgreSQL start
   - Idempotent - skips if tables already exist
   - Includes all 40 tables with proper constraints

2. **Drizzle ORM (Secondary)**
   - Used for schema updates and migrations
   - `npm run db:push` syncs schema changes
   - Drizzle migrations table tracks applied changes

### Table Creation Order

Tables are created in dependency order:

1. `workspaces` (no dependencies)
2. `subscription_plans` (no dependencies)
3. `users` (references workspaces, subscription_plans)
4. `workspace_users` (references workspaces, users)
5. `drivers` (references workspaces)
6. `products` (references workspaces)
7. `thing_models` (references workspaces)
8. `devices` (references workspaces, drivers, thing_models)
9. ... (remaining tables follow dependency order)

### Performance Indexes

The schema includes 80+ performance indexes covering:

- **Workspace isolation**: All multi-tenant queries
- **Time-series queries**: Device data timestamp ranges
- **Status lookups**: Device and alert status filtering
- **Full-text search**: Device name and key matching

## Backup and Recovery

### Database Backup
```bash
docker exec contexus-postgres pg_dump -U contexus -d contexus > backup.sql
```

### Database Restore
```bash
docker exec -i contexus-postgres psql -U contexus -d contexus < backup.sql
```

### Schema-Only Export
```bash
docker exec contexus-postgres pg_dump -U contexus -d contexus --schema-only > schema.sql
```
