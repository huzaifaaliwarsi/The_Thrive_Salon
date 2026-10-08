const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const bcrypt = require('bcryptjs');

const config = {
  host: '127.0.0.1',
  port: 5432,
  user: 'postgres',
  password: 'admin123'
};

async function main() {
  console.log('Connecting to PostgreSQL on 127.0.0.1:5432 as postgres...');
  
  // 1. Ensure thrive_local database exists
  const adminClient = new Client({ ...config, database: 'postgres' });
  await adminClient.connect();
  try {
    const res = await adminClient.query("SELECT 1 FROM pg_database WHERE datname = 'thrive_local'");
    if (res.rowCount === 0) {
      console.log('Creating database thrive_local...');
      await adminClient.query('CREATE DATABASE thrive_local');
    } else {
      console.log('Database thrive_local already exists.');
    }
  } finally {
    await adminClient.end();
  }

  // 2. Connect to thrive_local
  const db = new Client({ ...config, database: 'thrive_local' });
  await db.connect();
  console.log('Connected to thrive_local.');

  try {
    // Check if tables already exist
    const userTable = await db.query("SELECT to_regclass('public.users') AS users");
    if (!userTable.rows[0].users) {
      console.log('Applying structure-compatible.sql schema...');
      const sqlFile = path.join(__dirname, 'structure-compatible.sql');
      const dump = fs.readFileSync(sqlFile, 'utf8')
        .split(/\r?\n/)
        .filter(line => !/^ALTER .* OWNER TO |^(GRANT|REVOKE) |^SET default_with_oids|^\\(restrict|unrestrict)\b/.test(line))
        .join('\n');
      
      await db.query('BEGIN');
      await db.query(dump);
      await db.query('SET search_path TO public');

      // UUID defaults
      const tables = await db.query("SELECT table_name FROM information_schema.columns WHERE table_schema='public' AND column_name='id' AND data_type='uuid'");
      for (const { table_name } of tables.rows) {
        if (/^[a-z_]+$/.test(table_name)) {
          await db.query(`ALTER TABLE public."${table_name}" ALTER COLUMN id SET DEFAULT gen_random_uuid()`);
        }
      }
      await db.query('COMMIT');
      console.log('Base schema applied successfully.');
    } else {
      console.log('Base tables already exist.');
    }

    // Step 1: payment_accounts and sales columns
    await db.query('BEGIN');
    console.log('Ensuring payment_accounts table exists...');
    await db.query(`
      CREATE TABLE IF NOT EXISTS public.payment_accounts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        salon_id UUID NOT NULL REFERENCES public.salons(id) ON DELETE CASCADE,
        account_name TEXT NOT NULL,
        account_title TEXT,
        account_number TEXT,
        iban TEXT,
        type TEXT DEFAULT 'BANK',
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now()
      );
    `);
    await db.query('ALTER TABLE public.payment_accounts ADD COLUMN IF NOT EXISTS iban TEXT;');
    await db.query('CREATE INDEX IF NOT EXISTS idx_payment_accounts_salon_id ON public.payment_accounts(salon_id);');
    await db.query('ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id);');
    await db.query('ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;');
    await db.query('COMMIT');

    // Salon & Users
    await db.query('BEGIN');
    const salonId = 'e5df75db-41f3-4199-8a7a-70cddbb537e7';
    await db.query(`
      INSERT INTO salons (id, name, qr_domain, subscription_end, is_suspended)
      VALUES ($1, 'The Thrive Salon', 'localhost:8081', now() + interval '10 years', 'false')
      ON CONFLICT (id) DO NOTHING
    `, [salonId]);

    const localPassword = 'LocalSalon123!';
    const hashedPassword = await bcrypt.hash(localPassword, 10);

    // Owner account
    await db.query(`
      INSERT INTO users (email, password, plain_password, role, salon_id, name)
      VALUES ($1, $2, $3, 'OWNER', $4, 'Local Owner')
      ON CONFLICT (email) DO UPDATE SET password = EXCLUDED.password, salon_id = EXCLUDED.salon_id
    `, ['owner@local.test', hashedPassword, localPassword, salonId]);

    // Super Admin account
    await db.query(`
      INSERT INTO users (email, password, plain_password, role, name)
      VALUES ($1, $2, $3, 'SUPER_ADMIN', 'Super Admin')
      ON CONFLICT (email) DO UPDATE SET password = EXCLUDED.password
    `, ['admin@local.test', hashedPassword, localPassword]);

    await db.query('COMMIT');
    console.log('Local Salon & Users configured.');

    // Seed data
    const seedFile = path.join(__dirname, 'seed-data.sql');
    if (fs.existsSync(seedFile)) {
      console.log('Seeding initial data from seed-data.sql...');
      const seedSql = fs.readFileSync(seedFile, 'utf8');
      await db.query('BEGIN');
      await db.query(seedSql);
      await db.query('COMMIT');
      console.log('Seed data imported.');
    }

    // Summary of tables
    const tableSummary = await db.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
      ORDER BY table_name;
    `);
    console.log(`\nInitialized thrive_local successfully! Total tables in public schema: ${tableSummary.rowCount}`);
    console.log('Available tables:');
    console.log(tableSummary.rows.map(r => r.table_name).join(', '));
  } catch (err) {
    await db.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    await db.end();
  }
}

main().catch(err => {
  console.error('Initialization error:', err);
  process.exit(1);
});
