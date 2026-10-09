const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function clearTransactionalData() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    console.log('--- Clearing Transactional Data ---');

    // 1. Delete sale items and sales
    await client.query('DELETE FROM sale_items');
    await client.query('DELETE FROM sales');
    console.log('Cleared sales & sale_items');

    // 2. Delete expenses
    await client.query('DELETE FROM expenses');
    console.log('Cleared expenses');

    // 3. Delete purchases & inventory transactions
    await client.query('DELETE FROM inventory_transactions');
    await client.query('DELETE FROM purchases');
    console.log('Cleared purchases & inventory_transactions');

    // 4. Delete salary deductions & history
    await client.query('DELETE FROM salary_deductions');
    await client.query('DELETE FROM staff_salary_history');
    console.log('Cleared salary_deductions & staff_salary_history');

    // 5. Delete appointments & attendance
    await client.query('DELETE FROM appointments');
    await client.query('DELETE FROM attendance');
    console.log('Cleared appointments & attendance');

    // 6. Delete all ledger entries (clears all cash drawer & bank payment ledger entries)
    await client.query('DELETE FROM ledger_entries');
    console.log('Cleared ledger_entries');

    // 7. Reset salon cash drawer balance to 0
    await client.query('UPDATE salons SET cash_balance = 0.00');
    console.log('Reset salon cash_balance to 0.00');

    // 7. Reset client balances and total_spent to 0
    await client.query('UPDATE clients SET balance = 0.00, total_spent = 0.00');
    console.log('Reset client balances and total_spent to 0.00');

    // 8. Reset vendor balances to 0
    await client.query('UPDATE vendors SET balance = 0.00');
    console.log('Reset vendor balances to 0.00');

    await client.query('COMMIT');
    console.log('All transactional data, reports, bank payments, and POS records have been successfully reset to 0!');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error during cleanup:', err);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

clearTransactionalData();
