require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const { Client } = require('pg');

async function run() {
  const client = new Client({
    connectionString: process.env.DATABASE_URL
  });
  await client.connect();
  console.log('Connected to DB');

  await client.query(`
    ALTER TABLE public.salary_deductions ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'CASH';
    ALTER TABLE public.salary_deductions ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
  `);

  console.log('Successfully updated public.salary_deductions table with payment columns!');
  await client.end();
}

run().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
