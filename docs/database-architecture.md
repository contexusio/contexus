# contexus IoT Platform - Unified PostgreSQL Database Architecture

## Overview

The contexus IoT platform uses a sophisticated unified database architecture optimized for both configuration and time-series data:

- **PostgreSQL**: Unified database for configuration, administrative data, and time-series IoT sensor data
- **Redis**: High-performance caching, session management, and real-time data temporary storage

## Architecture Benefits

### Unified PostgreSQL Database
- **ACID compliance** for all data operations ensuring consistency
- **Single source of truth** eliminating cross-database synchronization complexity
- **Advanced indexing** with composite indexes for optimal time-series queries
- **JSONB support** for flexible metadata and configuration storage
- **Multi-tenancy support** via workspace-based data isolation
- **Horizontal scaling** capabilities with connection pooling
- **Enterprise-grade features** with full transaction support

### Redis Integration
- **Session caching** with PostgreSQL persistence for scalability
- **Real-time data caching** for live dashboard updates
- **Query result caching** for frequently accessed configuration data
- **Rate limiting** protection for API endpoints
- **High-performance temporary storage** with configurable TTL

## Database Schema

### Unified PostgreSQL Schema (`shared/unified-schema.ts`)

**Configuration & Management Tables:**
- `workspaces` - Multi-tenancy with subscription-based access control
- `users` - User accounts with role-based permissions (admin/user)
- `users_sessions` - PostgreSQL-backed session management
- `devices` - Device registry with hierarchical relationships and metadata
- `products` - Device templates and product definitions
- `dashboards` - Configurable dashboards with widget layouts
- `floor_plans` - Visual device placement with template system

**Time-Series & Operational Tables:**
- `device_data` - High-volume sensor readings with composite indexes
- `device_energy_data` - Specialized energy consumption tracking
- `system_metrics` - Platform performance monitoring data

**Key Features:**
- **UUID primary keys** for distributed system compatibility
- **Composite indexes** on (device_id, property_key, timestamp) for fast time-series queries
- **JSONB columns** for flexible metadata storage
- **Workspace-based data isolation** for multi-tenancy
- **Optimized data types** for efficient storage and retrieval

## Connection Factory Pattern

### DatabaseConnectionFactory (`server/database/connection-factory.ts`)

The `DatabaseConnectionFactory` provides enterprise-grade connection management:

**Core Features:**
- **Connection pooling** with configurable limits (default: 25 connections)
- **Circuit breaker pattern** prevents cascading database failures
- **Automatic retry logic** with exponential backoff
- **Health monitoring** with periodic connection validation
- **Graceful shutdown** handling for production deployments
- **Multi-database management** (PostgreSQL + Redis)

**Configuration:**
```typescript
// Example connection factory configuration
const factory = new DatabaseConnectionFactory({
  postgres: {
    maxConnections: 25,
    connectionTimeout: 30000,
    healthCheckInterval: 30000,
    retryAttempts: 3,
    retryDelay: 1000
  },
  redis: {
    maxConnections: 10,
    connectionTimeout: 5000,
    retryAttempts: 3
  }
});
```

## Data Flow

### Configuration Data Flow
```
User Action → API Endpoint → Authentication → Storage Layer → PostgreSQL
                ↓                                    ↓
         WebSocket Notification                 Redis Cache
                ↓                                    ↓
            Client Update ← ← ← ← ← ← ← ← ← ← ← ← ← ← ←
```

### Time-Series Data Flow
```
IoT Device → LoRaWAN Gateway → ChirpStack → Webhook Handler → Storage Layer
                                                                  ↓
                                          Real-time Processing → PostgreSQL
                                                                  ↓
                                          Aggregation & Rules Engine
                                                                  ↓
                                          Dashboard Updates ← Redis Cache
```

### Storage Abstraction Layer

The storage layer (`server/storage/`) provides:
- **Type-safe operations** using Drizzle ORM schemas
- **Automatic connection management** via connection factory
- **Health checking** and fallback mechanisms
- **Query optimization** with proper indexing strategies
- **Workspace-based data isolation** for multi-tenancy

## Performance Characteristics

### PostgreSQL (Unified Database)
- **Read latency**: Sub-millisecond for indexed queries
- **Write throughput**: 10,000+ inserts/second with connection pooling
- **Concurrency**: Full ACID compliance with MVCC
- **Time-series queries**: Optimized with composite indexes
- **Storage efficiency**: JSONB compression and TOAST for large values

### Redis (Caching Layer)
- **Session lookup**: Sub-millisecond access times
- **Cache hit rate**: 95%+ for frequently accessed data
- **Memory management**: LRU eviction with configurable policies
- **Persistence**: Optional RDB snapshots for backup

## Development Workflow

### Environment Setup
```bash
# Install all dependencies
npm install

# Start development server with hot reload
npm run dev

# Type checking and validation
npm run check
```

### Database Operations
```bash
# Generate migration files from schema changes
npm run db:generate

# Apply schema changes directly (development only)
npm run db:push

# Run database migrations (production)
npm run db:migrate

# Open Drizzle Studio for database GUI
npm run db:studio
```

### Docker Development
```bash
# Start development environment with databases
docker-compose -f docker-compose.dev.yml up -d

# Start full production stack
docker-compose up -d

# View application logs
docker-compose logs -f app

# Stop all services
docker-compose down
```

## Deployment Configuration

### Environment Variables
```bash
# Required for production deployment
DATABASE_URL=postgresql://user:secure_password@host:5432/database
REDIS_URL=redis://:secure_redis_password@host:6379
SESSION_SECRET=256_bit_secure_random_string
ADMIN_PASSWORD=strong_admin_password
ALLOWED_ORIGINS=https://yourdomain.com,https://app.yourdomain.com
```

### Production Deployment
```bash
# Full production stack with all services
docker-compose up -d

# Scale application instances for load balancing
docker-compose up -d --scale app=3

# View application logs
docker-compose logs -f app
```

## Scaling Considerations

### Horizontal Scaling
- **Application layer**: Stateless design supports multiple instances
- **Database layer**: PostgreSQL read replicas for query scaling
- **Connection pooling**: Shared connection pool across application instances
- **Load balancing**: Requires external load balancer for multiple app instances
- **Session management**: PostgreSQL-backed sessions work across instances

### Performance Optimization
- **Composite indexes** for device + time range queries
- **Connection pooling** with configurable limits
- **Redis caching** for frequently accessed configuration data
- **Query optimization** with proper indexing strategies
- **Workspace isolation** for multi-tenant query performance

## Backup Strategy

### PostgreSQL Backup
```bash
# Full database backup
pg_dump -Fc $DATABASE_URL > backup/postgres-full-$(date +%Y%m%d).dump

# Point-in-time recovery setup
pg_basebackup -h localhost -D backup/base -U postgres -v -P -W

# Continuous WAL archiving for production
archive_command = 'cp %p /backup/wal/%f'
```

### Redis Backup
```bash
# RDB snapshot backup
redis-cli BGSAVE
cp /var/lib/redis/dump.rdb backup/redis-$(date +%Y%m%d).rdb

# AOF backup for durability
redis-cli BGREWRITEAOF
cp /var/lib/redis/appendonly.aof backup/redis-aof-$(date +%Y%m%d).aof
```

### Automated Backup Script
```bash
#!/bin/bash
# Daily backup script
DATE=$(date +%Y%m%d)
BACKUP_DIR="/backup/daily"

# PostgreSQL backup
pg_dump -Fc $DATABASE_URL > $BACKUP_DIR/postgres-$DATE.dump

# Redis backup
redis-cli BGSAVE
cp /var/lib/redis/dump.rdb $BACKUP_DIR/redis-$DATE.rdb

# Cleanup old backups (keep 30 days)
find $BACKUP_DIR -name "*.dump" -mtime +30 -delete
find $BACKUP_DIR -name "*.rdb" -mtime +30 -delete
```

## Development Guidelines

### Schema Changes Workflow
1. **Edit unified schema** in `shared/unified-schema.ts`
2. **Generate migration files** with `npm run db:generate`
3. **Test locally** using `npm run db:push` for rapid iteration
4. **Review migration files** before applying to production
5. **Apply production migrations** using `npm run db:migrate`

### Adding New Tables
1. Define table in `shared/unified-schema.ts` with proper indexes
2. Include workspace_id for multi-tenancy if applicable
3. Add appropriate Zod schemas for runtime validation
4. Implement storage methods in `server/storage/`
5. Add type definitions in `shared/types.ts`

### Query Optimization Best Practices
- **Use composite indexes** for device + time range queries
- **Implement workspace filtering** at the database level
- **Use prepared statements** for repeated queries
- **Monitor query performance** with `EXPLAIN ANALYZE`
- **Optimize JSONB queries** with GIN indexes when needed
- **Implement proper pagination** for large result sets

## Monitoring and Observability

### Health Monitoring
- **Application health**: `GET /api/health`
- **Database status**: PostgreSQL connection and table verification
- **Redis status**: Cache connectivity and performance metrics
- **Circuit breaker status**: External service health monitoring

### Metrics Collection
- **Connection pool utilization**: Monitor active vs idle connections
- **Query performance**: Track slow queries and optimization opportunities
- **Cache hit rates**: Redis effectiveness for session and query caching
- **Ingestion rates**: Device data throughput and processing times
- **Workspace metrics**: Per-tenant resource usage and performance

### Logging Strategy
- **Structured logging** with `server/utils/logger.ts`
- **Database operation logging** with query context
- **Connection factory events** for health monitoring
- **Performance metrics** for optimization analysis

## Security Considerations

### Database Security
- **Connection encryption** using SSL/TLS
- **Principle of least privilege** for database users
- **Row-level security** for workspace data isolation
- **Audit logging** for data access and modifications
- **Regular security updates** for PostgreSQL and Redis

### Session Management
- **Secure session storage** in PostgreSQL with Redis caching
- **Session TTL management** with automatic cleanup
- **Secure cookie configuration** (httpOnly, secure, SameSite)
- **Session fixation protection** with regeneration on login

This unified PostgreSQL architecture provides the contexus IoT platform with optimal performance characteristics for both configuration and time-series data while maintaining development simplicity, deployment flexibility, and enterprise-grade reliability.