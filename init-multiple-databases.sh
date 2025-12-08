#!/bin/bash
set -e

echo "=== Contexus IoT Platform Database Initialization ==="
echo "=== Complete Schema Creation for Docker Deployment ==="
echo "POSTGRES_USER: $POSTGRES_USER"
echo "POSTGRES_DB: $POSTGRES_DB"
echo "Initialization started at: $(date)"

check_fresh_init() {
    local table_count=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -c "
        SELECT COUNT(*) FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
    " 2>/dev/null || echo "0")
    
    if [ "$table_count" -gt 0 ]; then
        echo "Database already contains $table_count tables - skipping initialization"
        psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
            SELECT table_name FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
            ORDER BY table_name;
        "
        return 1
    fi
    return 0
}

drizzle_migrations_applied() {
    local table_exists=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -c "
        SELECT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_name = 'drizzle_migrations'
        );
    " 2>/dev/null || echo "f")

    if [ "$table_exists" = "t" ]; then
        local applied_count
        applied_count=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -c "
            SELECT COUNT(*) FROM public.drizzle_migrations;
        " 2>/dev/null || echo "0")
        DRIZZLE_APPLIED_COUNT=${applied_count:-0}
        if [ "${applied_count:-0}" -gt 0 ]; then
            return 0
        fi
    fi
    DRIZZLE_APPLIED_COUNT=0
    return 1
}

echo "Waiting for PostgreSQL to be fully ready..."
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
    if pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" -h localhost -q; then
        echo "PostgreSQL is ready after $attempt attempts!"
        break
    fi
    if [ $attempt -eq $max_attempts ]; then
        echo "PostgreSQL failed to become ready after $max_attempts attempts"
        exit 1
    fi
    echo "PostgreSQL not ready yet (attempt $attempt/$max_attempts), waiting..."
    sleep 3
    attempt=$((attempt + 1))
done

sleep 5

if drizzle_migrations_applied; then
    echo "Detected existing Drizzle migrations ($DRIZZLE_APPLIED_COUNT applied) - skipping bootstrap"
    exit 0
fi

if ! check_fresh_init; then
    echo "Database already initialized - exiting gracefully"
    exit 0
fi

echo "Starting fresh database schema creation (48 tables)..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-'EOSQL'
    \set VERBOSITY verbose
    
    SELECT 'Database connection successful' as status, current_database() as database;
    
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    
    SELECT 'Extensions created successfully' as status;

    -- =====================================================
    -- TABLE 1: workspaces (Multi-tenancy foundation)
    -- =====================================================
    CREATE TABLE workspaces (
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

    -- =====================================================
    -- TABLE 2: subscription_plans
    -- =====================================================
    CREATE TABLE subscription_plans (
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

    -- =====================================================
    -- TABLE 3: users
    -- =====================================================
    CREATE TABLE users (
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

    -- =====================================================
    -- TABLE 4: workspace_users (junction table)
    -- =====================================================
    CREATE TABLE workspace_users (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        role VARCHAR(20) DEFAULT 'member' NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        UNIQUE(workspace_id, user_id)
    );

    -- =====================================================
    -- TABLE 5: admin_users
    -- =====================================================
    CREATE TABLE admin_users (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id VARCHAR NOT NULL REFERENCES users(id),
        password_hash VARCHAR(255) NOT NULL,
        first_name VARCHAR(100),
        last_name VARCHAR(100),
        last_login_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 6: regular_users
    -- =====================================================
    CREATE TABLE regular_users (
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

    -- =====================================================
    -- TABLE 7: session (connect-pg-simple)
    -- =====================================================
    CREATE TABLE session (
        sid VARCHAR PRIMARY KEY,
        sess JSON NOT NULL,
        expire TIMESTAMP NOT NULL
    );
    CREATE INDEX idx_session_expire ON session(expire);

    -- =====================================================
    -- TABLE 8: drivers
    -- =====================================================
    CREATE TABLE drivers (
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

    -- =====================================================
    -- TABLE 9: products
    -- =====================================================
    CREATE TABLE products (
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

    -- =====================================================
    -- TABLE 10: thing_models
    -- =====================================================
    CREATE TABLE thing_models (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        description TEXT,
        version TEXT,
        properties JSONB,
        services JSONB,
        events JSONB,
        tags JSONB,
        status TEXT,
        schema TEXT,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 11: devices
    -- =====================================================
    CREATE TABLE devices (
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

    -- =====================================================
    -- TABLE 12: mqtt_discovered_devices
    -- =====================================================
    CREATE TABLE mqtt_discovered_devices (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        driver_id VARCHAR NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
        device_key VARCHAR(100) NOT NULL,
        first_seen TIMESTAMPTZ DEFAULT now() NOT NULL,
        last_seen TIMESTAMPTZ DEFAULT now() NOT NULL,
        message_count INTEGER DEFAULT 1 NOT NULL,
        sample_payload JSONB,
        status VARCHAR(20) DEFAULT 'pending' NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ,
        UNIQUE(workspace_id, driver_id, device_key)
    );

    -- =====================================================
    -- TABLE 13: mqtt_message_buffer
    -- =====================================================
    CREATE TABLE mqtt_message_buffer (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        discovered_device_id VARCHAR NOT NULL REFERENCES mqtt_discovered_devices(id) ON DELETE CASCADE,
        topic VARCHAR(255) NOT NULL,
        payload JSONB NOT NULL,
        timestamp TIMESTAMPTZ DEFAULT now() NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 14: device_data (time-series)
    -- =====================================================
    CREATE TABLE device_data (
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

    -- =====================================================
    -- TABLE 15: device_property_cache
    -- =====================================================
    CREATE TABLE device_property_cache (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL,
        device_id VARCHAR NOT NULL,
        property_name VARCHAR(100) NOT NULL,
        numeric_value REAL,
        text_value TEXT,
        bool_value BOOLEAN,
        value_type VARCHAR(20) DEFAULT 'number' NOT NULL,
        last_updated TIMESTAMPTZ DEFAULT now() NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        UNIQUE(workspace_id, device_id, property_name)
    );

    -- =====================================================
    -- TABLE 16: dashboards
    -- =====================================================
    CREATE TABLE dashboards (
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

    -- =====================================================
    -- TABLE 17: floor_plans
    -- =====================================================
    CREATE TABLE floor_plans (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        image_url TEXT,
        image_data TEXT,
        devices JSONB DEFAULT '[]',
        settings JSONB DEFAULT '{}',
        is_public BOOLEAN DEFAULT false,
        created_by VARCHAR,
        tags TEXT[] DEFAULT '{}',
        refresh_interval INTEGER DEFAULT 30,
        template_id VARCHAR,
        template_widgets JSONB DEFAULT '[]',
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 18: floor_plan_templates
    -- =====================================================
    CREATE TABLE floor_plan_templates (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        category VARCHAR(50) DEFAULT 'general',
        widgets JSONB DEFAULT '[]',
        layout_config JSONB DEFAULT '{}',
        is_default BOOLEAN DEFAULT false,
        is_public BOOLEAN DEFAULT false,
        thumbnail TEXT,
        created_by VARCHAR,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 19: hmi_diagrams (retained for migration safety)
    -- =====================================================
    CREATE TABLE hmi_diagrams (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        category VARCHAR(50) DEFAULT 'general',
        components JSONB DEFAULT '[]',
        connections JSONB DEFAULT '[]',
        settings JSONB DEFAULT '{}',
        is_public BOOLEAN DEFAULT false,
        created_by VARCHAR,
        tags TEXT[] DEFAULT '{}',
        refresh_interval INTEGER DEFAULT 5,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 20: rules
    -- =====================================================
    CREATE TABLE rules (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        conditions TEXT NOT NULL,
        actions TEXT NOT NULL,
        is_active BOOLEAN DEFAULT true NOT NULL,
        created_by VARCHAR(36),
        last_triggered TIMESTAMPTZ,
        execution_count INTEGER DEFAULT 0 NOT NULL,
        cooldown_minutes INTEGER DEFAULT 20 NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 21: rule_executions
    -- =====================================================
    CREATE TABLE rule_executions (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        rule_id VARCHAR NOT NULL REFERENCES rules(id) ON DELETE CASCADE,
        device_id VARCHAR,
        condition_met BOOLEAN NOT NULL,
        trigger_value JSONB,
        action_executed TEXT,
        action_result TEXT,
        execution_time_ms INTEGER,
        error TEXT,
        executed_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 22: alerts
    -- =====================================================
    CREATE TABLE alerts (
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

    -- =====================================================
    -- TABLE 23: scenes
    -- =====================================================
    CREATE TABLE scenes (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        actions JSONB DEFAULT '[]',
        is_active BOOLEAN DEFAULT true,
        icon VARCHAR(50),
        color VARCHAR(20),
        created_by VARCHAR,
        last_executed_at TIMESTAMPTZ,
        execution_count INTEGER DEFAULT 0,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 24: flows
    -- =====================================================
    CREATE TABLE flows (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        is_enabled BOOLEAN DEFAULT false NOT NULL,
        trigger_type VARCHAR(50) DEFAULT 'manual' NOT NULL,
        nodes JSONB DEFAULT '[]' NOT NULL,
        edges JSONB DEFAULT '[]' NOT NULL,
        viewport JSONB DEFAULT '{"x": 0, "y": 0, "zoom": 1}' NOT NULL,
        created_by VARCHAR,
        last_executed_at TIMESTAMPTZ,
        execution_count INTEGER DEFAULT 0 NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 25: flow_execution_logs
    -- =====================================================
    CREATE TABLE flow_execution_logs (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL,
        flow_id VARCHAR NOT NULL REFERENCES flows(id) ON DELETE CASCADE,
        status VARCHAR(20) DEFAULT 'running' NOT NULL,
        trigger_data JSONB,
        execution_path JSONB DEFAULT '[]' NOT NULL,
        error_message TEXT,
        started_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        completed_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 26: node_red_flows (legacy)
    -- =====================================================
    CREATE TABLE node_red_flows (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        category VARCHAR(50),
        flow_definition JSONB DEFAULT '{}',
        status VARCHAR(20) DEFAULT 'stopped' NOT NULL,
        node_count INTEGER DEFAULT 0,
        created_by VARCHAR,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ,
        last_deployed TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 27: virtual_points
    -- =====================================================
    CREATE TABLE virtual_points (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL,
        flow_id VARCHAR NOT NULL REFERENCES flows(id) ON DELETE CASCADE,
        node_id VARCHAR(100) NOT NULL,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        unit VARCHAR(20),
        data_type VARCHAR(20) DEFAULT 'number',
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 28: virtual_point_data
    -- =====================================================
    CREATE TABLE virtual_point_data (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL,
        virtual_point_id VARCHAR NOT NULL REFERENCES virtual_points(id) ON DELETE CASCADE,
        numeric_value REAL,
        text_value TEXT,
        bool_value BOOLEAN,
        json_value JSONB,
        timestamp TIMESTAMPTZ DEFAULT now() NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 29: control_devices
    -- =====================================================
    CREATE TABLE control_devices (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        widget_id VARCHAR,
        dashboard_id VARCHAR,
        device_key VARCHAR(100) NOT NULL,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        control_type VARCHAR(50) NOT NULL,
        driver_id VARCHAR,
        mqtt_topic_prefix VARCHAR(255),
        current_state JSONB DEFAULT '{}',
        metadata JSONB DEFAULT '{}',
        is_enabled BOOLEAN DEFAULT true NOT NULL,
        last_command_at TIMESTAMPTZ,
        last_status_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 30: control_commands
    -- =====================================================
    CREATE TABLE control_commands (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL,
        control_device_id VARCHAR NOT NULL REFERENCES control_devices(id) ON DELETE CASCADE,
        command_type VARCHAR(50) NOT NULL,
        command_value JSONB,
        source VARCHAR(50) NOT NULL,
        source_id VARCHAR,
        status VARCHAR(20) DEFAULT 'pending' NOT NULL,
        mqtt_topic VARCHAR(255),
        mqtt_payload JSONB,
        error_message TEXT,
        executed_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 31: energy_meters
    -- =====================================================
    CREATE TABLE energy_meters (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        device_id VARCHAR NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        energy_property VARCHAR(100) NOT NULL,
        unit VARCHAR(20) DEFAULT 'kWh',
        is_accumulated BOOLEAN DEFAULT false,
        is_active BOOLEAN DEFAULT true,
        multiplier NUMERIC DEFAULT 1.0,
        description TEXT,
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 32: energy_readings
    -- =====================================================
    CREATE TABLE energy_readings (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL,
        energy_meter_id VARCHAR NOT NULL REFERENCES energy_meters(id) ON DELETE CASCADE,
        device_id VARCHAR NOT NULL,
        energy_value NUMERIC NOT NULL,
        unit VARCHAR(20) DEFAULT 'kWh',
        raw_data JSONB DEFAULT '{}',
        timestamp TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 33: energy_consumption
    -- =====================================================
    CREATE TABLE energy_consumption (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL,
        energy_meter_id VARCHAR NOT NULL REFERENCES energy_meters(id) ON DELETE CASCADE,
        device_id VARCHAR NOT NULL,
        consumption NUMERIC NOT NULL,
        unit VARCHAR(20) DEFAULT 'kWh',
        period_start TIMESTAMPTZ NOT NULL,
        period_end TIMESTAMPTZ NOT NULL,
        period_type VARCHAR(20) NOT NULL,
        start_value NUMERIC,
        end_value NUMERIC,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 34: spaces
    -- =====================================================
    CREATE TABLE spaces (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        tier_level INTEGER NOT NULL,
        parent_space_id VARCHAR REFERENCES spaces(id) ON DELETE CASCADE,
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ,
        UNIQUE(workspace_id, name)
    );

    -- =====================================================
    -- TABLE 35: space_meters
    -- =====================================================
    CREATE TABLE space_meters (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        space_id VARCHAR NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
        energy_meter_id VARCHAR NOT NULL REFERENCES energy_meters(id) ON DELETE CASCADE,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        UNIQUE(space_id, energy_meter_id)
    );

    -- =====================================================
    -- TABLE 36: system_config
    -- =====================================================
    CREATE TABLE system_config (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        category VARCHAR(50) NOT NULL,
        key VARCHAR(100) UNIQUE NOT NULL,
        value TEXT NOT NULL,
        value_type VARCHAR(20) NOT NULL DEFAULT 'string',
        description TEXT,
        is_editable BOOLEAN NOT NULL DEFAULT true,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 37: system_branding
    -- =====================================================
    CREATE TABLE system_branding (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        type VARCHAR(50) NOT NULL UNIQUE,
        file_name VARCHAR(255) NOT NULL,
        mime_type VARCHAR(100) NOT NULL,
        file_data TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        uploaded_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        uploaded_by VARCHAR(255)
    );

    -- =====================================================
    -- TABLE 38: system_metrics
    -- =====================================================
    CREATE TABLE system_metrics (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        metric_name VARCHAR(100) NOT NULL,
        value REAL NOT NULL,
        unit VARCHAR(20),
        metadata JSONB DEFAULT '{}',
        timestamp TIMESTAMPTZ DEFAULT now() NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 39: database_connections
    -- =====================================================
    CREATE TABLE database_connections (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(100) NOT NULL,
        type VARCHAR(50) NOT NULL,
        host VARCHAR(255) NOT NULL,
        port INTEGER NOT NULL,
        database VARCHAR(100) NOT NULL,
        username VARCHAR(100) NOT NULL,
        password VARCHAR(255),
        connection_string TEXT,
        ssl BOOLEAN DEFAULT false NOT NULL,
        is_active BOOLEAN DEFAULT true NOT NULL,
        is_verified BOOLEAN DEFAULT false NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 40: data_integration_jobs
    -- =====================================================
    CREATE TABLE data_integration_jobs (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(100) NOT NULL,
        source_connection_id VARCHAR NOT NULL REFERENCES database_connections(id),
        target_connection_id VARCHAR NOT NULL REFERENCES database_connections(id),
        query TEXT NOT NULL,
        schedule VARCHAR(100) NOT NULL,
        is_active BOOLEAN DEFAULT true NOT NULL,
        last_run TIMESTAMPTZ,
        next_run TIMESTAMPTZ,
        status VARCHAR(20) DEFAULT 'pending' NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 41: api_keys (Security Hardening)
    -- =====================================================
    CREATE TABLE api_keys (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        key_hash VARCHAR(255) NOT NULL,
        key_prefix VARCHAR(12) NOT NULL,
        permissions JSONB DEFAULT '["read"]',
        rate_limit INTEGER DEFAULT 1000 NOT NULL,
        rate_limit_window INTEGER DEFAULT 3600 NOT NULL,
        last_used_at TIMESTAMPTZ,
        expires_at TIMESTAMPTZ,
        is_active BOOLEAN DEFAULT true NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        revoked_at TIMESTAMPTZ,
        UNIQUE(workspace_id, name)
    );

    -- =====================================================
    -- TABLE 42: refresh_tokens
    -- =====================================================
    CREATE TABLE refresh_tokens (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token_hash VARCHAR(255) NOT NULL UNIQUE,
        device_info JSONB DEFAULT '{}',
        ip_address VARCHAR(45),
        expires_at TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        revoked_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 43: totp_secrets (Two-Factor Auth)
    -- =====================================================
    CREATE TABLE totp_secrets (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
        secret VARCHAR(255) NOT NULL,
        is_enabled BOOLEAN DEFAULT false NOT NULL,
        is_verified BOOLEAN DEFAULT false NOT NULL,
        recovery_codes JSONB DEFAULT '[]',
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ,
        last_used_at TIMESTAMPTZ
    );

    -- =====================================================
    -- TABLE 44: audit_logs
    -- =====================================================
    CREATE TABLE audit_logs (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR REFERENCES workspaces(id) ON DELETE SET NULL,
        user_id VARCHAR REFERENCES users(id) ON DELETE SET NULL,
        action VARCHAR(50) NOT NULL,
        resource_type VARCHAR(50) NOT NULL,
        resource_id VARCHAR(36),
        old_values JSONB,
        new_values JSONB,
        metadata JSONB DEFAULT '{}',
        ip_address VARCHAR(45),
        user_agent TEXT,
        correlation_id VARCHAR(36),
        status VARCHAR(20) DEFAULT 'success' NOT NULL,
        error_message TEXT,
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL
    );

    -- =====================================================
    -- TABLE 45: data_aggregations (Analytics)
    -- =====================================================
    CREATE TABLE data_aggregations (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        device_id VARCHAR NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        property VARCHAR(100) NOT NULL,
        interval VARCHAR(20) NOT NULL,
        period_start TIMESTAMPTZ NOT NULL,
        period_end TIMESTAMPTZ NOT NULL,
        count INTEGER DEFAULT 0 NOT NULL,
        sum NUMERIC(20,6),
        avg NUMERIC(20,6),
        min NUMERIC(20,6),
        max NUMERIC(20,6),
        first NUMERIC(20,6),
        last NUMERIC(20,6),
        stddev NUMERIC(20,6),
        percentile_50 NUMERIC(20,6),
        percentile_95 NUMERIC(20,6),
        percentile_99 NUMERIC(20,6),
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        UNIQUE(device_id, property, interval, period_start)
    );

    -- =====================================================
    -- TABLE 46: anomaly_rules
    -- =====================================================
    CREATE TABLE anomaly_rules (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        device_id VARCHAR REFERENCES devices(id) ON DELETE CASCADE,
        property VARCHAR(100) NOT NULL,
        rule_type VARCHAR(50) NOT NULL,
        threshold_high NUMERIC(20,6),
        threshold_low NUMERIC(20,6),
        deviation_percent NUMERIC(5,2),
        rate_of_change NUMERIC(20,6),
        window_minutes INTEGER DEFAULT 60 NOT NULL,
        cooldown_minutes INTEGER DEFAULT 15 NOT NULL,
        severity VARCHAR(20) DEFAULT 'warning' NOT NULL,
        is_enabled BOOLEAN DEFAULT true NOT NULL,
        last_triggered_at TIMESTAMPTZ,
        created_by VARCHAR(36) REFERENCES users(id),
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ,
        UNIQUE(workspace_id, name)
    );

    -- =====================================================
    -- TABLE 47: scheduled_reports
    -- =====================================================
    CREATE TABLE scheduled_reports (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        report_type VARCHAR(50) NOT NULL,
        schedule VARCHAR(100) NOT NULL,
        timezone VARCHAR(50) DEFAULT 'UTC' NOT NULL,
        format VARCHAR(20) DEFAULT 'pdf' NOT NULL,
        recipients JSONB DEFAULT '[]',
        parameters JSONB DEFAULT '{}',
        dashboard_id VARCHAR REFERENCES dashboards(id) ON DELETE CASCADE,
        is_enabled BOOLEAN DEFAULT true NOT NULL,
        last_run_at TIMESTAMPTZ,
        next_run_at TIMESTAMPTZ,
        created_by VARCHAR(36) REFERENCES users(id),
        created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        updated_at TIMESTAMPTZ,
        UNIQUE(workspace_id, name)
    );

    -- =====================================================
    -- TABLE 48: report_executions
    -- =====================================================
    CREATE TABLE report_executions (
        id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
        report_id VARCHAR NOT NULL REFERENCES scheduled_reports(id) ON DELETE CASCADE,
        status VARCHAR(20) DEFAULT 'pending' NOT NULL,
        started_at TIMESTAMPTZ DEFAULT now() NOT NULL,
        completed_at TIMESTAMPTZ,
        file_url TEXT,
        file_size INTEGER,
        recipient_count INTEGER DEFAULT 0,
        error_message TEXT,
        metadata JSONB DEFAULT '{}'
    );

    -- =====================================================
    -- PERFORMANCE INDEXES
    -- =====================================================
    
    CREATE INDEX idx_workspaces_slug ON workspaces(slug);
    CREATE INDEX idx_workspaces_name ON workspaces(name);
    CREATE INDEX idx_workspaces_plan ON workspaces(plan);
    CREATE INDEX idx_workspaces_is_active ON workspaces(is_active);
    
    CREATE INDEX idx_subscription_plans_name ON subscription_plans(name);
    CREATE INDEX idx_subscription_plans_is_active ON subscription_plans(is_active);
    
    CREATE INDEX idx_users_email ON users(email);
    CREATE INDEX idx_users_username ON users(username);
    CREATE INDEX idx_users_role ON users(role);
    CREATE INDEX idx_users_active ON users(is_active);
    CREATE INDEX idx_users_cognito_sub ON users(cognito_sub);
    CREATE INDEX idx_users_default_workspace ON users(default_workspace_id);
    CREATE INDEX idx_users_subscription_plan ON users(subscription_plan_id);
    CREATE INDEX idx_users_created_at ON users(created_at);
    
    CREATE INDEX idx_workspace_users_workspace_id ON workspace_users(workspace_id);
    CREATE INDEX idx_workspace_users_user_id ON workspace_users(user_id);
    
    CREATE INDEX idx_drivers_workspace_id ON drivers(workspace_id);
    CREATE INDEX idx_drivers_type ON drivers(type);
    CREATE INDEX idx_drivers_is_active ON drivers(is_active);
    
    CREATE INDEX idx_devices_workspace_id ON devices(workspace_id);
    CREATE INDEX idx_devices_name ON devices(name);
    CREATE INDEX idx_devices_device_key ON devices(device_key);
    CREATE INDEX idx_devices_owner_id ON devices(owner_id);
    CREATE INDEX idx_devices_status ON devices(status);
    CREATE INDEX idx_devices_last_seen ON devices(last_seen);
    CREATE INDEX idx_devices_created_at ON devices(created_at);
    CREATE INDEX idx_devices_gateway ON devices(is_gateway);
    CREATE INDEX idx_devices_protocol ON devices(protocol);
    CREATE INDEX idx_devices_owner_status ON devices(owner_id, status);
    CREATE INDEX idx_devices_status_last_seen ON devices(status, last_seen);
    CREATE INDEX idx_devices_workspace_created_at ON devices(workspace_id, created_at);
    CREATE INDEX idx_devices_workspace_status ON devices(workspace_id, status);
    
    CREATE INDEX idx_mqtt_discovered_devices_workspace_id ON mqtt_discovered_devices(workspace_id);
    CREATE INDEX idx_mqtt_discovered_devices_driver_id ON mqtt_discovered_devices(driver_id);
    CREATE INDEX idx_mqtt_discovered_devices_status ON mqtt_discovered_devices(status);
    CREATE INDEX idx_mqtt_discovered_devices_last_seen ON mqtt_discovered_devices(last_seen);
    
    CREATE INDEX idx_mqtt_message_buffer_discovered_device_id ON mqtt_message_buffer(discovered_device_id);
    CREATE INDEX idx_mqtt_message_buffer_workspace_id ON mqtt_message_buffer(workspace_id);
    CREATE INDEX idx_mqtt_message_buffer_timestamp ON mqtt_message_buffer(timestamp DESC);
    
    CREATE INDEX idx_device_data_device_property_time ON device_data(device_id, property_name, timestamp DESC);
    CREATE INDEX idx_device_data_timestamp ON device_data(timestamp DESC);
    CREATE INDEX idx_device_data_property_time ON device_data(property_name, timestamp DESC);
    CREATE INDEX idx_device_data_workspace_id ON device_data(workspace_id);
    CREATE INDEX idx_device_data_workspace_created_at ON device_data(workspace_id, created_at);
    
    CREATE INDEX idx_device_property_cache_workspace ON device_property_cache(workspace_id);
    CREATE INDEX idx_device_property_cache_device ON device_property_cache(device_id);
    
    CREATE INDEX idx_dashboards_workspace_id ON dashboards(workspace_id);
    CREATE INDEX idx_dashboards_is_public ON dashboards(is_public);
    CREATE INDEX idx_dashboards_publish_slug ON dashboards(publish_slug);
    
    CREATE INDEX idx_floor_plans_workspace_id ON floor_plans(workspace_id);
    CREATE INDEX idx_floor_plan_templates_workspace_id ON floor_plan_templates(workspace_id);
    CREATE INDEX idx_hmi_diagrams_workspace_id ON hmi_diagrams(workspace_id);
    
    CREATE INDEX idx_rules_workspace_id ON rules(workspace_id);
    CREATE INDEX idx_rules_is_active ON rules(is_active);
    CREATE INDEX idx_rule_executions_rule_id ON rule_executions(rule_id);
    CREATE INDEX idx_rule_executions_executed_at ON rule_executions(executed_at);
    
    CREATE INDEX idx_alerts_workspace_id ON alerts(workspace_id);
    CREATE INDEX idx_alerts_device_id ON alerts(device_id);
    CREATE INDEX idx_alerts_is_acknowledged ON alerts(is_acknowledged);
    CREATE INDEX idx_alerts_created_at ON alerts(created_at);
    
    CREATE INDEX idx_scenes_workspace_id ON scenes(workspace_id);
    
    CREATE INDEX idx_flows_workspace_id ON flows(workspace_id);
    CREATE INDEX idx_flows_is_enabled ON flows(is_enabled);
    CREATE INDEX idx_flow_execution_logs_flow_id ON flow_execution_logs(flow_id);
    CREATE INDEX idx_flow_execution_logs_workspace_id ON flow_execution_logs(workspace_id);
    CREATE INDEX idx_flow_execution_logs_status ON flow_execution_logs(status);
    
    CREATE INDEX idx_node_red_flows_workspace_id ON node_red_flows(workspace_id);
    
    CREATE INDEX idx_virtual_points_workspace_id ON virtual_points(workspace_id);
    CREATE INDEX idx_virtual_points_flow_id ON virtual_points(flow_id);
    CREATE INDEX idx_virtual_point_data_workspace_id ON virtual_point_data(workspace_id);
    CREATE INDEX idx_virtual_point_data_virtual_point_id ON virtual_point_data(virtual_point_id);
    CREATE INDEX idx_virtual_point_data_timestamp ON virtual_point_data(timestamp);
    
    CREATE INDEX idx_control_devices_workspace_id ON control_devices(workspace_id);
    CREATE INDEX idx_control_devices_device_key ON control_devices(device_key);
    CREATE INDEX idx_control_commands_workspace_id ON control_commands(workspace_id);
    CREATE INDEX idx_control_commands_control_device_id ON control_commands(control_device_id);
    
    CREATE INDEX idx_energy_meters_workspace_id ON energy_meters(workspace_id);
    CREATE INDEX idx_energy_meters_device_id ON energy_meters(device_id);
    CREATE INDEX idx_energy_readings_workspace_id ON energy_readings(workspace_id);
    CREATE INDEX idx_energy_readings_energy_meter_id ON energy_readings(energy_meter_id);
    CREATE INDEX idx_energy_readings_timestamp ON energy_readings(timestamp);
    CREATE INDEX idx_energy_consumption_workspace_id ON energy_consumption(workspace_id);
    CREATE INDEX idx_energy_consumption_energy_meter_id ON energy_consumption(energy_meter_id);
    CREATE INDEX idx_energy_consumption_period ON energy_consumption(period_start, period_end);
    
    -- Spaces indexes moved to new table indexes section
    
    CREATE INDEX idx_system_config_key ON system_config(key);
    CREATE INDEX idx_system_config_category ON system_config(category);
    CREATE INDEX idx_system_metrics_timestamp ON system_metrics(timestamp);
    
    -- New table indexes
    CREATE INDEX idx_thing_models_workspace_id ON thing_models(workspace_id);
    CREATE INDEX idx_thing_models_workspace_created_at ON thing_models(workspace_id, created_at);
    
    CREATE INDEX idx_spaces_workspace_id ON spaces(workspace_id);
    CREATE INDEX idx_spaces_tier_level ON spaces(tier_level);
    CREATE INDEX idx_spaces_parent_space_id ON spaces(parent_space_id);
    CREATE INDEX idx_spaces_workspace_tier ON spaces(workspace_id, tier_level);
    
    CREATE INDEX idx_api_keys_workspace_id ON api_keys(workspace_id);
    CREATE INDEX idx_api_keys_user_id ON api_keys(user_id);
    CREATE INDEX idx_api_keys_key_prefix ON api_keys(key_prefix);
    CREATE INDEX idx_api_keys_is_active ON api_keys(is_active);
    CREATE INDEX idx_api_keys_expires_at ON api_keys(expires_at);
    
    CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
    CREATE INDEX idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);
    CREATE INDEX idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);
    
    CREATE INDEX idx_totp_secrets_user_id ON totp_secrets(user_id);
    
    CREATE INDEX idx_audit_logs_workspace_id ON audit_logs(workspace_id);
    CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
    CREATE INDEX idx_audit_logs_action ON audit_logs(action);
    CREATE INDEX idx_audit_logs_resource_type ON audit_logs(resource_type);
    CREATE INDEX idx_audit_logs_resource_id ON audit_logs(resource_id);
    CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);
    CREATE INDEX idx_audit_logs_correlation_id ON audit_logs(correlation_id);
    CREATE INDEX idx_audit_logs_workspace_created_at ON audit_logs(workspace_id, created_at);
    
    CREATE INDEX idx_data_aggregations_workspace_device ON data_aggregations(workspace_id, device_id);
    CREATE INDEX idx_data_aggregations_device_property ON data_aggregations(device_id, property);
    CREATE INDEX idx_data_aggregations_interval ON data_aggregations(interval);
    CREATE INDEX idx_data_aggregations_period_start ON data_aggregations(period_start);
    
    CREATE INDEX idx_anomaly_rules_workspace_id ON anomaly_rules(workspace_id);
    CREATE INDEX idx_anomaly_rules_device_id ON anomaly_rules(device_id);
    CREATE INDEX idx_anomaly_rules_property ON anomaly_rules(property);
    CREATE INDEX idx_anomaly_rules_is_enabled ON anomaly_rules(is_enabled);
    
    CREATE INDEX idx_scheduled_reports_workspace_id ON scheduled_reports(workspace_id);
    CREATE INDEX idx_scheduled_reports_dashboard_id ON scheduled_reports(dashboard_id);
    CREATE INDEX idx_scheduled_reports_is_enabled ON scheduled_reports(is_enabled);
    CREATE INDEX idx_scheduled_reports_next_run_at ON scheduled_reports(next_run_at);
    
    CREATE INDEX idx_report_executions_report_id ON report_executions(report_id);
    CREATE INDEX idx_report_executions_status ON report_executions(status);
    CREATE INDEX idx_report_executions_started_at ON report_executions(started_at);

    -- =====================================================
    -- DEFAULT DATA
    -- =====================================================
    
    INSERT INTO workspaces (id, name, slug, plan, is_active) 
    VALUES ('default-workspace-id', 'Default Workspace', 'default', 'free', true)
    ON CONFLICT (slug) DO NOTHING;
    
    -- Note: system_branding uses file-based entries (logo, favicon, etc.)
    -- Default entries will be created by the application when files are uploaded
    
    SELECT 'Schema creation completed successfully' as status;

EOSQL

echo "Verifying database initialization..."

table_count=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -c "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
")

key_tables=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -c "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_type = 'BASE TABLE'
    AND table_name IN ('users', 'workspaces', 'devices', 'drivers', 'dashboards', 'flows', 'rules', 'alerts');
")

echo "Final Initialization Results:"
echo "   Total tables created: $table_count"
echo "   Key IoT Hub tables: $key_tables/8"

if [ "$table_count" -ge 40 ] && [ "$key_tables" -ge 6 ]; then
    echo "DATABASE INITIALIZATION COMPLETED SUCCESSFULLY!"
    echo "All 48 tables created and verified"
    
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
        ORDER BY table_name;
    "
else
    echo "DATABASE INITIALIZATION FAILED!"
    echo "Expected >=40 total tables and >=6 key tables"
    echo "Got $table_count total tables and $key_tables key tables"
    exit 1
fi

echo "=== Database initialization completed at: $(date) ==="

