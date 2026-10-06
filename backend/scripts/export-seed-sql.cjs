const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const root = path.resolve(__dirname, '../..');
const password = fs.readFileSync(path.join(root, '.local/postgres-password.txt'), 'utf8').trim();
const config = { host: '127.0.0.1', port: 55433, user: 'thrive_local', password, database: 'thrive_local' };

async function exportSeed() {
  const client = new Client(config);
  await client.connect();

  let sql = '-- Thrive Salon Local Database Seed Data\n';
  sql += '-- Generated for easy setup on new machines\n\n';

  // 1. Payment accounts
  const accounts = await client.query('SELECT * FROM public.payment_accounts ORDER BY created_at');
  sql += '-- 1. Payment Accounts\n';
  for (const r of accounts.rows) {
    sql += `INSERT INTO public.payment_accounts (id, salon_id, account_name, account_title, account_number, type, is_active) VALUES ('${r.id}', '${r.salon_id}', '${r.account_name}', '${r.account_title || ''}', '${r.account_number || ''}', '${r.type}', ${r.is_active}) ON CONFLICT (id) DO NOTHING;\n`;
  }
  sql += '\n';

  // 2. Services
  const services = await client.query('SELECT * FROM public.services ORDER BY created_at');
  sql += '-- 2. Services\n';
  for (const r of services.rows) {
    sql += `INSERT INTO public.services (id, salon_id, name, price, category, is_active) VALUES ('${r.id}', '${r.salon_id}', '${r.name.replace(/'/g, "''")}', ${r.price}, '${r.category}', '${r.is_active}') ON CONFLICT (id) DO NOTHING;\n`;
  }
  sql += '\n';

  // 3. Staff
  const staff = await client.query('SELECT * FROM public.staff ORDER BY created_at');
  sql += '-- 3. Staff\n';
  for (const r of staff.rows) {
    sql += `INSERT INTO public.staff (id, salon_id, name, phone, salary_type, salary_value, commission_percentage) VALUES ('${r.id}', '${r.salon_id}', '${r.name}', '${r.phone || ''}', '${r.salary_type}', ${r.salary_value || 0}, ${r.commission_percentage || 0}) ON CONFLICT (id) DO NOTHING;\n`;
  }
  sql += '\n';

  // 4. Clients
  const clients = await client.query('SELECT * FROM public.clients ORDER BY created_at');
  sql += '-- 4. Clients\n';
  for (const r of clients.rows) {
    sql += `INSERT INTO public.clients (id, salon_id, name, phone, source) VALUES ('${r.id}', '${r.salon_id}', '${r.name}', '${r.phone || ''}', '${r.source || 'WALK_IN'}') ON CONFLICT (id) DO NOTHING;\n`;
  }
  sql += '\n';

  // 5. Sales
  const sales = await client.query('SELECT * FROM public.sales ORDER BY created_at');
  sql += '-- 5. Sales\n';
  for (const r of sales.rows) {
    const accId = r.payment_account_id ? `'${r.payment_account_id}'` : 'NULL';
    const breakdown = r.payment_breakdown ? `'${r.payment_breakdown.replace(/'/g, "''")}'` : 'NULL';
    sql += `INSERT INTO public.sales (id, salon_id, staff_id, customer_name, customer_phone, subtotal, total, payment_method, payment_account_id, payment_breakdown, amount_paid, status, created_at) VALUES ('${r.id}', '${r.salon_id}', ${r.staff_id ? `'${r.staff_id}'` : 'NULL'}, '${r.customer_name}', '${r.customer_phone || ''}', ${r.subtotal}, ${r.total}, '${r.payment_method}', ${accId}, ${breakdown}, ${r.amount_paid || 0}, '${r.status}', '${r.created_at.toISOString()}') ON CONFLICT (id) DO NOTHING;\n`;
  }
  sql += '\n';

  // 6. Sale Items
  const saleItems = await client.query('SELECT * FROM public.sale_items');
  sql += '-- 6. Sale Items\n';
  for (const r of saleItems.rows) {
    sql += `INSERT INTO public.sale_items (id, sale_id, service_id, staff_id, quantity, price) VALUES ('${r.id}', '${r.sale_id}', ${r.service_id ? `'${r.service_id}'` : 'NULL'}, ${r.staff_id ? `'${r.staff_id}'` : 'NULL'}, ${r.quantity}, ${r.price}) ON CONFLICT (id) DO NOTHING;\n`;
  }
  sql += '\n';

  // 7. Ledger Entries
  const ledger = await client.query('SELECT * FROM public.ledger_entries ORDER BY created_at');
  sql += '-- 7. Ledger Entries\n';
  for (const r of ledger.rows) {
    const notes = r.notes ? `'${r.notes.replace(/'/g, "''")}'` : 'NULL';
    sql += `INSERT INTO public.ledger_entries (id, salon_id, client_id, sale_id, expense_id, type, amount, category, notes, person_name, date, created_at) VALUES ('${r.id}', '${r.salon_id}', ${r.client_id ? `'${r.client_id}'` : 'NULL'}, ${r.sale_id ? `'${r.sale_id}'` : 'NULL'}, ${r.expense_id ? `'${r.expense_id}'` : 'NULL'}, '${r.type}', ${r.amount}, '${r.category}', ${notes}, '${(r.person_name || '').replace(/'/g, "''")}', '${r.date ? r.date.toISOString() : r.created_at.toISOString()}', '${r.created_at.toISOString()}') ON CONFLICT (id) DO NOTHING;\n`;
  }
  sql += '\n';

  // 8. Expenses
  const expenses = await client.query('SELECT * FROM public.expenses ORDER BY created_at');
  sql += '-- 8. Expenses\n';
  for (const r of expenses.rows) {
    sql += `INSERT INTO public.expenses (id, salon_id, name, category, amount, date) VALUES ('${r.id}', '${r.salon_id}', '${r.name.replace(/'/g, "''")}', '${r.category}', ${r.amount}, '${r.date}') ON CONFLICT (id) DO NOTHING;\n`;
  }

  const outPath = path.join(__dirname, 'seed-data.sql');
  fs.writeFileSync(outPath, sql, 'utf8');
  console.log(`Saved seed-data.sql successfully (${sql.length} bytes)!`);

  await client.end();
}

exportSeed().catch(console.error);
