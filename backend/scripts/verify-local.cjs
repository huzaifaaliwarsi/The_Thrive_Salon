const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const { Client } = require('pg');
const { validateDatabaseUrl } = require('../dist/config');
async function main() {
  for (const url of ['postgresql://u:p@example.com:5432/prod', 'postgresql://u:p@localhost:5432/prod', 'postgresql://thrive_local:p@127.0.0.1:55433/wrong']) {
    assert.throws(() => validateDatabaseUrl(url, true));
  }
  const password = fs.readFileSync(path.resolve(__dirname, '../../.local/postgres-password.txt'), 'utf8').trim();
  const db = new Client({ host: '127.0.0.1', port: 55433, user: 'thrive_local', password, database: 'thrive_local' });
  await db.connect();
  try {
    const identity = (await db.query('SELECT current_database() AS database, inet_server_addr() AS address, inet_server_port() AS port')).rows[0];
    assert.equal(identity.database, 'thrive_local');
    assert.equal(identity.port, 55433);
    console.log('Database identity:', identity);
    await db.query('BEGIN');
    const row = (await db.query("INSERT INTO clients(name) VALUES ('LOCAL_ROLLBACK_CHECK') RETURNING id")).rows[0];
    assert.ok(row.id);
    await db.query('ROLLBACK');
    assert.equal((await db.query('SELECT 1 FROM clients WHERE id=$1', [row.id])).rowCount, 0);
  } finally { await db.end(); }
  const login = await fetch('http://127.0.0.1:3000/api/auth/login', {method:'POST', headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'owner@local.test',password:'LocalSalon123!'})});
  assert.equal(login.status, 200);
  const { token } = await login.json();
  for (const route of ['auth/me','services','staff','sales','dashboard/metrics','inventory/items','appointments','attendance','ledger','salary','purchases','reports/summary?startDate=2026-08-01&endDate=2026-09-08']) {
    const response = await fetch(`http://127.0.0.1:3000/api/${route}`, {headers:{Authorization:`Bearer ${token}`}});
    assert.equal(response.status, 200, route);
    await response.json();
    console.log(`PASS ${route}`);
  }
  console.log('PASS local database guard, login, API reads, and rolled-back write.');
}
main().catch(e => { console.error(e.message); process.exitCode=1; });
