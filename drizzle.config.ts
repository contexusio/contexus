import { defineConfig } from 'drizzle-kit';
import { config } from 'dotenv';
import path from 'path';

// Enhanced environment loading with explicit path resolution
const envPath = process.env.NODE_ENV === 'production' 
  ? path.resolve(process.cwd(), '.env')
  : path.resolve(process.cwd(), '.env.local');

console.log(`🔍 Drizzle loading environment from: ${envPath}`);

// Load environment with enhanced error handling
try {
  const result = config({ path: envPath });
  if (result.error) {
    console.warn(`⚠️ Environment file load warning: ${result.error.message}`);
  } else {
    console.log(`✅ Environment loaded successfully from ${envPath}`);
  }
} catch (error) {
  console.warn(`⚠️ Failed to load environment file: ${error.message}`);
}

// Enhanced DATABASE_URL validation with connection consistency
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  throw new Error('DATABASE_URL environment variable is required for Drizzle configuration');
}

// Validate DATABASE_URL format and extract components for consistency
const urlRegex = /^postgresql:\/\/([^:]+):([^@]+)@([^:]+):(\d+)\/(.+)$/;
const urlMatch = databaseUrl.match(urlRegex);

if (!urlMatch) {
  throw new Error(`Invalid DATABASE_URL format. Expected: postgresql://user:password@host:port/database`);
}

const [, user, password, host, port, database] = urlMatch;

console.log(`🔍 Drizzle configuration validated for connection consistency:`);
console.log(`   Host: ${host}`);
console.log(`   Port: ${port}`);
console.log(`   User: ${user}`);
console.log(`   Database: ${database}`);
console.log(`   URL: ${databaseUrl.replace(/:[^:@]*@/, ':***@')}`);

// Explicit schema targeting for consistency
const targetSchema = 'public';
console.log(`🔍 Target schema (explicit): ${targetSchema}`);

export default defineConfig({
  schema: './shared/unified-schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: {
    url: databaseUrl,
  },
  verbose: true,
  strict: true,
  // Explicit schema targeting to match verification queries
  schemaFilter: [targetSchema],
  // Enhanced migration configuration with explicit schema
  migrations: {
    prefix: 'timestamp',
    table: 'drizzle_migrations',
    schema: targetSchema,
  },
  // Add introspection options for better schema detection consistency
  introspect: {
    casing: 'preserve',
  },
  // Ensure consistent schema handling
  tablesFilter: ['*'], // Include all tables
  // Remove pooling configuration that might conflict with runtime connection factory
  // Let the runtime connection factory handle pooling
});
