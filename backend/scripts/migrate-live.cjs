const { Client } = require('pg');

const connString = process.argv[2];

if (!connString) {
  console.log('Usage: node scripts/migrate-live.cjs "postgresql://user:pass@host:port/dbname"');
  process.exit(1);
}

async function run() {
  const client = new Client({ connectionString: connString, ssl: { rejectUnauthorized: false } });
  try {
    await client.connect();
    console.log('Connected to live PostgreSQL database successfully!');

    console.log('1. Creating payment_accounts table...');
    await client.query(`
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

    console.log('2. Creating index...');
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_payment_accounts_salon_id ON public.payment_accounts(salon_id);
    `);

    console.log('3. Updating sales table...');
    await client.query(`
      ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
      ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;
    `);

    console.log('4. Updating expenses table...');
    await client.query(`
      ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'CASH';
      ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
      ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;
    `);

    console.log('5. Updating salary_deductions table...');
    await client.query(`
      ALTER TABLE public.salary_deductions ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'CASH';
      ALTER TABLE public.salary_deductions ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
    `);

    console.log('\n>>> ALL TABLES & COLUMNS SUCCESSFULLY CREATED ON LIVE DB! <<<');
  } catch (err) {
    console.error('Error executing migration:', err.message);
  } finally {
    await client.end();
  }
}

run();
