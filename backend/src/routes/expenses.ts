import { Router } from 'express';
import { db } from '../db';
import { expenses, salons, ledgerEntries, staff, paymentAccounts } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, gte, lte, sql } from 'drizzle-orm';

const router = Router();

function computeExpensePaymentSplit(
  amountNum: number,
  paymentMethod?: string,
  cashAmount?: any,
  onlineAmount?: any
): { methodUpper: string; cashPaid: number; onlinePaid: number } {
  const methodUpper = (paymentMethod || 'CASH').toUpperCase();
  let cashPaid = 0;
  let onlinePaid = 0;

  if (cashAmount !== undefined || onlineAmount !== undefined) {
    cashPaid = parseFloat(cashAmount?.toString() || '0') || 0;
    onlinePaid = parseFloat(onlineAmount?.toString() || '0') || 0;
  } else if (methodUpper === 'SPLIT') {
    cashPaid = Math.round((amountNum / 2) * 100) / 100;
    onlinePaid = Math.round((amountNum - cashPaid) * 100) / 100;
  } else if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'BANK'].includes(methodUpper)) {
    onlinePaid = amountNum;
    cashPaid = 0;
  } else {
    cashPaid = amountNum;
    onlinePaid = 0;
  }

  return { methodUpper, cashPaid, onlinePaid };
}

// Update Expense (Owner only)
router.put('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { 
    amount, 
    category, 
    name, 
    date, 
    staffId, 
    paymentMethod, 
    paymentAccountId, 
    cashAmount, 
    onlineAmount, 
    paymentBreakdown 
  } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  if (!name || !category) {
    return res.status(400).json({ message: 'Name and Category are required' });
  }

  const amountNum = parseFloat(amount);
  if (isNaN(amountNum) || amountNum <= 0) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }

  let validStaffId: string | null = null;
  if (staffId && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(staffId)) {
    try {
      const staffExists = await db.query.staff.findFirst({
        where: eq(staff.id, staffId)
      });
      if (staffExists) {
        validStaffId = staffId;
      }
    } catch (_) {}
  }

  try {
    const result = await db.transaction(async (tx) => {
      const oldExpense = await tx.query.expenses.findFirst({
        where: and(eq(expenses.id, id as string), eq(expenses.salonId, salonId as string))
      });
      if (!oldExpense) return null;

      // 1. Calculate how much cash was previously deducted by inspecting old ledger entries
      const oldLedgerList = await tx.query.ledgerEntries.findMany({
        where: eq(ledgerEntries.expenseId, id as string)
      });

      let oldCashPaid = 0;
      for (const entry of oldLedgerList) {
        let isCashEntry = true;
        if (entry.notes) {
          try {
            const parsed = JSON.parse(entry.notes);
            const m = (parsed.paymentMethod || '').toUpperCase();
            if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'BANK'].includes(m)) {
              isCashEntry = false;
            }
          } catch (_) {}
        }
        if (isCashEntry) {
          oldCashPaid += parseFloat(entry.amount || '0');
        }
      }

      if (oldLedgerList.length === 0) {
        const oldMethod = ((oldExpense as any).paymentMethod || 'CASH').toUpperCase();
        if (oldMethod === 'CASH') {
          oldCashPaid = parseFloat(oldExpense.amount || '0');
        }
      }

      // 2. Resolve new payment account
      let matchedAccount: any = null;
      if (paymentAccountId) {
        matchedAccount = await tx.query.paymentAccounts.findFirst({
          where: and(
            eq(paymentAccounts.id, paymentAccountId),
            eq(paymentAccounts.salonId, salonId as string)
          )
        });
      }

      const { methodUpper, cashPaid, onlinePaid } = computeExpensePaymentSplit(
        amountNum,
        paymentMethod,
        cashAmount,
        onlineAmount
      );

      const resolvedAccountName = matchedAccount?.accountName || null;

      // 3. Reverse old cash & apply new cash
      const netCashDiff = oldCashPaid - cashPaid;
      if (netCashDiff !== 0) {
        await tx.update(salons)
          .set({
            cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric + ${netCashDiff.toString()}::numeric)`
          })
          .where(eq(salons.id, salonId as string));
      }

      // 4. Update Expense record
      const [updatedExpense] = await tx.update(expenses)
        .set({
          amount: amountNum.toString(),
          category,
          name,
          date: date ? date : new Date().toISOString().split('T')[0],
          paymentMethod: methodUpper,
          paymentAccountId: matchedAccount?.id || paymentAccountId || null,
          paymentBreakdown: paymentBreakdown ? (typeof paymentBreakdown === 'string' ? paymentBreakdown : JSON.stringify(paymentBreakdown)) : null,
        })
        .where(eq(expenses.id, id as string))
        .returning();

      // 5. Replace ledger entries
      await tx.delete(ledgerEntries).where(eq(ledgerEntries.expenseId, id as string));

      const expenseDate = date ? new Date(date) : new Date();

      if (cashPaid > 0) {
        const cashNotes = JSON.stringify({
          serviceName: name,
          paymentMethod: 'CASH',
          userNotes: `Expense (Cash): ${name} (${category})`
        });

        await tx.insert(ledgerEntries).values({
          salonId: salonId as string,
          expenseId: updatedExpense.id,
          staffId: validStaffId,
          type: 'DEBIT',
          amount: cashPaid.toString(),
          category: 'EXPENSE',
          notes: cashNotes,
          date: expenseDate,
        });
      }

      if (onlinePaid > 0) {
        const onlineMethod = methodUpper === 'SPLIT' || methodUpper === 'CASH' ? 'ONLINE' : methodUpper;
        const onlineNotes = JSON.stringify({
          serviceName: name,
          paymentMethod: onlineMethod,
          paymentAccountId: matchedAccount?.id || paymentAccountId || undefined,
          paymentAccountName: resolvedAccountName || undefined,
          userNotes: `Expense (${onlineMethod}${resolvedAccountName ? ` - ${resolvedAccountName}` : ''}): ${name} (${category})`
        });

        await tx.insert(ledgerEntries).values({
          salonId: salonId as string,
          expenseId: updatedExpense.id,
          staffId: validStaffId,
          type: 'DEBIT',
          amount: onlinePaid.toString(),
          category: 'EXPENSE',
          notes: onlineNotes,
          date: expenseDate,
        });
      }

      return {
        ...updatedExpense,
        paymentAccount: matchedAccount || null
      };
    });

    if (!result) return res.status(404).json({ message: 'Expense not found' });
    res.json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error updating expense' });
  }
});

// Create Expense (Owner only)
router.post('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { 
    amount, 
    category, 
    name, 
    date, 
    staffId, 
    paymentMethod, 
    paymentAccountId, 
    cashAmount, 
    onlineAmount, 
    paymentBreakdown 
  } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  if (!name || !category) {
    return res.status(400).json({ message: 'Name and Category are required' });
  }

  const amountNum = parseFloat(amount);
  if (isNaN(amountNum) || amountNum <= 0) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }

  let validStaffId: string | null = null;
  if (staffId && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(staffId)) {
    try {
      const staffExists = await db.query.staff.findFirst({
        where: eq(staff.id, staffId)
      });
      if (staffExists) {
        validStaffId = staffId;
      }
    } catch (_) {}
  }

  try {
    const result = await db.transaction(async (tx) => {
      // 1. Resolve payment account if provided
      let matchedAccount: any = null;
      if (paymentAccountId) {
        matchedAccount = await tx.query.paymentAccounts.findFirst({
          where: and(
            eq(paymentAccounts.id, paymentAccountId),
            eq(paymentAccounts.salonId, salonId as string)
          )
        });
      }

      const { methodUpper, cashPaid, onlinePaid } = computeExpensePaymentSplit(
        amountNum,
        paymentMethod,
        cashAmount,
        onlineAmount
      );

      const resolvedAccountName = matchedAccount?.accountName || null;

      // 2. Insert Expense
      const [newExpense] = await tx.insert(expenses).values({
        amount: amountNum.toString(),
        category,
        name,
        date: date ? date : new Date().toISOString().split('T')[0],
        salonId: salonId as string,
        paymentMethod: methodUpper,
        paymentAccountId: matchedAccount?.id || paymentAccountId || null,
        paymentBreakdown: paymentBreakdown ? (typeof paymentBreakdown === 'string' ? paymentBreakdown : JSON.stringify(paymentBreakdown)) : null,
      }).returning();

      // 3. Deduct from Cash Balance (only if cash was paid)
      if (cashPaid > 0) {
        await tx.update(salons)
          .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric - ${cashPaid.toString()}::numeric)` })
          .where(eq(salons.id, salonId as string));
      }

      const expenseDate = date ? new Date(date) : new Date();

      // 4. Create Ledger Entries
      if (cashPaid > 0) {
        const cashNotes = JSON.stringify({
          serviceName: name,
          paymentMethod: 'CASH',
          userNotes: `Expense (Cash): ${name} (${category})`
        });

        await tx.insert(ledgerEntries).values({
          salonId: salonId as string,
          expenseId: newExpense.id,
          staffId: validStaffId,
          type: 'DEBIT',
          amount: cashPaid.toString(),
          category: 'EXPENSE',
          notes: cashNotes,
          date: expenseDate,
        });
      }

      if (onlinePaid > 0) {
        const onlineMethod = methodUpper === 'SPLIT' || methodUpper === 'CASH' ? 'ONLINE' : methodUpper;
        const onlineNotes = JSON.stringify({
          serviceName: name,
          paymentMethod: onlineMethod,
          paymentAccountId: matchedAccount?.id || paymentAccountId || undefined,
          paymentAccountName: resolvedAccountName || undefined,
          userNotes: `Expense (${onlineMethod}${resolvedAccountName ? ` - ${resolvedAccountName}` : ''}): ${name} (${category})`
        });

        await tx.insert(ledgerEntries).values({
          salonId: salonId as string,
          expenseId: newExpense.id,
          staffId: validStaffId,
          type: 'DEBIT',
          amount: onlinePaid.toString(),
          category: 'EXPENSE',
          notes: onlineNotes,
          date: expenseDate,
        });
      }

      return {
        ...newExpense,
        paymentAccount: matchedAccount || null
      };
    });

    res.status(201).json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error creating expense' });
  }
});

// List Expenses (Owner only)
router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.query.salonId as string) : req.user.salonId;
  const { startDate, endDate } = req.query;

  try {
    let whereClause = eq(expenses.salonId, salonId as string);
    
    if (startDate) {
      whereClause = and(whereClause, gte(expenses.date, startDate as string))!;
    }
    if (endDate) {
      whereClause = and(whereClause, lte(expenses.date, endDate as string))!;
    }

    const allExpenses = await db.query.expenses.findMany({
      where: whereClause,
      with: {
        paymentAccount: true
      },
      orderBy: (expenses, { desc }) => [desc(expenses.date)]
    });
    res.json(allExpenses);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching expenses' });
  }
});

// Delete Expense (Owner only)
router.delete('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.salonId;

  try {
    const result = await db.transaction(async (tx) => {
      const deletedExpense = await tx.query.expenses.findFirst({
        where: and(eq(expenses.id, id as string), eq(expenses.salonId, salonId as string))
      });

      if (!deletedExpense) return null;

      // Find how much cash was actually deducted
      const oldLedgerList = await tx.query.ledgerEntries.findMany({
        where: eq(ledgerEntries.expenseId, id as string)
      });

      let cashToRefund = 0;
      for (const entry of oldLedgerList) {
        let isCashEntry = true;
        if (entry.notes) {
          try {
            const parsed = JSON.parse(entry.notes);
            const m = (parsed.paymentMethod || '').toUpperCase();
            if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'BANK'].includes(m)) {
              isCashEntry = false;
            }
          } catch (_) {}
        }
        if (isCashEntry) {
          cashToRefund += parseFloat(entry.amount || '0');
        }
      }

      if (oldLedgerList.length === 0) {
        const oldMethod = ((deletedExpense as any).paymentMethod || 'CASH').toUpperCase();
        if (oldMethod === 'CASH') {
          cashToRefund = parseFloat(deletedExpense.amount || '0');
        }
      }

      // Delete corresponding ledger entries
      await tx.delete(ledgerEntries)
        .where(eq(ledgerEntries.expenseId, id as string));

      // Delete expense
      await tx.delete(expenses)
        .where(eq(expenses.id, id as string));

      // Reverse cash only if cash was actually deducted
      if (cashToRefund > 0) {
        await tx.update(salons)
          .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric + ${cashToRefund.toString()}::numeric)` })
          .where(eq(salons.id, salonId as string));
      }

      return deletedExpense;
    });

    if (!result) return res.status(404).json({ message: 'Expense not found' });
    res.json({ message: 'Expense deleted successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error deleting expense' });
  }
});

export default router;
