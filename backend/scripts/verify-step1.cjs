const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const root = path.resolve(__dirname, '../..');
const password = fs.readFileSync(path.join(root, '.local/postgres-password.txt'), 'utf8').trim();
const config = { host: '127.0.0.1', port: 55433, user: 'thrive_local', password, database: 'thrive_local' };

async function verify() {
  const client = new Client(config);
  await client.connect();

  const accounts = await client.query('SELECT id, salon_id, account_name, account_number, type, is_active FROM payment_accounts');
  console.log('--- Payment Accounts in DB ---');
  console.table(accounts.rows);

  const salesCols = await client.query(`
    SELECT column_name, data_type, is_nullable 
    FROM information_schema.columns 
    WHERE table_name = 'sales' AND column_name IN ('payment_account_id', 'payment_breakdown')
    ORDER BY column_name
  `);
  console.log('--- Sales New Columns ---');
  console.table(salesCols.rows);

  await client.end();
}

verify().catch(console.error);
