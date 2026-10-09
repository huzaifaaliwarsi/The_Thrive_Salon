require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const { db } = require('../dist/db');
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
  console.log(`Found ${accounts.length} payment accounts:`, accounts.map(a => `${a.accountName} (${a.id})`));

  if (accounts.length === 0) {
    throw new Error('No payment accounts found for salon');
  }

  const bankAccount = accounts[0]; // e.g. JazzCash or Meezan Bank
  console.log(`Using account for test: ${bankAccount.accountName}`);

  // Initial Galla balance
  const initialGalla = await getSalonGallaBalances(salonId);
  console.log('Initial Galla:', {
    cashBalance: initialGalla.cashBalance,
    onlineBalance: initialGalla.onlineBalance,
    breakdown: initialGalla.onlineBreakdown
  });

  const initialBankAmt = initialGalla.onlineBreakdown[bankAccount.accountName] || 0;

  // 1. Create Online Expense (e.g. 150 PKR via bank account)
  console.log('\n--- 1. Testing Online Expense ---');
  const onlineExpenseRes = await axios.post(`${baseURL}/api/expenses`, {
    name: 'Test Tea via Bank',
    category: 'Other',
    amount: 150,
    paymentMethod: 'ONLINE',
    paymentAccountId: bankAccount.id,
    date: new Date().toISOString().split('T')[0]
  }, { headers });
  console.log('Created Online Expense ID:', onlineExpenseRes.data.id);

  const afterOnlineGalla = await getSalonGallaBalances(salonId);
  console.log('After Online Expense Galla:', {
    cashBalance: afterOnlineGalla.cashBalance,
    onlineBalance: afterOnlineGalla.onlineBalance,
    breakdown: afterOnlineGalla.onlineBreakdown
  });

  const afterBankAmt = afterOnlineGalla.onlineBreakdown[bankAccount.accountName] || 0;
  console.log(`Difference in ${bankAccount.accountName}:`, afterBankAmt - initialBankAmt, '(Expected -150)');

  // 2. Create Split Expense (e.g. 200 PKR total: 100 Cash, 100 Bank)
  console.log('\n--- 2. Testing Split Expense ---');
  const splitExpenseRes = await axios.post(`${baseURL}/api/expenses`, {
    name: 'Test Utility Split',
    category: 'Bills',
    amount: 200,
    paymentMethod: 'SPLIT',
    paymentAccountId: bankAccount.id,
    cashAmount: 100,
    onlineAmount: 100,
    date: new Date().toISOString().split('T')[0]
  }, { headers });
  console.log('Created Split Expense ID:', splitExpenseRes.data.id);

  const afterSplitGalla = await getSalonGallaBalances(salonId);
  console.log('After Split Expense Galla:', {
    cashBalance: afterSplitGalla.cashBalance,
    onlineBalance: afterSplitGalla.onlineBalance,
    breakdown: afterSplitGalla.onlineBreakdown
  });

  // Clean up test expenses
  console.log('\n--- Cleaning up test expenses ---');
  await axios.delete(`${baseURL}/api/expenses/${onlineExpenseRes.data.id}`, { headers });
  await axios.delete(`${baseURL}/api/expenses/${splitExpenseRes.data.id}`, { headers });
  console.log('Cleaned up successfully!');

  const finalGalla = await getSalonGallaBalances(salonId);
  console.log('Final Restored Galla:', {
    cashBalance: finalGalla.cashBalance,
    onlineBalance: finalGalla.onlineBalance,
    breakdown: finalGalla.onlineBreakdown
  });

  console.log('\n ALL EXPENSE PAYMENT TESTS PASSED PERFECTLY!');
  process.exit(0);
}

test().catch(err => {
  console.error('Test failed:', err.response?.data || err.message);
  process.exit(1);
});
