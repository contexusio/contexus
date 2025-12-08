# contexus IoTHub - Open Source Enterprise IoT Platform

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)](https://github.com/contexus/contexus)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Node.js Version](https://img.shields.io/badge/node-%3E%3D18.0.0-brightgreen)](https://nodejs.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-blue.svg)](https://postgresql.org/)

A comprehensive, scalable IoT platform for device management, data visualization, and real-time monitoring. Built with modern technologies including Node.js, TypeScript, PostgreSQL, Redis, and React.

## 🚀 Features

### Core Platform
- **Multi-Tenancy** - Production-ready workspace isolation for devices, data, dashboards, rules, alerts, and drivers
- **Device Management** - Register, monitor, and control IoT devices with hierarchical relationships
- **Real-time Data** - WebSocket-based live data streaming with ECharts visualization
- **Dashboard Builder** - Customizable drag-and-drop dashboards with widget library (KPI, Charts, Controls, Data, FlowInfo)
- **Rule Engine** - Condition-based automation rules with configurable alerts and escalation
- **Alert System** - Smart notifications with grouping, historical view, and count badges
- **User Management** - Role-based access control (RBAC) with workspace-based permissions
- **SaaS Subscription Management** - Database-backed subscription plans with configurable resource limits

### IoT Device Integration
- **LoRaWAN Integration** - ChirpStack webhooks and MQTT integration for device data ingestion
- **Generic MQTT Driver Support** - User-defined MQTT topics, multiple protocols, advanced connection options, and wildcards
- **MQTT Device Discovery** - Staged onboarding with automatic device detection, discovery lifecycle, and interactive property mapping
- **Device Registry** - Comprehensive device metadata with firmware versions, battery levels, and connection monitoring

### Flow Engine & Automation
- **Visual Flow Builder** - Drag-and-drop workflow builder (Node-RED style) for ETL processes
- **Flow Nodes** - Trigger nodes (manual/scheduled), processing nodes (calculations/rules), and action nodes (MQTT control, notifications, email, device updates)
- **Virtual Points System** - Processing nodes output calculated data points stored and displayed like real device data
- **Device Property Value Cache** - Multi-device calculation support with cached property values
- **Flow Execution Logging** - Comprehensive execution history with status tracking and error reporting
- **Dashboard-Flow Integration** - Trigger manual flows from dashboard widgets and display flow status/history

### Energy & Space Management
- **Energy Management System** - Dual-storage architecture for energy data with hourly aggregation
- **Energy Meters** - Device configuration UI for energy meters with multiplier support
- **Energy Analytics** - Dedicated Energy Management Page with consumption analysis and charts
- **Space Management** - Hierarchical three-tier organization (Building, System/Area, Equipment) for energy meters
- **Space Analytics** - Interactive Space Management Page with aggregated consumption API

### Visualization & Planning
- **Plan Builder** - Visual plan creation with IoT device placement
- **Image & GIS Modes** - Support for both image upload and GIS map modes (Leaflet + OpenStreetMap)
- **Device Markers** - Live data popups and widget panels based on template wireframe system
- **GIS Map Features** - Configurable presets, tile styles, and geographic device placement workflow
- **Floor Plans** - Template system for reusable floor plan layouts

### Data & Analytics
- **Unified PostgreSQL Storage** - Single database for configuration and time-series data (40 tables)
- **Data Visualization** - ECharts integration for charts, graphs, and real-time widgets
- **Historical Analysis** - Long-term data storage with optimized composite indexes
- **Device Property Cache** - Cached latest values for fast dashboard loading
- **Export Capabilities** - Data export in multiple formats

### Integrations
- **ChirpStack** - LoRaWAN network server integration with webhook endpoints and MQTT support
- **Database Connectors** - External database connection support for data integration jobs
- **Email Notifications** - SMTP-based alerting with configurable templates

### Security & Performance
- **PostgreSQL Sessions** - Scalable session management with connect-pg-simple
- **Secure CORS** - Environment-aware origin-based access control
- **Rate Limiting** - API protection and throttling
- **Structured Logging** - Comprehensive audit trails with correlation IDs
- **Connection Pooling** - Enterprise-grade database connection factory with circuit breaker protection
- **Performance Optimizations** - Skeleton loading UI, deferred queries, prefetching, and HTTP cache headers

## 📋 Prerequisites

- **Node.js** 18.0.0 or higher
- **PostgreSQL** 15 or higher
- **Redis** 7.0 or higher
- **Docker** (optional, for containerized deployment)

## 🛠️ Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/contexus/contexus.git
cd contexus
```

### 2. Environment Setup

```bash
# Copy environment template
cp env.example .env

# Edit environment variables
nano .env
```

**Required Environment Variables:**
```bash
# Database
POSTGRES_PASSWORD=your_secure_database_password
DATABASE_URL=postgresql://contexus:${POSTGRES_PASSWORD}@localhost:5432/contexus

# Redis
REDIS_PASSWORD=your_secure_redis_password
REDIS_URL=redis://:${REDIS_PASSWORD}@localhost:6379

# Security
SESSION_SECRET=your_256_bit_session_secret
ADMIN_PASSWORD=your_secure_admin_password
JWT_SECRET=your_jwt_secret

# CORS (production)
ALLOWED_ORIGINS=https://yourdomain.com,https://api.yourdomain.com
ALLOWED_NO_ORIGINS=true  # Allow requests without Origin header (development)

# Email (optional)
EMAIL_PASSWORD=your_email_service_password
SMTP_HOST=
SMTP_PORT=
SMTP_USER=

# Application
PORT=15000
NODE_ENV=production
LOG_LEVEL=info
LOG_FORMAT=json

# Note: PostgreSQL now stores all data (configuration + time-series) in unified schema
```

### 3. Install Dependencies

```bash
npm install
```

### 4. Database Setup

```bash
# Push database schema
npm run db:push

# Or with Docker Compose
docker-compose up postgres redis -d
```

### 5. Development Server

```bash
# Start development server
npm run dev

# Access the platform
open http://localhost:15000
```

**Note:** Default port is 15000 (not 5000)

### 6. Default Login

- **Username:** `iotevadmin`
- **Password:** 'admin123!' Value from `ADMIN_PASSWORD` environment variable
- **ADMIN_EMAIL** 'contact@contexus.io'
- **Change immediately after first login**

## 🐳 Docker Deployment

### Production Deployment

```bash
chmod +x docker-compose-wrapper.sh
./docker-compose-wrapper.sh up -d

### Or ensure data directores present first
./ensure-data-dirs.sh
### Then start all services
docker-compose up -d

# View logs
docker-compose logs -f contexus

# Scale services
docker-compose up -d --scale contexus=3
```

### Docker Initialization Flow

1. **PostgreSQL Container** - Runs `init-multiple-databases.sh` on first start
   - Creates all 40 tables with proper constraints
   - Sets up 80+ performance indexes
   - Inserts default workspace and branding data
   - Skips if Drizzle migrations already applied

2. **Application Container** - Waits for PostgreSQL + Redis health checks
   - `start.sh` verifies schema existence (expects 35+ tables)
   - Falls back to `npm run db:push` if schema incomplete
   - Starts Node.js application on port 15000

### Key Docker Files

- **`init-multiple-databases.sh`** - PostgreSQL initialization script (creates 40 tables)
- **`start.sh`** - Application startup with schema verification
- **`docker-compose.yml`** - Container orchestration with health checks
- **`manual-schema.sql`** - Backup SQL for manual schema creation
- **`drizzle.config.ts`** - Drizzle ORM configuration

### Troubleshooting

```bash
# If schema not created: Clean volumes and restart
docker-compose down -v
docker-compose up -d

# Check table count
docker exec contexus-postgres psql -U contexus -d contexus -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"

# Manual schema creation fallback
docker exec -i contexus-postgres psql -U contexus -d contexus < manual-schema.sql

# View initialization logs
docker-compose logs -f postgres contexus
```

### Development with Docker

```bash
# Development environment
docker-compose -f docker-compose.dev.yml up -d
```

## 🧪 Testing

The project uses Vitest for comprehensive testing:

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm run test:coverage

# Run tests with UI
npm run test:ui
```

### Test Structure
- **Unit Tests:** `/test/unit/` - Individual component testing
- **Integration Tests:** `/test/integration/` - API endpoint testing
- **E2E Tests:** `/test/e2e/` - Full workflow testing

## 📚 API Documentation

### Authentication Endpoints
```
POST   /api/auth/login     - User login
POST   /api/auth/logout    - User logout
GET    /api/auth/me        - Current user info
```

### Device Management
```
GET    /api/devices        - List all devices
POST   /api/devices        - Create device
GET    /api/devices/:id    - Get device details
PUT    /api/devices/:id    - Update device
DELETE /api/devices/:id    - Delete device
```

### User Management (Admin)
```
GET    /api/users          - List all users
PATCH  /api/users/:id      - Update user
DELETE /api/users/:id      - Delete user
POST   /api/users/:id/unlock - Unlock user account
```

### Data Endpoints
```
GET    /api/devices/:id/data      - Device data history
POST   /api/devices/:id/data      - Insert device data
GET    /api/devices/:id/latest    - Latest device reading
```

### Workspace Management
```
GET    /api/workspaces            - List workspaces
POST   /api/workspaces            - Create workspace
GET    /api/workspaces/:id        - Get workspace details
PUT    /api/workspaces/:id        - Update workspace
```

### Flow Engine
```
GET    /api/flows                 - List flows
POST   /api/flows                 - Create flow
GET    /api/flows/:id             - Get flow details
PUT    /api/flows/:id             - Update flow
POST   /api/flows/:id/execute     - Execute flow manually
GET    /api/flows/:id/logs        - Get execution logs
```

### Energy Management
```
GET    /api/energy/meters         - List energy meters
GET    /api/energy/consumption    - Get consumption data
GET    /api/spaces                - List spaces (hierarchical)
GET    /api/spaces/:id/consumption - Get space aggregated consumption
```

### ChirpStack Integration
```
POST   /api/chirpstack/webhook/driver/:driverId - LoRaWAN webhook endpoint
GET    /api/chirpstack/devices    - List ChirpStack devices
```

### Node-RED Integration
```
GET    /api/node-red/flows       - List Node-RED flows
POST   /api/node-red/flows       - Deploy flow
```

## 🏗️ Architecture

### Technology Stack
- **Backend:** Node.js + TypeScript + Express.js
- **Frontend:** React + TypeScript + Vite + Radix UI + shadcn/ui + Tailwind CSS
- **Database:** PostgreSQL (unified schema - 40 tables for config + time-series)
- **ORM:** Drizzle ORM with type-safe operations
- **Cache/Sessions:** Redis with PostgreSQL fallback
- **Real-time:** WebSockets + MQTT for IoT device communication
- **Visualization:** ECharts for data charts and graphs
- **Maps:** Leaflet + OpenStreetMap for GIS features
- **Build:** Vite (frontend) + ESBuild (backend)
- **State Management:** TanStack Query + React Context
- **Testing:** Vitest with comprehensive test coverage

### Project Structure
```
├── server/                 # Backend application
│   ├── auth/              # Authentication & authorization
│   ├── database/          # Database connection factory
│   ├── routes/            # API route handlers
│   ├── services/          # Business logic services
│   ├── storage/           # Database abstraction layers
│   ├── middleware/        # Express middleware
│   ├── utils/             # Utility functions
│   ├── chirpstack-webhook-handler.ts  # LoRaWAN integration
│   ├── node-red-runtime.ts # Node-RED integration
│   └── index.ts           # Application entry point
├── client/                # Frontend React application
│   ├── src/
│   │   ├── components/    # React components (Radix UI + shadcn/ui)
│   │   ├── pages/         # Page components
│   │   ├── hooks/         # Custom React hooks
│   │   └── lib/           # Frontend utilities
├── shared/                # Shared types and schemas
│   └── unified-schema.ts  # Complete PostgreSQL schema (40 tables)
├── test/                  # Test suites (Vitest)
│   ├── unit/              # Unit tests
│   ├── integration/       # Integration tests
│   └── e2e/               # End-to-end tests
├── docs/                  # Documentation
│   ├── DATABASE-DOCKER-DEPLOYMENT.md  # Docker deployment guide
│   └── CHIRPSTACK_WEBHOOK_INTEGRATION.md  # ChirpStack setup
├── init-multiple-databases.sh  # PostgreSQL init script
├── start.sh               # Application startup script
├── manual-schema.sql      # Backup SQL schema
├── docker-compose.yml     # Container orchestration
└── drizzle.config.ts      # Drizzle ORM configuration
```

### Database Schema (40 Tables)

**Unified PostgreSQL Architecture** - Single database for all data storage:

**Core Platform (7 tables):** workspaces, subscription_plans, users, workspace_users, admin_users, regular_users, session

**IoT Device Management (8 tables):** drivers, products, thing_models, devices, mqtt_discovered_devices, mqtt_message_buffer, device_data, device_property_cache

**Dashboard & Visualization (4 tables):** dashboards, floor_plans, floor_plan_templates, hmi_diagrams

**Automation & Rules (4 tables):** rules, rule_executions, alerts, scenes

**Flow Engine (5 tables):** flows, flow_execution_logs, node_red_flows, virtual_points, virtual_point_data

**Control System (2 tables):** control_devices, control_commands

**Energy Management (3 tables):** energy_meters, energy_readings, energy_consumption

**Space Management (2 tables):** spaces, space_meters

**System Configuration (5 tables):** system_config, system_branding, system_metrics, database_connections, data_integration_jobs

**Key Features:**
- Composite indexes for efficient time-series queries (device_id, property_name, timestamp)
- UUID primary keys for distributed system compatibility
- JSONB columns for flexible metadata storage
- Workspace-based data isolation for multi-tenancy
- 80+ performance indexes for optimized queries

**Redis:** Session caching, real-time data, rate limiting, query result caching

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `NODE_ENV` | Environment mode | `development` | No |
| `PORT` | Application port | `15000` | No |
| `DATABASE_URL` | PostgreSQL connection string | - | Yes |
| `REDIS_URL` | Redis connection string | - | Yes |
| `SESSION_SECRET` | Session encryption key | - | Yes |
| `ADMIN_PASSWORD` | Initial admin password | - | Yes | # Changed from DEFAULT_ADMIN_PASSWORD
| `ALLOWED_ORIGINS` | CORS allowed origins | localhost in dev | Production |

### CORS Configuration

Development (automatic):
```javascript
['http://localhost:15000']
```

Production (set via environment):
```bash
ALLOWED_ORIGINS=https://yourdomain.com,https://api.yourdomain.com
```

## 🔒 Security Features

- **PostgreSQL Sessions** - Scalable session storage
- **CORS Protection** - Origin-based access control
- **HTTPS Enforcement** - Production security headers
- **Password Hashing** - bcrypt with salt rounds
- **SQL Injection Prevention** - Parameterized queries
- **XSS Protection** - httpOnly cookies, CSP headers

## 📊 Monitoring & Logging

### Structured Logging
```javascript
// Service-specific loggers
const logger = createLogger('ServiceName');

logger.info('Operation completed', { userId, duration });
logger.error('Operation failed', { error, context });
```

### Log Levels
- **debug:** Development debugging (not in production)
- **info:** General application flow
- **warn:** Warning conditions
- **error:** Error conditions requiring attention

### Health Checks
- **Application:** `GET /api/health`
- **Database:** Connection verification (including time-series tables)
- **Redis:** Cache connectivity

## 🚀 Deployment

### Production Checklist

1. **Environment Variables**
   - [ ] Set secure passwords for all services
   - [ ] Configure ALLOWED_ORIGINS for CORS
   - [ ] Set strong SESSION_SECRET

2. **Security**
   - [ ] Enable HTTPS with valid certificates
   - [ ] Configure firewall rules
   - [ ] Set up database backups

3. **Monitoring**
   - [ ] Configure log aggregation
   - [ ] Set up health check monitoring
   - [ ] Configure alerting

4. **Performance**
   - [ ] Set resource limits in Docker
   - [ ] Configure database connection pools
   - [ ] Enable Redis persistence

### Scaling

**Horizontal Scaling:**
```bash
# Scale application instances
docker-compose up -d --scale app=5

# Load balancer configuration required
```

**Database Optimization:**
- Connection pooling (configured)
- Read replicas or partitioning for PostgreSQL time-series tables
- Redis cluster for session storage

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Development Guidelines
- Follow TypeScript best practices
- Write tests for new features
- Use structured logging
- Follow the existing code style
- Update documentation

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation:** [docs/](./docs/)
- **Issues:** [GitHub Issues](https://github.com/contexus/contexus/issues)
- **Discussions:** [GitHub Discussions](https://github.com/contexus/contexus/discussions)

## 🎯 Roadmap

- [x] Multi-tenant architecture with workspace isolation
- [x] Flow Engine with visual workflow builder
- [x] Energy Management System with hierarchical spaces
- [x] MQTT Device Discovery and Property Mapping
- [x] Dashboard-Flow Integration
- [x] Plan Builder with GIS map support
- [x] SaaS Subscription Management
- [x] Virtual Points System for calculated data
- [ ] Mobile application (React Native)
- [ ] Advanced analytics dashboard
- [ ] Machine learning integration
- [ ] Kubernetes deployment
- [ ] GraphQL API
- [ ] WebRTC video streaming
- [ ] Blockchain integration for device identity

---

**Built with ❤️ by the contexus Team**
