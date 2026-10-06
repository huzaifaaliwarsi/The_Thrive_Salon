import { Router } from 'express';
import { db } from '../db';
import { expenses, salons, ledgerEntries, staff } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, gte, lte, sql } from 'drizzle-orm';

const router = Router();

// Update Expense (Owner only)
router.put('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { amount, category, name, date, staffId, paymentMethod } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  if (!name || !category) {
    return res.status(400).json({ message: 'Name and Category are required' });
  }

  // Validate amount (Bug #22: Amount validation)
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
      // 1. Get old amount to reverse
      const oldExpense = await tx.query.expenses.findFirst({
        where: and(eq(expenses.id, id as string), eq(expenses.salonId, salonId as string))
      });
      if (!oldExpense) return null;

      // 2. Update Expense
      const [updatedExpense] = await tx.update(expenses)
        .set({ 
          amount: amount.toString(), 
          category, 
          name, 
          date: date ? date : new Date().toISOString().split('T')[0] 
        })
        .where(eq(expenses.id, id as string))
        .returning();

      // 3. Update Cash Balance: Reverse old, add new (accounting for cash vs online)
      const oldLedger = await tx.query.ledgerEntries.findFirst({
        where: eq(ledgerEntries.expenseId, id as string)
      });
      let oldIsCash = true;
      if (oldLedger && oldLedger.notes) {
        try {
          const struct = JSON.parse(oldLedger.notes);
          if (struct.paymentMethod === 'ONLINE') oldIsCash = false;
        } catch (_) {}
      }

      const newIsCash = !paymentMethod || paymentMethod.toUpperCase() === 'CASH';

      let balanceAdjustment = 0;
      if (oldIsCash) balanceAdjustment += parseFloat(oldExpense.amount);
      if (newIsCash) balanceAdjustment -= parseFloat(amount.toString());

      if (balanceAdjustment !== 0) {
        await tx.update(salons)
          .set({ 
            cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric + ${balanceAdjustment.toString()}::numeric)` 
          })
          .where(eq(salons.id, salonId as string));
      }

      // 4. Update corresponding Ledger Entry
      const structuredNotes = {
        serviceName: name,
        paymentMethod: paymentMethod || 'CASH',
        userNotes: `Expense: ${name} (${category})`
      };

      await tx.update(ledgerEntries)
        .set({
          amount: amount.toString(),
          notes: JSON.stringify(structuredNotes),
          staffId: validStaffId,
          date: date ? new Date(date) : undefined,
        })
        .where(eq(ledgerEntries.expenseId, id as string));

      return updatedExpense;
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
  const { amount, category, name, date, staffId, paymentMethod } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  if (!name || !category) {
    return res.status(400).json({ message: 'Name and Category are required' });
  }

  // Validate amount (Bug #22: Amount validation)
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
      const [newExpense] = await tx.insert(expenses).values({
        amount: amount.toString(),
        category,
        name,
        date: date ? date : new Date().toISOString().split('T')[0],
        salonId: salonId as string,
      }).returning();

      // Deduct from Cash Balance (only if CASH)
      const isCash = !paymentMethod || paymentMethod.toUpperCase() === 'CASH';
      if (isCash) {
        await tx.update(salons)
          .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric - ${amount.toString()}::numeric)` })
          .where(eq(salons.id, salonId as string));
      }

      // Sync with Ledger
      const structuredNotes = {
        serviceName: name,
        paymentMethod: paymentMethod || 'CASH',
        userNotes: `Expense: ${name} (${category})`
      };

      await tx.insert(ledgerEntries).values({
        salonId: salonId as string,
        expenseId: newExpense.id,
        staffId: validStaffId,
        type: 'DEBIT',
        amount: amount.toString(),
        category: 'EXPENSE',
        notes: JSON.stringify(structuredNotes),
        date: date ? new Date(date) : new Date(),
      });

      return newExpense;
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
      const [deletedExpense] = await tx.delete(expenses)
        .where(and(eq(expenses.id, id as string), eq(expenses.salonId, salonId as string)))
        .returning();

      if (!deletedExpense) return null;

      // Delete corresponding ledger entry
      await tx.delete(ledgerEntries)
        .where(eq(ledgerEntries.expenseId, id as string));

      // Reverse Cash Balance Deduction
      await tx.update(salons)
        .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric + ${deletedExpense.amount}::numeric)` })
        .where(eq(salons.id, salonId as string));

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
