require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const { getSalonGallaBalances } = require('../dist/utils/ledger');
const axios = require('axios');

async function test() {
  const baseURL = 'http://127.0.0.1:3001';
  console.log('Logging in as owner...');
  const loginRes = await axios.post(`${baseURL}/api/auth/login`, {
    email: 'owner@local.test',
    password: 'LocalSalon123!'
  });
  const token = loginRes.data.token;
  const salonId = loginRes.data.user?.salonId || loginRes.data.salonId;
  const headers = { Authorization: `Bearer ${token}` };

  console.log(`Logged in! Salon ID: ${salonId}`);

  // Fetch bank accounts
  const accountsRes = await axios.get(`${baseURL}/api/payment-accounts`, { headers });
  const accounts = accountsRes.data;
  if (!accounts || accounts.length === 0) {
    throw new Error('No payment accounts found for salon');
  }
  const bankAccount = accounts[0];
  console.log(`Using bank account for test: "${bankAccount.accountName}" (ID: ${bankAccount.id})`);

  // Fetch a staff member
  const staffRes = await axios.get(`${baseURL}/api/staff`, { headers });
  const staffList = staffRes.data;
  if (!staffList || staffList.length === 0) {
    throw new Error('No staff members found');
  }
  const staffMember = staffList[0];
  console.log(`Using staff member: "${staffMember.name}" (ID: ${staffMember.id})`);

  // Fetch or create a test client
  const clientsRes = await axios.get(`${baseURL}/api/clients?limit=1`, { headers });
  let client = clientsRes.data[0];
  if (!client) {
    const newClient = await axios.post(`${baseURL}/api/clients`, {
      name: 'Test Client Bank',
      phone: '03001234567'
    }, { headers });
    client = newClient.data;
  }
  console.log(`Using client: "${client.name}" (ID: ${client.id})`);

  // Initial Galla balance
  const initialGalla = await getSalonGallaBalances(salonId);
  const initialBank = initialGalla.onlineBreakdown[bankAccount.accountName] || 0;
  console.log(`\n[INITIAL] Bank Balance for "${bankAccount.accountName}": PKR ${initialBank}`);

  // --- 1. Test Staff Salary Advance via Online Bank ---
  console.log('\n--- 1. Testing Staff Advance via Online Bank (PKR 300) ---');
  const advanceRes = await axios.post(`${baseURL}/api/salary`, {
    staffId: staffMember.id,
    type: 'ADVANCE',
    amount: 300,
    reason: 'Test Advance via Bank',
    paymentMethod: 'ONLINE',
    paymentAccountId: bankAccount.id,
    date: new Date().toISOString().split('T')[0]
  }, { headers });
  const advanceId = advanceRes.data.id;
  console.log(`Created Advance ID: ${advanceId}, Method: ${advanceRes.data.paymentMethod}`);

  const gallaAfterAdvance = await getSalonGallaBalances(salonId);
  const bankAfterAdvance = gallaAfterAdvance.onlineBreakdown[bankAccount.accountName] || 0;
  console.log(`Bank Balance after advance: PKR ${bankAfterAdvance} (expected: PKR ${initialBank - 300})`);
  if (Math.abs(bankAfterAdvance - (initialBank - 300)) > 0.01) {
    throw new Error(`Salary advance did not deduct bank balance correctly! Expected ${initialBank - 300}, got ${bankAfterAdvance}`);
  }
  console.log('✓ Advance correctly deducted 300 from bank account!');

  // --- 2. Test Customer Debt Payment into Bank ---
  console.log('\n--- 2. Testing Customer Debt Payment into Bank (PKR 500) ---');
  const clientPayRes = await axios.post(`${baseURL}/api/ledger/payment`, {
    clientId: client.id,
    amount: 500,
    type: 'DEBIT',
    paymentMethod: 'ONLINE',
    paymentAccountId: bankAccount.id,
    notes: 'Test Client Debt Payment via Bank'
  }, { headers });
  const clientPayId = clientPayRes.data.id;
  console.log(`Created Client Payment Ledger Entry ID: ${clientPayId}`);

  const gallaAfterClientPay = await getSalonGallaBalances(salonId);
  const bankAfterClientPay = gallaAfterClientPay.onlineBreakdown[bankAccount.accountName] || 0;
  console.log(`Bank Balance after client payment: PKR ${bankAfterClientPay} (expected: PKR ${bankAfterAdvance + 500})`);
  if (Math.abs(bankAfterClientPay - (bankAfterAdvance + 500)) > 0.01) {
    throw new Error(`Customer payment did not add to bank balance correctly! Expected ${bankAfterAdvance + 500}, got ${bankAfterClientPay}`);
  }
  console.log('✓ Customer payment correctly added 500 to bank account!');

  // --- 3. Test Vendor Payment via Bank ---
  console.log('\n--- 3. Testing Vendor Bill Payment via Bank (PKR 200) ---');
  // Fetch a vendor
  const vendorsRes = await axios.get(`${baseURL}/api/inventory/vendors`, { headers });
  let vendor = vendorsRes.data[0];
  if (!vendor) {
    const newVendor = await axios.post(`${baseURL}/api/inventory/vendors`, {
      name: 'Test Vendor Bank',
      phone: '03111234567'
    }, { headers });
    vendor = newVendor.data;
  }
  console.log(`Using vendor: "${vendor.name}" (ID: ${vendor.id})`);

  const vendorPayRes = await axios.post(`${baseURL}/api/ledger/payment`, {
    vendorId: vendor.id,
    amount: 200,
    type: 'DEBIT',
    paymentMethod: 'ONLINE',
    paymentAccountId: bankAccount.id,
    notes: 'Test Vendor Payment via Bank'
  }, { headers });
  const vendorPayId = vendorPayRes.data.id;
  console.log(`Created Vendor Payment Ledger Entry ID: ${vendorPayId}`);

  const gallaAfterVendorPay = await getSalonGallaBalances(salonId);
  const bankAfterVendorPay = gallaAfterVendorPay.onlineBreakdown[bankAccount.accountName] || 0;
  console.log(`Bank Balance after vendor payment: PKR ${bankAfterVendorPay} (expected: PKR ${bankAfterClientPay - 200})`);
  if (Math.abs(bankAfterVendorPay - (bankAfterClientPay - 200)) > 0.01) {
    throw new Error(`Vendor payment did not deduct bank balance correctly! Expected ${bankAfterClientPay - 200}, got ${bankAfterVendorPay}`);
  }
  console.log('✓ Vendor payment correctly deducted 200 from bank account!');

  // --- 4. Cleanup ---
  console.log('\n--- 4. Cleaning up test records ---');
  await axios.delete(`${baseURL}/api/salary/${advanceId}`, { headers });
  console.log('Deleted test advance');
  await axios.delete(`${baseURL}/api/ledger/payment/${clientPayId}`, { headers });
  console.log('Deleted test client payment');
  await axios.delete(`${baseURL}/api/ledger/payment/${vendorPayId}`, { headers });
  console.log('Deleted test vendor payment');

  const finalGalla = await getSalonGallaBalances(salonId);
  const finalBank = finalGalla.onlineBreakdown[bankAccount.accountName] || 0;
  console.log(`Final Bank Balance for "${bankAccount.accountName}": PKR ${finalBank} (initial: PKR ${initialBank})`);
  console.log('\n>>> ALL MULTI-BANK PAYROLL & LEDGER PAYMENT TESTS PASSED 100%! <<<');
}

test().catch(err => {
  console.error('Test Failed:', err.response?.data || err.message);
  process.exit(1);
});
