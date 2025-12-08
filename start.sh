#!/bin/bash
set -e

echo "🚀 Starting Contexus IoT Hub Application..."

# Clear any problematic NODE_OPTIONS and set correct ones
export NODE_OPTIONS="--max-old-space-size=1024"
echo "🔧 NODE_OPTIONS set to: $NODE_OPTIONS"

# Enhanced database parameter extraction with better error handling
extract_db_params() {
  if [[ -n "${DATABASE_URL:-}" ]]; then
    # Parse DATABASE_URL format: postgresql://user:password@host:port/database
    if [[ "$DATABASE_URL" =~ postgresql://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+) ]]; then
      DB_USER="${BASH_REMATCH[1]}"
      DB_PASSWORD="${BASH_REMATCH[2]}"
      DB_HOST="${BASH_REMATCH[3]}"
      DB_PORT="${BASH_REMATCH[4]}"
      DB_NAME="${BASH_REMATCH[5]}"
    else
      echo "❌ Invalid DATABASE_URL format" >&2
      return 1
    fi
  else
    # Use individual environment variables
    DB_USER="${POSTGRES_USER:-contexus}"
    DB_PASSWORD="${POSTGRES_PASSWORD:-contexus}"
    DB_HOST="${POSTGRES_HOST:-postgres}"
    DB_PORT="${POSTGRES_PORT:-5432}"
    DB_NAME="${POSTGRES_DB:-contexus}"
  fi
  
  # Validate all parameters are set
  if [[ -z "$DB_USER" || -z "$DB_PASSWORD" || -z "$DB_HOST" || -z "$DB_PORT" || -z "$DB_NAME" ]]; then
    echo "❌ Missing required database parameters" >&2
    return 1
  fi
  
  export DB_USER DB_PASSWORD DB_HOST DB_PORT DB_NAME
  return 0
}

# Standardized database query execution
execute_db_query() {
  local query="$1"
  local psql_options="${2:-}"
  
  if ! extract_db_params >/dev/null 2>&1; then
    echo "❌ Failed to extract database parameters" >&2
    return 1
  fi
  
  # Add tuples-only option if specified
  if [[ "$psql_options" == "tuples-only" ]]; then
    psql_options="-t -A"
  fi
  
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    $psql_options -c "$query" 2>/dev/null
}

# Execute SQL file
execute_sql_file() {
  local sql_file="$1"
  
  if ! extract_db_params >/dev/null 2>&1; then
    echo "❌ Failed to extract database parameters" >&2
    return 1
  fi
  
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -f "$sql_file" 2>&1
}

# Function to wait for a service with better error handling
wait_for() {
  local host=$1
  local port=$2
  local service_name=$3
  local max_attempts=60
  local attempt=1
  
  echo "⏳ Waiting for $service_name at $host:$port..."
  
  while [ $attempt -le $max_attempts ]; do
    if nc -z "$host" "$port" 2>/dev/null; then
      echo "✅ $service_name is ready at $host:$port"
      return 0
    fi
    
    echo "🔄 Attempt $attempt/$max_attempts: $service_name not ready, waiting..."
    sleep 2
    attempt=$((attempt + 1))
  done
  
  echo "❌ $service_name failed to become ready after $max_attempts attempts"
  return 1
}

# Enhanced PostgreSQL connection test
test_postgres_connection() {
  local max_attempts=30
  local attempt=1
  
  echo "🔍 Testing PostgreSQL connection..."
  
  while [ $attempt -le $max_attempts ]; do
    if extract_db_params >/dev/null 2>&1; then
      echo "🔍 Database connection details:"
      echo "   Host: $DB_HOST"
      echo "   Port: $DB_PORT"
      echo "   User: $DB_USER"
      echo "   Database: $DB_NAME"
      
      # Test basic connectivity
      if execute_db_query "SELECT 1;" "tuples-only" >/dev/null 2>&1; then
        echo "✅ PostgreSQL connection successful"
        return 0
      fi
    fi
    
    echo "⚠️ PostgreSQL connection failed, retrying in 3 seconds... (attempt $attempt/$max_attempts)"
    sleep 3
    attempt=$((attempt + 1))
  done
  
  echo "❌ PostgreSQL connection failed after $max_attempts attempts"
  return 1
}

# Get table count in public schema
get_table_count() {
  local count=$(execute_db_query "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
  " "tuples-only" 2>/dev/null | tr -d '\r\n ')
  echo "${count:-0}"
}

# Get key IoT tables count
get_key_tables_count() {
  local count=$(execute_db_query "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_type = 'BASE TABLE'
    AND table_name IN ('users', 'workspaces', 'devices', 'products', 'dashboards', 'drivers');
  " "tuples-only" 2>/dev/null | tr -d '\r\n ')
  echo "${count:-0}"
}

# Check if schema is ready
check_schema_ready() {
  local total_tables=$(get_table_count)
  local key_tables=$(get_key_tables_count)
  
  echo "🔍 Schema check: $total_tables total tables, $key_tables/6 key tables"
  
  # Need at least 15 tables and 4 key tables
  if [[ "${total_tables:-0}" -ge 15 && "${key_tables:-0}" -ge 4 ]]; then
    echo "✅ Schema verification PASSED"
    return 0
  else
    echo "❌ Schema verification FAILED (need >=15 total, >=4 key tables)"
    return 1
  fi
}

# Create schema using manual-schema.sql
create_schema_from_sql() {
  echo "🔧 Creating schema from manual-schema.sql..."
  
  local sql_file="/app/manual-schema.sql"
  if [[ ! -f "$sql_file" ]]; then
    sql_file="./manual-schema.sql"
  fi
  
  if [[ ! -f "$sql_file" ]]; then
    echo "❌ manual-schema.sql not found"
    return 1
  fi
  
  echo "📄 Found SQL file: $sql_file"
  
  if execute_sql_file "$sql_file"; then
    echo "✅ SQL schema executed successfully"
    return 0
  else
    echo "❌ SQL schema execution failed"
    return 1
  fi
}

# Create schema using Drizzle db:push
create_schema_with_drizzle() {
  echo "🔧 Creating schema with Drizzle db:push..."
  
  export NODE_OPTIONS="--max-old-space-size=1024"
  
  if timeout 180 npm run db:push 2>&1; then
    echo "✅ Drizzle db:push completed"
    return 0
  else
    echo "❌ Drizzle db:push failed"
    return 1
  fi
}

# Main schema initialization with multiple fallbacks
initialize_schema() {
  echo "🚀 INITIALIZING DATABASE SCHEMA"
  echo "================================"
  
  local tables_before=$(get_table_count)
  echo "📊 Tables before initialization: $tables_before"
  
  # If we already have tables, just verify
  if [[ "$tables_before" -ge 15 ]]; then
    echo "ℹ️ Database already has $tables_before tables"
    if check_schema_ready; then
      return 0
    fi
  fi
  
  # Strategy 1: Try Drizzle db:push first
  echo ""
  echo "📋 Strategy 1: Drizzle db:push"
  echo "------------------------------"
  if create_schema_with_drizzle; then
    sleep 3
    if check_schema_ready; then
      echo "✅ Schema created successfully with Drizzle"
      return 0
    fi
  fi
  
  # Strategy 2: Try manual SQL file
  echo ""
  echo "📋 Strategy 2: Manual SQL schema"
  echo "---------------------------------"
  if create_schema_from_sql; then
    sleep 3
    if check_schema_ready; then
      echo "✅ Schema created successfully from SQL file"
      return 0
    fi
  fi
  
  # Strategy 3: Inline essential tables creation
  echo ""
  echo "📋 Strategy 3: Inline essential tables"
  echo "---------------------------------------"
  create_essential_tables
  sleep 3
  if check_schema_ready; then
    echo "✅ Essential tables created inline"
    return 0
  fi
  
  echo "❌ All schema creation strategies failed"
  return 1
}

# Create essential tables inline as last resort
create_essential_tables() {
  echo "🔧 Creating essential tables inline..."
  
  execute_db_query "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";" || true
  execute_db_query "CREATE EXTENSION IF NOT EXISTS \"pgcrypto\";" || true
  
  # Create workspaces
  execute_db_query "
    CREATE TABLE IF NOT EXISTS workspaces (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      name VARCHAR(100) NOT NULL,
      slug VARCHAR(100) UNIQUE NOT NULL,
      logo TEXT,
      plan VARCHAR(50) DEFAULT 'free',
      device_limit INTEGER DEFAULT 10,
      dashboard_limit INTEGER DEFAULT 5,
      storage_limit INTEGER DEFAULT 1073741824,
      theme JSONB DEFAULT '{}',
      settings JSONB DEFAULT '{}',
      is_active BOOLEAN DEFAULT true,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Create subscription_plans
  execute_db_query "
    CREATE TABLE IF NOT EXISTS subscription_plans (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      name VARCHAR(100) UNIQUE NOT NULL,
      description TEXT,
      max_workspaces INTEGER DEFAULT 1,
      max_devices_per_workspace INTEGER DEFAULT 10,
      max_dashboards_per_workspace INTEGER DEFAULT 5,
      max_storage_per_workspace INTEGER DEFAULT 1073741824,
      data_retention_days INTEGER DEFAULT 30,
      price DECIMAL(10,2) DEFAULT 0,
      billing_period VARCHAR(20) DEFAULT 'monthly',
      is_active BOOLEAN DEFAULT true,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Create users
  execute_db_query "
    CREATE TABLE IF NOT EXISTS users (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      username VARCHAR(255) UNIQUE NOT NULL,
      email VARCHAR(255) UNIQUE NOT NULL,
      password VARCHAR(255),
      role VARCHAR(20) DEFAULT 'user' NOT NULL,
      is_active BOOLEAN DEFAULT true NOT NULL,
      is_cognito_user BOOLEAN DEFAULT false NOT NULL,
      cognito_sub VARCHAR(255),
      default_workspace_id VARCHAR REFERENCES workspaces(id),
      subscription_plan_id VARCHAR REFERENCES subscription_plans(id),
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Create drivers
  execute_db_query "
    CREATE TABLE IF NOT EXISTS drivers (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      name VARCHAR(100) NOT NULL,
      type VARCHAR(50) NOT NULL,
      version VARCHAR(20),
      description TEXT,
      protocol VARCHAR(50),
      author VARCHAR(100),
      configuration JSONB DEFAULT '{}',
      dependencies JSONB DEFAULT '[]',
      documentation TEXT,
      owner_id VARCHAR,
      is_active BOOLEAN DEFAULT true NOT NULL,
      license VARCHAR(50),
      script_content TEXT,
      supported_devices TEXT[] DEFAULT '{}',
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Create products
  execute_db_query "
    CREATE TABLE IF NOT EXISTS products (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      name VARCHAR(100) NOT NULL,
      description TEXT,
      manufacturer VARCHAR(100),
      model VARCHAR(100),
      version VARCHAR(50),
      protocol VARCHAR(50),
      data_format JSONB DEFAULT '{}',
      configuration JSONB DEFAULT '{}',
      created_at TIMESTAMP DEFAULT now(),
      updated_at TIMESTAMP,
      is_active BOOLEAN DEFAULT true,
      category VARCHAR(50),
      tags TEXT[],
      documentation_url TEXT,
      support_url TEXT,
      icon_url TEXT
    );
  " || true
  
  # Create thing_models
  execute_db_query "
    CREATE TABLE IF NOT EXISTS thing_models (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      name VARCHAR(100) NOT NULL,
      description TEXT,
      schema JSONB DEFAULT '{}' NOT NULL,
      version VARCHAR(50) DEFAULT '1.0.0',
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ,
      is_active BOOLEAN DEFAULT true,
      category VARCHAR(50),
      tags TEXT[] DEFAULT '{}'
    );
  " || true
  
  # Create devices
  execute_db_query "
    CREATE TABLE IF NOT EXISTS devices (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      name VARCHAR(100) NOT NULL,
      device_key VARCHAR(100),
      thing_model_id VARCHAR REFERENCES thing_models(id),
      owner_id VARCHAR,
      driver_id VARCHAR REFERENCES drivers(id) ON DELETE CASCADE,
      status VARCHAR(20) DEFAULT 'offline' NOT NULL,
      last_seen TIMESTAMPTZ,
      location TEXT,
      metadata JSONB DEFAULT '{}',
      firmware_version VARCHAR(50),
      hardware_version VARCHAR(50),
      battery_level REAL,
      connection_string TEXT,
      is_gateway BOOLEAN DEFAULT false,
      notes TEXT,
      parent_device_id VARCHAR,
      protocol VARCHAR(50),
      signal_strength REAL,
      tags JSONB DEFAULT '[]',
      temperature REAL,
      humidity REAL,
      property_mappings JSONB DEFAULT '[]',
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ,
      UNIQUE(workspace_id, device_key)
    );
  " || true
  
  # Create dashboards
  execute_db_query "
    CREATE TABLE IF NOT EXISTS dashboards (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      name VARCHAR(100) NOT NULL,
      description TEXT,
      layout JSONB DEFAULT '{}',
      widgets JSONB DEFAULT '[]',
      is_public BOOLEAN DEFAULT false,
      is_template BOOLEAN DEFAULT false,
      is_external_public BOOLEAN DEFAULT false,
      publish_slug VARCHAR(100),
      created_by VARCHAR REFERENCES users(id),
      shared_with TEXT[] DEFAULT '{}',
      tags TEXT[] DEFAULT '{}',
      refresh_interval INTEGER DEFAULT 30,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Create session table
  execute_db_query "
    CREATE TABLE IF NOT EXISTS session (
      sid VARCHAR PRIMARY KEY,
      sess JSON NOT NULL,
      expire TIMESTAMP NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_session_expire ON session(expire);
  " || true
  
  # Create workspace_users
  execute_db_query "
    CREATE TABLE IF NOT EXISTS workspace_users (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role VARCHAR(20) DEFAULT 'member' NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      UNIQUE(workspace_id, user_id)
    );
  " || true
  
  # Create admin_users
  execute_db_query "
    CREATE TABLE IF NOT EXISTS admin_users (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id VARCHAR NOT NULL REFERENCES users(id),
      password_hash VARCHAR(255) NOT NULL,
      first_name VARCHAR(100),
      last_name VARCHAR(100),
      last_login_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Create regular_users
  execute_db_query "
    CREATE TABLE IF NOT EXISTS regular_users (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id VARCHAR NOT NULL REFERENCES users(id),
      password_hash VARCHAR(255) NOT NULL,
      first_name VARCHAR(100),
      last_name VARCHAR(100),
      approval_status VARCHAR(20) DEFAULT 'pending' NOT NULL,
      auth_provider VARCHAR(50) DEFAULT 'local',
      email_verified BOOLEAN DEFAULT false NOT NULL,
      email_verification_token VARCHAR(255),
      token_expires_at TIMESTAMPTZ,
      last_login_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Create device_data
  execute_db_query "
    CREATE TABLE IF NOT EXISTS device_data (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      device_id VARCHAR NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
      timestamp TIMESTAMPTZ DEFAULT now() NOT NULL,
      property_name VARCHAR(100) NOT NULL,
      data_type VARCHAR(50) DEFAULT 'sensor_data' NOT NULL,
      numeric_value REAL,
      text_value TEXT,
      bool_value BOOLEAN,
      json_value JSONB,
      value_type VARCHAR(20) DEFAULT 'number' NOT NULL,
      unit VARCHAR(20),
      quality INTEGER DEFAULT 100,
      source VARCHAR(100),
      processed BOOLEAN DEFAULT false,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_device_data_lookup ON device_data(device_id, property_name, timestamp DESC);
  " || true
  
  # Create rules
  execute_db_query "
    CREATE TABLE IF NOT EXISTS rules (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      name VARCHAR(100) NOT NULL,
      description TEXT,
      conditions TEXT NOT NULL,
      actions TEXT NOT NULL,
      is_active BOOLEAN DEFAULT true NOT NULL,
      created_by VARCHAR,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Create alerts
  execute_db_query "
    CREATE TABLE IF NOT EXISTS alerts (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      message TEXT NOT NULL,
      level TEXT DEFAULT 'info' NOT NULL,
      source TEXT,
      source_id VARCHAR,
      device_id VARCHAR,
      rule_id VARCHAR,
      is_acknowledged BOOLEAN DEFAULT false NOT NULL,
      acknowledged_by VARCHAR,
      acknowledged_at TIMESTAMP,
      resolved_at TIMESTAMP,
      metadata JSONB DEFAULT '{}',
      created_at TIMESTAMP DEFAULT now() NOT NULL,
      created_by VARCHAR
    );
  " || true
  
  # Create flows
  execute_db_query "
    CREATE TABLE IF NOT EXISTS flows (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      name VARCHAR(100) NOT NULL,
      description TEXT,
      is_enabled BOOLEAN DEFAULT false NOT NULL,
      trigger_type VARCHAR(50) DEFAULT 'manual' NOT NULL,
      nodes JSONB DEFAULT '[]' NOT NULL,
      edges JSONB DEFAULT '[]' NOT NULL,
      viewport JSONB DEFAULT '{\"x\": 0, \"y\": 0, \"zoom\": 1}' NOT NULL,
      created_by VARCHAR,
      last_executed_at TIMESTAMPTZ,
      execution_count INTEGER DEFAULT 0 NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Create system_branding
  execute_db_query "
    CREATE TABLE IF NOT EXISTS system_branding (
      id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
      login_background TEXT,
      platform_logo TEXT,
      site_title VARCHAR(100) DEFAULT 'Contexus - Smart IoT Platform',
      primary_color VARCHAR(20),
      secondary_color VARCHAR(20),
      favicon TEXT,
      created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
      updated_at TIMESTAMPTZ
    );
  " || true
  
  # Insert default data
  execute_db_query "
    INSERT INTO workspaces (id, name, slug, plan, is_active) 
    VALUES ('default-workspace-id', 'Default Workspace', 'default', 'free', true)
    ON CONFLICT (slug) DO NOTHING;
  " || true
  
  execute_db_query "
    INSERT INTO system_branding (id, site_title) 
    VALUES ('default-branding-id', 'Contexus - Smart IoT Platform')
    ON CONFLICT DO NOTHING;
  " || true
  
  echo "✅ Essential tables creation attempted"
}

# MAIN EXECUTION FLOW
echo "🔍 STARTING ENHANCED STARTUP PROCESS"
echo "===================================="

# Wait for services
if ! wait_for postgres 5432 "PostgreSQL"; then
  echo "⚠️ PostgreSQL not found at postgres:5432, trying localhost..."
  if ! wait_for localhost 5432 "PostgreSQL"; then
    echo "❌ PostgreSQL service check failed"
    exit 1
  fi
fi

# Try Redis but don't fail if not available
if wait_for redis 6379 "Redis"; then
  echo "✅ Redis is available"
else
  echo "⚠️ Redis not available, continuing without it..."
fi

# Additional wait for PostgreSQL to fully initialize
echo "🔧 Waiting 10 seconds for PostgreSQL to fully initialize..."
sleep 10

# Test PostgreSQL connection
if ! test_postgres_connection; then
  echo "❌ Failed to establish PostgreSQL connection"
  exit 1
fi

# Schema initialization process
echo ""
echo "📋 Checking if database schema exists..."
echo "========================================="

if check_schema_ready; then
  echo "✅ Database schema already exists and is ready"
else
  echo "❌ Database schema not found or incomplete"
  echo ""
  echo "📋 Initializing database schema..."
  
  if initialize_schema; then
    echo "✅ Schema initialization completed successfully"
  else
    echo "❌ Failed to initialize database schema"
    echo ""
    echo "💡 TROUBLESHOOTING:"
    echo "   1. Clean Docker volumes: docker-compose down -v"
    echo "   2. Remove data directory: rm -rf ./data/postgres/*"
    echo "   3. Restart: docker-compose up -d"
    echo ""
    echo "   Or manually run: docker exec -i contexus-postgres psql -U contexus -d contexus < manual-schema.sql"
    exit 1
  fi
fi

# Final verification
echo ""
echo "🔍 Final schema verification..."
final_tables=$(get_table_count)
final_key_tables=$(get_key_tables_count)

echo "📊 Final count: $final_tables total tables, $final_key_tables/6 key tables"

if [[ "$final_tables" -ge 10 && "$final_key_tables" -ge 4 ]]; then
  echo "========================================"
  echo "🚀 DATABASE INITIALIZATION COMPLETE!"
  echo "🚀 Starting Contexus IoT Hub Application..."
  echo "========================================"
  
  export NODE_OPTIONS="--max-old-space-size=1024"
  exec node dist/server/index.js
else
  echo "❌ Schema verification failed after all attempts"
  echo "   Total tables: $final_tables (need >=10)"
  echo "   Key tables: $final_key_tables (need >=4)"
  exit 1
fi
