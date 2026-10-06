const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const root = path.resolve(__dirname, '../..');
const password = fs.readFileSync(path.join(root, '.local/postgres-password.txt'), 'utf8').trim();
const config = { host: '127.0.0.1', port: 55433, user: 'thrive_local', password, database: 'thrive_local' };

async function seedData() {
  const db = new Client(config);
  await db.connect();
  console.log('Connected to thrive_local PostgreSQL database...');

  try {
    await db.query('BEGIN');

    // 1. Get local salon
    const salonRes = await db.query('SELECT id, name FROM public.salons LIMIT 1');
    if (!salonRes.rowCount) throw new Error('No salon found in database!');
    const salon = salonRes.rows[0];
    const salonId = salon.id;
    console.log(`Seeding data for Salon: "${salon.name}" (${salonId})`);

    // 2. Ensure Payment Accounts
    console.log('1. Setting up Payment Accounts...');
    const accountsData = [
      { name: 'JazzCash', title: 'The Thrive Salon - Wallet', number: '03001234567', type: 'WALLET' },
      { name: 'Meezan Bank', title: 'The Thrive Salon Main', number: '01020304050607', type: 'BANK' },
      { name: 'EasyPaisa', title: 'Thrive Branch Wallet', number: '03459876543', type: 'WALLET' },
      { name: 'HBL Islamic', title: 'Thrive Corporate Account', number: '22334455667788', type: 'BANK' }
    ];

    const accountMap = {};
    for (const acc of accountsData) {
      let existing = await db.query('SELECT id FROM public.payment_accounts WHERE salon_id = $1 AND account_name = $2', [salonId, acc.name]);
      if (existing.rowCount === 0) {
        const ins = await db.query(
          'INSERT INTO public.payment_accounts (salon_id, account_name, account_title, account_number, type, is_active) VALUES ($1, $2, $3, $4, $5, true) RETURNING id',
          [salonId, acc.name, acc.title, acc.number, acc.type]
        );
        accountMap[acc.name] = ins.rows[0].id;
      } else {
        accountMap[acc.name] = existing.rows[0].id;
      }
    }

    // 3. Seed Staff Members
    console.log('2. Setting up Staff Members...');
    const staffData = [
      { name: 'Ali Raza', phone: '03011112222', type: 'MONTHLY_PLUS_COMMISSION', val: 35000, comm: 10 },
      { name: 'Ayesha Khan', phone: '03022223333', type: 'COMMISSION', val: 0, comm: 30 },
      { name: 'Bilal Ahmed', phone: '03033334444', type: 'MONTHLY', val: 40000, comm: 5 },
      { name: 'Sana Fatima', phone: '03044445555', type: 'COMMISSION', val: 0, comm: 25 }
    ];

    const staffMap = {};
    for (const s of staffData) {
      let existing = await db.query('SELECT id FROM public.staff WHERE salon_id = $1 AND name = $2', [salonId, s.name]);
      if (existing.rowCount === 0) {
        const ins = await db.query(
          'INSERT INTO public.staff (salon_id, name, phone, salary_type, salary_value, commission_percentage) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id',
          [salonId, s.name, s.phone, s.type, s.val, s.comm]
        );
        staffMap[s.name] = ins.rows[0].id;
      } else {
        staffMap[s.name] = existing.rows[0].id;
      }
    }

    // 4. Seed Services
    console.log('3. Setting up Services...');
    const servicesData = [
      { name: 'Signature Haircut', price: 1500, cat: 'Hair' },
      { name: 'Beard Styling & Trim', price: 800, cat: 'Beard' },
      { name: 'Hydra Facial & Glow', price: 4500, cat: 'Skin' },
      { name: 'Keratin Hair Treatment', price: 8500, cat: 'Hair' },
      { name: 'Manicure & Pedicure Spa', price: 2800, cat: 'Nails' },
      { name: 'Hair Color & Highlights', price: 6000, cat: 'Hair' },
      { name: 'Charcoal Deep Cleansing', price: 2000, cat: 'Skin' }
    ];

    const serviceMap = {};
    for (const s of servicesData) {
      let existing = await db.query('SELECT id, price FROM public.services WHERE salon_id = $1 AND name = $2', [salonId, s.name]);
      if (existing.rowCount === 0) {
        const ins = await db.query(
          'INSERT INTO public.services (salon_id, name, price, category, is_active) VALUES ($1, $2, $3, $4, $5) RETURNING id, price',
          [salonId, s.name, s.price, s.cat, 'true']
        );
        serviceMap[s.name] = { id: ins.rows[0].id, price: Number(ins.rows[0].price) };
      } else {
        serviceMap[s.name] = { id: existing.rows[0].id, price: Number(existing.rows[0].price) };
      }
    }

    // 5. Seed Clients
    console.log('4. Setting up Clients...');
    const clientsData = [
      { name: 'Hamza Tariq', phone: '03123456789' },
      { name: 'Zainab Malik', phone: '03339876543' },
      { name: 'Usman Farooq', phone: '03015554433' },
      { name: 'Sarah Ahmed', phone: '03211122334' },
      { name: 'Omer Siddiqui', phone: '03157778899' },
      { name: 'Hira Mani', phone: '03224443322' }
    ];

    const clientMap = {};
    for (const c of clientsData) {
      let existing = await db.query('SELECT id FROM public.clients WHERE salon_id = $1 AND name = $2', [salonId, c.name]);
      if (existing.rowCount === 0) {
        const ins = await db.query(
          'INSERT INTO public.clients (salon_id, name, phone, source) VALUES ($1, $2, $3, $4) RETURNING id',
          [salonId, c.name, c.phone, 'WALK_IN']
        );
        clientMap[c.name] = ins.rows[0].id;
      } else {
        clientMap[c.name] = existing.rows[0].id;
      }
    }

    // 6. Seed Realistic Sales with Online, Cash, Split & Accounts
    console.log('5. Generating Real Sales & Invoices with Payment Breakdowns...');

    const salesSamples = [
      // 1: Cash sale
      {
        clientName: 'Hamza Tariq',
        staffName: 'Ali Raza',
        items: [{ service: 'Signature Haircut', qty: 1 }],
        paymentMethod: 'CASH',
        accountName: null,
        breakdown: null,
        daysAgo: 0
      },
      // 2: Online via JazzCash
      {
        clientName: 'Zainab Malik',
        staffName: 'Ayesha Khan',
        items: [{ service: 'Hydra Facial & Glow', qty: 1 }],
        paymentMethod: 'ONLINE',
        accountName: 'JazzCash',
        breakdown: [{ accountName: 'JazzCash', amount: 4500 }],
        daysAgo: 0
      },
      // 3: Online via Meezan Bank
      {
        clientName: 'Usman Farooq',
        staffName: 'Ali Raza',
        items: [{ service: 'Keratin Hair Treatment', qty: 1 }],
        paymentMethod: 'ONLINE',
        accountName: 'Meezan Bank',
        breakdown: [{ accountName: 'Meezan Bank', amount: 8500 }],
        daysAgo: 0
      },
      // 4: Online Multi-Split (JazzCash + Meezan Bank - as in user's diagram)
      {
        clientName: 'Sarah Ahmed',
        staffName: 'Sana Fatima',
        items: [{ service: 'Manicure & Pedicure Spa', qty: 1 }, { service: 'Beard Styling & Trim', qty: 1 }],
        paymentMethod: 'ONLINE',
        accountName: 'JazzCash',
        breakdown: [
          { accountName: 'JazzCash', amount: 2000 },
          { accountName: 'Meezan Bank', amount: 1600 }
        ],
        daysAgo: 1
      },
      // 5: Online via EasyPaisa
      {
        clientName: 'Omer Siddiqui',
        staffName: 'Bilal Ahmed',
        items: [{ service: 'Hair Color & Highlights', qty: 1 }],
        paymentMethod: 'ONLINE',
        accountName: 'EasyPaisa',
        breakdown: [{ accountName: 'EasyPaisa', amount: 6000 }],
        daysAgo: 1
      },
      // 6: Split Cash + Online (HBL Islamic)
      {
        clientName: 'Hira Mani',
        staffName: 'Ayesha Khan',
        items: [{ service: 'Charcoal Deep Cleansing', qty: 1 }, { service: 'Signature Haircut', qty: 1 }],
        paymentMethod: 'SPLIT',
        accountName: 'HBL Islamic',
        cashPortion: 1500,
        onlinePortion: 2000,
        breakdown: [{ accountName: 'HBL Islamic', amount: 2000 }],
        daysAgo: 1
      }
    ];

    for (const sample of salesSamples) {
      const clientId = clientMap[sample.clientName];
      const staffId = staffMap[sample.staffName];
      let subtotal = 0;
      for (const item of sample.items) {
        subtotal += (serviceMap[item.service]?.price || 1000) * item.qty;
      }
      const total = subtotal;
      let amountPaid = total;
      if (sample.paymentMethod === 'CREDIT') amountPaid = 0;

      const saleDate = new Date();
      saleDate.setDate(saleDate.getDate() - sample.daysAgo);
      const paymentAccId = sample.accountName ? accountMap[sample.accountName] : null;

      const saleRes = await db.query(`
        INSERT INTO public.sales (
          salon_id, staff_id, customer_name, customer_phone,
          subtotal, total, payment_method, payment_account_id, payment_breakdown,
          amount_paid, status, created_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'ACTIVE', $11
        ) RETURNING id
      `, [
        salonId, staffId, sample.clientName, '03000000000',
        subtotal, total, sample.paymentMethod, paymentAccId,
        sample.breakdown ? JSON.stringify(sample.breakdown) : null,
        amountPaid, saleDate
      ]);
      const saleId = saleRes.rows[0].id;

      // Insert Sale Items
      for (const item of sample.items) {
        const sInfo = serviceMap[item.service];
        await db.query(`
          INSERT INTO public.sale_items (
            sale_id, service_id, staff_id, quantity, price
          ) VALUES ($1, $2, $3, $4, $5)
        `, [saleId, sInfo?.id || null, staffId, item.qty, sInfo?.price || 1000]);
      }

      // Insert Ledger Entries
      // 1. Charge Entry
      await db.query(`
        INSERT INTO public.ledger_entries (
          salon_id, client_id, sale_id, type, amount, category, notes, person_name, date, created_at
        ) VALUES ($1, $2, $3, 'CREDIT', $4, 'SALE', $5, $6, $7, $7)
      `, [salonId, clientId, saleId, total, `Invoice #${saleId.substring(0, 8)}`, sample.clientName, saleDate]);

      // 2. Payment Entries
      if (sample.paymentMethod === 'CASH') {
        await db.query(`
          INSERT INTO public.ledger_entries (
            salon_id, client_id, sale_id, type, amount, category, notes, person_name, date, created_at
          ) VALUES ($1, $2, $3, 'DEBIT', $4, 'PAYMENT', $5, $6, $7, $7)
        `, [
          salonId, clientId, saleId, amountPaid,
          JSON.stringify({ paymentMethod: 'CASH', userNotes: `Cash Payment - Sale #${saleId.substring(0, 8)}` }),
          sample.clientName, saleDate
        ]);
      } else if (sample.paymentMethod === 'ONLINE') {
        if (sample.breakdown && sample.breakdown.length > 0) {
          for (const b of sample.breakdown) {
            const accId = accountMap[b.accountName];
            await db.query(`
              INSERT INTO public.ledger_entries (
                salon_id, client_id, sale_id, type, amount, category, notes, person_name, date, created_at
              ) VALUES ($1, $2, $3, 'DEBIT', $4, 'PAYMENT', $5, $6, $7, $7)
            `, [
              salonId, clientId, saleId, b.amount,
              JSON.stringify({
                paymentMethod: 'ONLINE',
                paymentAccountId: accId,
                paymentAccountName: b.accountName,
                userNotes: `Online Payment (${b.accountName}) - Sale #${saleId.substring(0, 8)}`
              }),
              sample.clientName, saleDate
            ]);
          }
        } else {
          await db.query(`
            INSERT INTO public.ledger_entries (
              salon_id, client_id, sale_id, type, amount, category, notes, person_name, date, created_at
            ) VALUES ($1, $2, $3, 'DEBIT', $4, 'PAYMENT', $5, $6, $7, $7)
          `, [
            salonId, clientId, saleId, amountPaid,
            JSON.stringify({
              paymentMethod: 'ONLINE',
              paymentAccountId: paymentAccId,
              paymentAccountName: sample.accountName,
              userNotes: `Online Payment (${sample.accountName || 'Online'}) - Sale #${saleId.substring(0, 8)}`
            }),
            sample.clientName, saleDate
          ]);
        }
      } else if (sample.paymentMethod === 'SPLIT') {
        // Cash portion
        await db.query(`
          INSERT INTO public.ledger_entries (
            salon_id, client_id, sale_id, type, amount, category, notes, person_name, date, created_at
          ) VALUES ($1, $2, $3, 'DEBIT', $4, 'PAYMENT', $5, $6, $7, $7)
        `, [
          salonId, clientId, saleId, sample.cashPortion,
          JSON.stringify({ paymentMethod: 'CASH', userNotes: `Split Cash - Sale #${saleId.substring(0, 8)}` }),
          sample.clientName, saleDate
        ]);
        // Online portion
        await db.query(`
          INSERT INTO public.ledger_entries (
            salon_id, client_id, sale_id, type, amount, category, notes, person_name, date, created_at
          ) VALUES ($1, $2, $3, 'DEBIT', $4, 'PAYMENT', $5, $6, $7, $7)
        `, [
          salonId, clientId, saleId, sample.onlinePortion,
          JSON.stringify({
            paymentMethod: 'ONLINE',
            paymentAccountId: paymentAccId,
            paymentAccountName: sample.accountName,
            userNotes: `Split Online (${sample.accountName}) - Sale #${saleId.substring(0, 8)}`
          }),
          sample.clientName, saleDate
        ]);
      }
    }

    // 7. Seed Expenses
    console.log('6. Setting up Sample Expenses...');
    const expenseSamples = [
      { name: 'Salon Electricity Bill', cat: 'UTILITIES', amt: 12000, method: 'ONLINE', acc: 'Meezan Bank' },
      { name: 'Staff Tea & Refreshments', cat: 'PANTRY', amt: 1500, method: 'CASH', acc: null },
      { name: 'Hair Shampoos Restock', cat: 'SUPPLIES', amt: 5000, method: 'ONLINE', acc: 'JazzCash' }
    ];

    for (const exp of expenseSamples) {
      const expRes = await db.query(`
        INSERT INTO public.expenses (salon_id, name, category, amount, date)
        VALUES ($1, $2, $3, $4, CURRENT_DATE)
        RETURNING id
      `, [salonId, exp.name, exp.cat, exp.amt]);
      const expId = expRes.rows[0].id;

      await db.query(`
        INSERT INTO public.ledger_entries (
          salon_id, expense_id, type, amount, category, notes, person_name, date, created_at
        ) VALUES ($1, $2, 'DEBIT', $3, 'EXPENSE', $4, $5, now(), now())
      `, [
        salonId, expId, exp.amt,
        JSON.stringify({
          paymentMethod: exp.method,
          paymentAccountName: exp.acc,
          userNotes: exp.name
        }),
        exp.name
      ]);
    }

    await db.query('COMMIT');
    console.log('Realistic test data seeded successfully into PostgreSQL database!');
  } catch (err) {
    await db.query('ROLLBACK');
    console.error('Seeding failed:', err);
    process.exitCode = 1;
  } finally {
    await db.end();
  }
}

seedData();
