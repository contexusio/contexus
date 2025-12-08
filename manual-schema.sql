-- Contexus IoT Platform - Complete Schema (40 Tables)
-- Use this file for manual schema creation if Docker init fails
-- Execute with: psql -U contexus -d contexus -f manual-schema.sql

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- TABLE 1: workspaces
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

-- TABLE 2: subscription_plans
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

-- TABLE 3: users
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

-- TABLE 4: workspace_users
CREATE TABLE IF NOT EXISTS workspace_users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(workspace_id, user_id)
);

-- TABLE 5: admin_users
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

-- TABLE 6: regular_users
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

-- TABLE 7: session
CREATE TABLE IF NOT EXISTS session (
    sid VARCHAR PRIMARY KEY,
    sess JSON NOT NULL,
    expire TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_session_expire ON session(expire);

-- TABLE 8: drivers
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

-- TABLE 9: products
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

-- TABLE 10: thing_models
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

-- TABLE 11: devices
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

-- TABLE 12: mqtt_discovered_devices
CREATE TABLE IF NOT EXISTS mqtt_discovered_devices (
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

-- TABLE 13: mqtt_message_buffer
CREATE TABLE IF NOT EXISTS mqtt_message_buffer (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    discovered_device_id VARCHAR NOT NULL REFERENCES mqtt_discovered_devices(id) ON DELETE CASCADE,
    topic VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT now() NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- TABLE 14: device_data
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

-- TABLE 15: device_property_cache
CREATE TABLE IF NOT EXISTS device_property_cache (
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

-- TABLE 16: dashboards
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

-- TABLE 17: floor_plans
CREATE TABLE IF NOT EXISTS floor_plans (
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

-- TABLE 18: floor_plan_templates
CREATE TABLE IF NOT EXISTS floor_plan_templates (
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

-- TABLE 19: hmi_diagrams
CREATE TABLE IF NOT EXISTS hmi_diagrams (
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

-- TABLE 20: rules
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

-- TABLE 21: rule_executions
CREATE TABLE IF NOT EXISTS rule_executions (
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

-- TABLE 22: alerts
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

-- TABLE 23: scenes
CREATE TABLE IF NOT EXISTS scenes (
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

-- TABLE 24: flows
CREATE TABLE IF NOT EXISTS flows (
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

-- TABLE 25: flow_execution_logs
CREATE TABLE IF NOT EXISTS flow_execution_logs (
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

-- TABLE 26: node_red_flows
CREATE TABLE IF NOT EXISTS node_red_flows (
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

-- TABLE 27: virtual_points
CREATE TABLE IF NOT EXISTS virtual_points (
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

-- TABLE 28: virtual_point_data
CREATE TABLE IF NOT EXISTS virtual_point_data (
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

-- TABLE 29: control_devices
CREATE TABLE IF NOT EXISTS control_devices (
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

-- TABLE 30: control_commands
CREATE TABLE IF NOT EXISTS control_commands (
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

-- TABLE 31: energy_meters
CREATE TABLE IF NOT EXISTS energy_meters (
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

-- TABLE 32: energy_readings
CREATE TABLE IF NOT EXISTS energy_readings (
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

-- TABLE 33: energy_consumption
CREATE TABLE IF NOT EXISTS energy_consumption (
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

-- TABLE 34: spaces
CREATE TABLE IF NOT EXISTS spaces (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id VARCHAR NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    type VARCHAR(50) NOT NULL,
    parent_id VARCHAR,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ
);

-- TABLE 35: space_meters
CREATE TABLE IF NOT EXISTS space_meters (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    space_id VARCHAR NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
    energy_meter_id VARCHAR NOT NULL REFERENCES energy_meters(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(space_id, energy_meter_id)
);

-- TABLE 36: system_config
CREATE TABLE IF NOT EXISTS system_config (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR(100) UNIQUE NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    category VARCHAR(50),
    is_public BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ
);

-- TABLE 37: system_branding
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

-- TABLE 38: system_metrics
CREATE TABLE IF NOT EXISTS system_metrics (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    cpu_usage REAL,
    memory_usage REAL,
    disk_usage REAL,
    active_connections INTEGER,
    request_count INTEGER,
    error_count INTEGER,
    timestamp TIMESTAMPTZ DEFAULT now()
);

-- TABLE 39: database_connections
CREATE TABLE IF NOT EXISTS database_connections (
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

-- TABLE 40: data_integration_jobs
CREATE TABLE IF NOT EXISTS data_integration_jobs (
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

-- INDEXES (Essential for performance)
CREATE INDEX IF NOT EXISTS idx_workspaces_slug ON workspaces(slug);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_devices_workspace_id ON devices(workspace_id);
CREATE INDEX IF NOT EXISTS idx_devices_device_key ON devices(device_key);
CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
CREATE INDEX IF NOT EXISTS idx_device_data_device_property_time ON device_data(device_id, property_name, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_device_data_timestamp ON device_data(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_dashboards_workspace_id ON dashboards(workspace_id);
CREATE INDEX IF NOT EXISTS idx_flows_workspace_id ON flows(workspace_id);
CREATE INDEX IF NOT EXISTS idx_rules_workspace_id ON rules(workspace_id);
CREATE INDEX IF NOT EXISTS idx_alerts_workspace_id ON alerts(workspace_id);
CREATE INDEX IF NOT EXISTS idx_energy_meters_workspace_id ON energy_meters(workspace_id);

-- DEFAULT DATA
INSERT INTO workspaces (id, name, slug, plan, is_active) 
VALUES ('default-workspace-id', 'Default Workspace', 'default', 'free', true)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO system_branding (id, site_title) 
VALUES ('default-branding-id', 'Contexus - Smart IoT Platform')
ON CONFLICT DO NOTHING;

-- Verification
SELECT 'Schema creation completed' as status, COUNT(*) as table_count 
FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

