const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const root = path.resolve(__dirname, '../..');
const password = fs.readFileSync(path.join(root, '.local/postgres-password.txt'), 'utf8').trim();
const config = { host: '127.0.0.1', port: 55433, user: 'thrive_local', password, database: 'thrive_local' };

async function check() {
  const client = new Client(config);
  await client.connect();

  const res = await client.query(`
    SELECT 
      (SELECT count(*) FROM payment_accounts) AS accounts,
      (SELECT count(*) FROM services) AS services,
      (SELECT count(*) FROM staff) AS staff,
      (SELECT count(*) FROM clients) AS clients,
      (SELECT count(*) FROM sales) AS sales,
      (SELECT count(*) FROM sale_items) AS sale_items,
      (SELECT count(*) FROM ledger_entries) AS ledger_entries,
      (SELECT count(*) FROM expenses) AS expenses
  `);
  console.log('--- Real DB Table Record Counts ---');
  console.table(res.rows);

  const sampleSales = await client.query(`
    SELECT customer_name, total, payment_method, payment_breakdown 
    FROM sales 
    ORDER BY created_at DESC 
    LIMIT 6
  `);
  console.log('--- Sample Sales from PostgreSQL ---');
  console.table(sampleSales.rows);

  const sampleAccounts = await client.query(`
    SELECT account_name, account_number, type, is_active FROM payment_accounts
  `);
  console.log('--- Payment Accounts from PostgreSQL ---');
  console.table(sampleAccounts.rows);

  await client.end();
}

check().catch(console.error);
