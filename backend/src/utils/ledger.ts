import { sql, eq, and } from 'drizzle-orm';
import { db } from '../db';
import { ledgerEntries, sales, paymentAccounts } from '../db/schema';

export const isOnlineSql = sql<boolean>`(
  CASE
    WHEN LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"online"%' OR
         LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"card"%' OR
         LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"bank"%' OR
         LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"upi"%' OR
         LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"digital"%' OR
         LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"check"%' OR
         LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"cheque"%' OR
         LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"chq"%' THEN true
    WHEN LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"cash"%' OR
         LOWER(COALESCE(notes, '')) LIKE '%"paymentmethod"%"cash_on_delivery"%' THEN false
         
    WHEN LOWER(COALESCE(notes, '')) LIKE '%online%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%card%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%bank%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%upi%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%cheque%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%check%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%chq%' THEN true

    WHEN sale_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM sales s 
      WHERE s.id = sale_id 
      AND UPPER(COALESCE(s.payment_method, '')) IN ('ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ')
    ) THEN true
    WHEN purchase_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM purchases p 
      WHERE p.id = purchase_id 
      AND UPPER(COALESCE(p.payment_method, '')) IN ('ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'CHECK', 'CHEQUE', 'CHQ')
    ) THEN true
    ELSE false
  END
)`;

export const isCashSql = sql<boolean>`NOT (${isOnlineSql})`;

function getPaymentMethodFromEntry(entry: any, origSale?: any): string {
  let pMethod = '';
  const notes = (entry.notes || '').toString().trim();
  if (notes.startsWith('{') && notes.endsWith('}')) {
    try {
      const parsed = JSON.parse(notes);
      if (parsed.paymentMethod) {
        pMethod = parsed.paymentMethod.toString().toUpperCase();
      }
      if (!pMethod && parsed.userNotes) {
        const u = parsed.userNotes.toUpperCase();
        if (isOnlineMethod(u)) pMethod = 'ONLINE';
        else if (u.includes('CASH')) pMethod = 'CASH';
      }
    } catch (_) { }
  }
  if (!pMethod) {
    const upper = notes.toUpperCase();
    if (isOnlineMethod(upper)) {
      pMethod = 'ONLINE';
    } else if (upper.includes('CASH')) {
      pMethod = 'CASH';
    } else if (origSale && isOnlineMethod((origSale.paymentMethod || '').toUpperCase())) {
      pMethod = 'ONLINE';
    }
  }
  return pMethod || 'CASH';
}

function isOnlineMethod(method: string): boolean {
  const m = (method || '').toUpperCase();
  return m.includes('ONLINE') || m.includes('CARD') || m.includes('BANK') || m.includes('UPI') || m.includes('DIGITAL') || m.includes('CHECK') || m.includes('CHEQUE') || m.includes('CHQ');
}

export function getPaymentAccountFromEntry(
  entry: any,
  origSale?: any,
  accountMap?: Record<string, string>
): string {
  const notes = (entry.notes || '').toString().trim();
  if (notes.startsWith('{') && notes.endsWith('}')) {
    try {
      const parsed = JSON.parse(notes);
      if (parsed.paymentAccountName && typeof parsed.paymentAccountName === 'string' && parsed.paymentAccountName.trim()) {
        return parsed.paymentAccountName.trim();
      }
      if (parsed.paymentAccountId && accountMap && accountMap[parsed.paymentAccountId]) {
        return accountMap[parsed.paymentAccountId];
      }
    } catch (_) { }
  }

  if (origSale?.paymentAccountId && accountMap && accountMap[origSale.paymentAccountId]) {
    return accountMap[origSale.paymentAccountId];
  }

  if (accountMap) {
    const upperNotes = notes.toUpperCase();
    for (const accName of Object.values(accountMap)) {
      if (upperNotes.includes(accName.toUpperCase())) {
        return accName;
      }
    }
  }

  return 'Other Online';
}

function isWithinRange(value: unknown, startDate?: Date, endDate?: Date): boolean {
  if (!startDate && !endDate) return true;
  const parsed = value ? new Date(value as any) : null;
  if (!parsed || Number.isNaN(parsed.getTime())) return false;
  if (startDate && parsed < startDate) return false;
  if (endDate && parsed > endDate) return false;
  return true;
}

export async function getSalonDrawerBalances(
  salonId: string,
  startDate?: Date,
  endDate?: Date
) {
  return getSalonGallaBalances(salonId, startDate, endDate);
}

export async function calculateCashBalance(salonId: string): Promise<number> {
  const { cashBalance } = await getSalonGallaBalances(salonId);
  return cashBalance;
}

export async function calculateOnlineBalance(salonId: string): Promise<number> {
  const { onlineBalance } = await getSalonGallaBalances(salonId);
  return onlineBalance;
}

export async function getSalonGallaBalances(
  salonId: string,
  startDate?: Date,
  endDate?: Date
) {
  const [salesData, ledgerEntriesData, paymentAccountsData] = await Promise.all([
    db.select().from(sales).where(and(
      eq(sales.salonId, salonId),
      sql`${sales.status} != 'VOID'`,
      sql`${sales.status} != 'DRAFT'`
    )),
    db.select().from(ledgerEntries).where(eq(ledgerEntries.salonId, salonId)),
    db.select().from(paymentAccounts).where(eq(paymentAccounts.salonId, salonId))
  ]);

  const accountMap: Record<string, string> = {};
  for (const acc of paymentAccountsData) {
    if (acc.id && acc.accountName) {
      accountMap[acc.id] = acc.accountName;
    }
  }

  const filteredEntries = ledgerEntriesData.filter(e => isWithinRange((e as any).date || (e as any).createdAt, startDate, endDate));

  let cashSales = 0;
  let onlineSales = 0;
  let onlineBreakdown: Record<string, number> = {};
  let cashOut = 0;
  let onlineOut = 0;

  let expenseCash = 0;
  let expenseOnline = 0;
  let vendorCash = 0;
  let vendorOnline = 0;
  let anonPurchaseCash = 0;
  let anonPurchaseOnline = 0;
  let staffAdvanceCash = 0;
  let staffAdvanceOnline = 0;

  const allSalesMap: Record<string, any> = {};
  const allSalesList = await db.select().from(sales).where(eq(sales.salonId, salonId));
  for (const s of allSalesList) {
    allSalesMap[s.id] = s;
  }

  for (const entry of filteredEntries) {
    const amt = parseFloat(entry.amount || '0');
    if (amt <= 0) continue;
    const cat = entry.category;
    const typ = entry.type;

    if (cat === 'PAYMENT' && typ === 'DEBIT' && !entry.vendorId) {
      const origSale = entry.saleId ? allSalesMap[entry.saleId] : undefined;
      if (origSale && (origSale.status === 'VOID' || origSale.status === 'DRAFT')) {
        continue;
      }
      if (isOnlineMethod(getPaymentMethodFromEntry(entry, origSale))) {
        onlineSales += amt;
        const acct = getPaymentAccountFromEntry(entry, origSale, accountMap);
        onlineBreakdown[acct] = Number(((onlineBreakdown[acct] || 0) + amt).toFixed(2));
      } else {
        cashSales += amt;
      }
      continue;
    }

    const isExpenseOut = cat === 'EXPENSE';
    const isVendorPayment = (cat === 'PAYMENT' || cat === 'PURCHASE') && typ === 'DEBIT' && !!entry.vendorId;
    const isAnonPurchase = cat === 'PURCHASE' && typ === 'DEBIT' && !entry.vendorId;
    const isStaffSalaryOrAdvance = (cat === 'STAFF_ADVANCE' || cat === 'SALARY' || cat === 'STAFF_PAYMENT' || cat === 'PAYROLL') && typ === 'DEBIT';
    const isReconShortage = cat === 'RECONCILIATION_ADJUSTMENT' && typ === 'DEBIT';
    const isReconSurplus = cat === 'RECONCILIATION_ADJUSTMENT' && typ === 'CREDIT';
    const isStaffDeductionIn = cat === 'STAFF_DEDUCTION' && typ === 'CREDIT';

    let isVoidReversal = false;
    if (cat === 'VOID_REVERSAL' && typ === 'CREDIT' && entry.saleId) {
      const origSale = allSalesMap[entry.saleId];
      if (origSale && startDate) {
        const origDate = origSale.createdAt ? new Date(origSale.createdAt) : null;
        if (origDate && origDate < startDate) {
          isVoidReversal = true;
        }
      }
    }

    const entryIsOnline = isOnlineMethod(getPaymentMethodFromEntry(entry));

    if (isReconSurplus || isStaffDeductionIn) {
      if (entryIsOnline) {
        onlineSales += amt;
        const acct = getPaymentAccountFromEntry(entry, undefined, accountMap);
        onlineBreakdown[acct] = Number(((onlineBreakdown[acct] || 0) + amt).toFixed(2));
      } else {
        cashSales += amt;
      }
      continue;
    }

    if (!isExpenseOut && !isVendorPayment && !isAnonPurchase && !isStaffSalaryOrAdvance && !isVoidReversal && !isReconShortage) continue;

    if (entryIsOnline) {
      onlineOut += amt;
      const acct = getPaymentAccountFromEntry(entry, undefined, accountMap);
      onlineBreakdown[acct] = Number(((onlineBreakdown[acct] || 0) - amt).toFixed(2));
      if (isExpenseOut) expenseOnline += amt;
      if (isVendorPayment) vendorOnline += amt;
      if (isAnonPurchase) anonPurchaseOnline += amt;
      if (isStaffSalaryOrAdvance) staffAdvanceOnline += amt;
    } else {
      cashOut += amt;
      if (isExpenseOut) expenseCash += amt;
      if (isVendorPayment) vendorCash += amt;
      if (isAnonPurchase) anonPurchaseCash += amt;
      if (isStaffSalaryOrAdvance) staffAdvanceCash += amt;
    }
  }

  return {
    cashBalance: Number((cashSales - cashOut).toFixed(2)),
    onlineBalance: Number((onlineSales - onlineOut).toFixed(2)),
    cashSales: Number(cashSales.toFixed(2)),
    onlineSales: Number(onlineSales.toFixed(2)),
    onlineBreakdown,
    cashIn: Number(cashSales.toFixed(2)),
    onlineIn: Number(onlineSales.toFixed(2)),
    cashOut: Number(cashOut.toFixed(2)),
    onlineOut: Number(onlineOut.toFixed(2)),
    expenseCash: Number(expenseCash.toFixed(2)),
    expenseOnline: Number(expenseOnline.toFixed(2)),
    vendorCash: Number(vendorCash.toFixed(2)),
    vendorOnline: Number(vendorOnline.toFixed(2)),
    anonPurchaseCash: Number(anonPurchaseCash.toFixed(2)),
    anonPurchaseOnline: Number(anonPurchaseOnline.toFixed(2)),
    staffAdvanceCash: Number(staffAdvanceCash.toFixed(2)),
    staffAdvanceOnline: Number(staffAdvanceOnline.toFixed(2))
  };
}
