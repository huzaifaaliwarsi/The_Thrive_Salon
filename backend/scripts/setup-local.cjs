const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const bcrypt = require('bcryptjs');
const root = path.resolve(__dirname, '../..');
const password = fs.readFileSync(path.join(root, '.local/postgres-password.txt'), 'utf8').trim();
// Deliberately independent of DATABASE_URL: this script cannot target another server.
const config = { host: '127.0.0.1', port: 55433, user: 'thrive_local', password };
async function main() {
  const admin = new Client({ ...config, database: 'postgres' });
  await admin.connect();
  try {
    const existing = await admin.query("SELECT 1 FROM pg_database WHERE datname = 'thrive_local'");
    if (!existing.rowCount) await admin.query('CREATE DATABASE thrive_local');
  } finally { await admin.end(); }
  const db = new Client({ ...config, database: 'thrive_local' });
  await db.connect();
  try {
    const exists = await db.query("SELECT to_regclass('public.users') AS users");
    if (exists.rows[0].users) { console.log('Local database already initialized; existing local data preserved.'); return; }
    // Structure only (no rows): dumped from structure-compatible.sql
    const sqlFile = fs.existsSync(path.join(__dirname, 'structure-compatible.sql')) ? 'structure-compatible.sql' : 'structure-only.sql';
    const dump = fs.readFileSync(path.join(__dirname, sqlFile), 'utf8')
      .split(/\r?\n/).filter(line => !/^ALTER .* OWNER TO |^(GRANT|REVOKE) |^SET default_with_oids|^\\(restrict|unrestrict)\b/.test(line)).join('\n');
    await db.query('BEGIN');
    await db.query(dump);
    await db.query('SET search_path TO public');
    // Give new local records generated UUIDs by default (app also sets its own explicitly).
    const tables = await db.query("SELECT table_name FROM information_schema.columns WHERE table_schema='public' AND column_name='id' AND data_type='uuid'");
    for (const { table_name } of tables.rows) {
      if (!/^[a-z_]+$/.test(table_name)) throw new Error('Unexpected table name');
      await db.query(`ALTER TABLE public."${table_name}" ALTER COLUMN id SET DEFAULT gen_random_uuid()`);
    }
    // Create local salon
    const salon = (await db.query(
      "INSERT INTO salons (name, qr_domain, subscription_end, is_suspended) VALUES ($1, 'localhost:8081', now() + interval '10 years', 'false') RETURNING id",
      ['The Thrive Salon']
    )).rows[0];
    const localPassword = 'LocalSalon123!';
    const hashedPassword = await bcrypt.hash(localPassword, 10);
    // Create Owner account
    await db.query("INSERT INTO users (email,password,plain_password,role,salon_id,name) VALUES ($1,$2,$3,'OWNER',$4,'Local Owner')", ['owner@local.test', hashedPassword, localPassword, salon.id]);
    // Create Super Admin account
    await db.query("INSERT INTO users (email,password,plain_password,role,name) VALUES ($1,$2,$3,'SUPER_ADMIN','Super Admin')", ['admin@local.test', hashedPassword, localPassword]);
    await db.query('COMMIT');
    console.log('Initialized empty local database with fresh schema. Local login: owner@local.test (or admin@local.test) / LocalSalon123!');
  } catch (error) { await db.query('ROLLBACK'); throw error; }
  finally { await db.end(); }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
