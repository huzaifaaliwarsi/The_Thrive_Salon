const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const root = path.resolve(__dirname, '../..');
const password = fs.readFileSync(path.join(root, '.local/postgres-password.txt'), 'utf8').trim();
const config = { host: '127.0.0.1', port: 55433, user: 'thrive_local', password, database: 'thrive_local' };

async function runMigration() {
  const db = new Client(config);
  await db.connect();
  console.log('Connected to thrive_local PostgreSQL database...');

  try {
    await db.query('BEGIN');

    // 1. Create payment_accounts table
    console.log('Creating payment_accounts table if not exists...');
    await db.query(`
      CREATE TABLE IF NOT EXISTS public.payment_accounts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        salon_id UUID NOT NULL REFERENCES public.salons(id) ON DELETE CASCADE,
        account_name TEXT NOT NULL,
        account_title TEXT,
        account_number TEXT,
        type TEXT DEFAULT 'BANK',
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now()
      );
    `);

    // 2. Index on salon_id
    await db.query(`
      CREATE INDEX IF NOT EXISTS idx_payment_accounts_salon_id ON public.payment_accounts(salon_id);
    `);

    // 3. Add payment_account_id & payment_breakdown to sales
    console.log('Adding nullable columns to sales table...');
    await db.query(`
      ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id);
    `);
    await db.query(`
      ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;
    `);

    // 4. Seed starter accounts for existing local salons if none exist
    const salonsRes = await db.query('SELECT id, name FROM public.salons');
    for (const salon of salonsRes.rows) {
      const existingAccounts = await db.query('SELECT 1 FROM public.payment_accounts WHERE salon_id = $1', [salon.id]);
      if (existingAccounts.rowCount === 0) {
        console.log(`Seeding initial accounts for salon "${salon.name}" (${salon.id})...`);
        await db.query(`
          INSERT INTO public.payment_accounts (salon_id, account_name, account_title, account_number, type, is_active)
          VALUES 
            ($1, 'JazzCash', $2, '03001234567', 'WALLET', true),
            ($1, 'Meezan Bank', $2, '01020304050607', 'BANK', true)
        `, [salon.id, salon.name]);
      }
    }

    await db.query('COMMIT');
    console.log('Step 1 Migration completed successfully!');
  } catch (err) {
    await db.query('ROLLBACK');
    console.error('Migration failed:', err);
    process.exitCode = 1;
  } finally {
    await db.end();
  }
}

runMigration();
