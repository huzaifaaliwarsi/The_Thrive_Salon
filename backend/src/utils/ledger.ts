import { sql, eq, and } from 'drizzle-orm';
import { db } from '../db';
import { ledgerEntries, sales } from '../db/schema';

export const isOnlineSql = sql<boolean>`(
  CASE
    -- 1. Check explicit JSON notes for paymentMethod containing ONLINE, CARD, BANK, UPI, DIGITAL, CHECK, CHEQUE, CHQ
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
         
    -- 2. Check plain text notes
    WHEN LOWER(COALESCE(notes, '')) LIKE '%online%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%card%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%bank%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%upi%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%cheque%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%check%' OR 
         LOWER(COALESCE(notes, '')) LIKE '%chq%' THEN true

    -- 3. Fallback to joined sale / purchase default payment method
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
    } catch (_) {}
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

/**
 * getSalonGallaBalances — single unified source of truth for Galla & Drawer balances.
 *
 * INCOME:
 *   cashSales / onlineSales  = sum of payment ledger entries per payment method
 *
 * OUTFLOWS:
 *   Expenses, vendor payments, anonymous purchases, staff advances.
 */
export async function getSalonGallaBalances(
  salonId: string,
  startDate?: Date,
  endDate?: Date
) {
  const [salesData, ledgerEntriesData] = await Promise.all([
    db.select().from(sales).where(and(
      eq(sales.salonId, salonId),
      sql`${sales.status} != 'VOID'`,
      sql`${sales.status} != 'DRAFT'`
    )),
    db.select().from(ledgerEntries).where(eq(ledgerEntries.salonId, salonId))
  ]);

  const filteredEntries = ledgerEntriesData.filter(e => isWithinRange((e as any).date || (e as any).createdAt, startDate, endDate));

  let cashSales = 0;
  let onlineSales = 0;
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

  // Map sales by ID to check status and creation date for void reversals
  const allSalesMap: Record<string, any> = {};
  const allSalesList = await db.select().from(sales).where(eq(sales.salonId, salonId));
  for (const s of allSalesList) {
    allSalesMap[s.id] = s;
  }

  // INCOME & OUTFLOWS from ledger entries
  for (const entry of filteredEntries) {
    const amt = parseFloat(entry.amount || '0');
    if (amt <= 0) continue;
    const cat = entry.category;
    const typ = entry.type;

    // Income from client payments (both initial and partial payments)
    if (cat === 'PAYMENT' && typ === 'DEBIT' && !entry.vendorId) {
      const origSale = entry.saleId ? allSalesMap[entry.saleId] : undefined;
      if (origSale && (origSale.status === 'VOID' || origSale.status === 'DRAFT')) {
        continue; // skip voided or draft sales
      }
      if (isOnlineMethod(getPaymentMethodFromEntry(entry, origSale))) {
        onlineSales += amt;
      } else {
        cashSales += amt;
      }
      continue;
    }

    const isExpenseOut    = cat === 'EXPENSE';
    const isVendorPayment = (cat === 'PAYMENT' || cat === 'PURCHASE') && typ === 'DEBIT' && !!entry.vendorId;
    const isAnonPurchase  = cat === 'PURCHASE' && typ === 'DEBIT' && !entry.vendorId;
    const isStaffSalaryOrAdvance = (cat === 'STAFF_ADVANCE' || cat === 'SALARY' || cat === 'STAFF_PAYMENT' || cat === 'PAYROLL') && typ === 'DEBIT';
    const isReconShortage = cat === 'RECONCILIATION_ADJUSTMENT' && typ === 'DEBIT';
    const isReconSurplus  = cat === 'RECONCILIATION_ADJUSTMENT' && typ === 'CREDIT';
    const isStaffDeductionIn = cat === 'STAFF_DEDUCTION' && typ === 'CREDIT';
    
    // Only subtract VOID_REVERSAL if the sale was created BEFORE startDate (previous period)
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
      } else {
        cashSales += amt;
      }
      continue;
    }

    if (!isExpenseOut && !isVendorPayment && !isAnonPurchase && !isStaffSalaryOrAdvance && !isVoidReversal && !isReconShortage) continue;

    if (entryIsOnline) {
      onlineOut += amt;
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
    cashBalance:   cashSales - cashOut,
    onlineBalance: onlineSales - onlineOut,
    cashSales,
    onlineSales,
    cashIn: cashSales,
    onlineIn: onlineSales,
    cashOut,
    onlineOut,
    expenseCash,
    expenseOnline,
    vendorCash,
    vendorOnline,
    anonPurchaseCash,
    anonPurchaseOnline,
    staffAdvanceCash,
    staffAdvanceOnline
  };
}
