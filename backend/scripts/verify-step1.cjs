const path = require('path');
const dotenv = require('dotenv');
const { Client } = require('pg');

dotenv.config({ path: path.resolve(__dirname, '../.env') });

const connectionString = process.env.DATABASE_URL || 'postgresql://postgres:admin123@127.0.0.1:5432/thrive_local';

async function verify() {
  console.log(`Connecting to: ${connectionString.replace(/:[^:]*@/, ':****@')}`);
  const client = new Client({ connectionString });
  await client.connect();

  const accounts = await client.query('SELECT id, salon_id, account_name, account_number, iban, type, is_active FROM payment_accounts');
  console.log('\n--- Payment Accounts in Database (pgAdmin) ---');
  console.table(accounts.rows);

  const salesCols = await client.query(`
    SELECT column_name, data_type, is_nullable 
    FROM information_schema.columns 
    WHERE table_name = 'sales' AND column_name IN ('payment_account_id', 'payment_breakdown')
    ORDER BY column_name
  `);
  console.log('\n--- Sales Table New Columns ---');
  console.table(salesCols.rows);

  const relationsCheck = await client.query(`
    SELECT tc.constraint_name, tc.table_name, kcu.column_name, 
           ccu.table_name AS foreign_table_name,
           ccu.column_name AS foreign_column_name 
    FROM information_schema.table_constraints AS tc 
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY' 
      AND (tc.table_name = 'payment_accounts' OR (tc.table_name = 'sales' AND kcu.column_name = 'payment_account_id'));
  `);
  console.log('\n--- Foreign Key Integrity ---');
  console.table(relationsCheck.rows);

  await client.end();
  console.log('\n✅ Step 1 verification successfully passed.');
}

verify().catch(err => {
  console.error('Verification failed:', err);
  process.exit(1);
});
