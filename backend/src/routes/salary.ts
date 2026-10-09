import { Router } from 'express';
import { db } from '../db';
import { salaryDeductions, staff, ledgerEntries, salons, paymentAccounts } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, gte, lte, sql } from 'drizzle-orm';

const router = Router();

// Get salary deductions for a staff member
router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.salonId;
  const { staffId, startDate, endDate } = req.query;

  try {
    let whereClause = eq(salaryDeductions.salonId, salonId as string);

    if (req.user.role === 'STAFF') {
      const staffRecord = await db.query.staff.findFirst({
        where: and(eq(staff.userId, req.user.id as string), eq(staff.salonId, salonId as string))
      });
      if (staffRecord) {
        whereClause = and(whereClause, eq(salaryDeductions.staffId, staffRecord.id))!;
      }
    } else if (staffId) {
      whereClause = and(whereClause, eq(salaryDeductions.staffId, staffId as string))!;
    }

    if (startDate && endDate) {
      const start = startDate as string;
      const end = endDate as string;
      whereClause = and(
        whereClause,
        gte(salaryDeductions.date, start),
        lte(salaryDeductions.date, end)
      )!;
    }

    const deductions = await db.query.salaryDeductions.findMany({
      where: whereClause,
      with: {
        staff: true,
        paymentAccount: true,
        notedByUser: {
          columns: {
            password: false,
            plainPassword: false,
          }
        },
      },
      orderBy: (deductions, { desc }) => [desc(deductions.date), desc(deductions.createdAt)],
    });

    res.json(deductions);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching salary deductions' });
  }
});

// Add salary deduction/advance (Owner only)
router.post('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { staffId, type, amount, reason, date, paymentMethod, paymentAccountId } = req.body || {};
  const salonId = req.user.salonId;
  const userId = req.user.id;

  if (!staffId || !type || !amount) {
    return res.status(400).json({ message: 'Missing required fields: staffId, type, amount' });
  }

  if (!['DEDUCTION', 'ADVANCE'].includes(type)) {
    return res.status(400).json({ message: 'Type must be DEDUCTION or ADVANCE' });
  }

  // Validate amount (Bug #22: Amount validation)
  const amountNum = parseFloat(amount);
  if (isNaN(amountNum) || amountNum <= 0) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }

  try {
    // Security: Validate staff ownership
    const targetStaff = await db.query.staff.findFirst({
      where: and(eq(staff.id, staffId as string), eq(staff.salonId, salonId as string))
    });
    if (!targetStaff) return res.status(403).json({ message: 'Staff member does not belong to your salon' });

    const result = await db.transaction(async (tx) => {
      let matchedAccount: any = null;
      if (paymentAccountId) {
        matchedAccount = await tx.query.paymentAccounts.findFirst({
          where: and(
            eq(paymentAccounts.id, paymentAccountId),
            eq(paymentAccounts.salonId, salonId as string)
          )
        });
      }

      const method = (paymentMethod || 'CASH').toUpperCase();
      const isOnline = ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'BANK'].includes(method);
      const resolvedAccountName = matchedAccount?.accountName || null;

      const [newDeduction] = await tx.insert(salaryDeductions).values({
        staffId,
        salonId: salonId as string,
        type,
        amount: amount.toString(),
        reason: reason || null,
        paymentMethod: method,
        paymentAccountId: matchedAccount?.id || paymentAccountId || null,
        date: date || new Date().toISOString().split('T')[0],
        notedBy: userId as string,
      }).returning();

      const structuredNotes = JSON.stringify({
        paymentMethod: method,
        paymentAccountId: matchedAccount?.id || paymentAccountId || undefined,
        paymentAccountName: resolvedAccountName || undefined,
        userNotes: `Staff ${type}${resolvedAccountName ? ` (${resolvedAccountName})` : ''}: ${reason || 'N/A'}`
      });

      // Sync with Ledger
      // ADVANCE: Money goes OUT (DEBIT) -> reduces balance
      // DEDUCTION: Money comes IN (CREDIT) to settle the advance
      await tx.insert(ledgerEntries).values({
        salonId: salonId as string,
        staffId,
        salaryDeductionId: newDeduction.id,
        amount: amount.toString(),
        type: type === 'ADVANCE' ? 'DEBIT' : 'CREDIT',
        category: type === 'ADVANCE' ? 'STAFF_ADVANCE' : 'STAFF_DEDUCTION',
        notes: structuredNotes,
        date: date ? new Date(date) : new Date(),
      });

      // Update Salon Cash Balance (Only for ADVANCE if cash, as it's Money Out from drawer)
      if (type === 'ADVANCE' && !isOnline) {
        await tx.update(salons)
          .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric - ${amount.toString()}::numeric)` })
          .where(eq(salons.id, salonId as string));
      }

      return {
        ...newDeduction,
        paymentAccount: matchedAccount || null
      };
    });

    res.status(201).json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error creating salary deduction' });
  }
});

// Update salary deduction (Owner only)
router.patch('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { type, amount, reason, date, paymentMethod, paymentAccountId } = req.body || {};
  const salonId = req.user.salonId;

  try {
    const updateData: any = {};
    if (type) updateData.type = type;
    if (amount) {
      const amountNum = parseFloat(amount);
      if (isNaN(amountNum) || amountNum <= 0) {
        return res.status(400).json({ message: 'Amount must be a positive number' });
      }
      updateData.amount = amount.toString();
    }
    if (reason) updateData.reason = reason;
    if (date) updateData.date = date;
    if (paymentMethod) updateData.paymentMethod = paymentMethod.toUpperCase();
    if (paymentAccountId !== undefined) updateData.paymentAccountId = paymentAccountId;

    const result = await db.transaction(async (tx) => {
      const oldDeduction = await tx.query.salaryDeductions.findFirst({
        where: and(eq(salaryDeductions.id, id as string), eq(salaryDeductions.salonId, salonId as string))
      });
      if (!oldDeduction) return null;

      let matchedAccount: any = null;
      const targetAccountId = paymentAccountId || oldDeduction.paymentAccountId;
      if (targetAccountId) {
        matchedAccount = await tx.query.paymentAccounts.findFirst({
          where: and(
            eq(paymentAccounts.id, targetAccountId),
            eq(paymentAccounts.salonId, salonId as string)
          )
        });
      }

      const [updated] = await tx.update(salaryDeductions)
        .set(updateData)
        .where(and(eq(salaryDeductions.id, id as string), eq(salaryDeductions.salonId, salonId as string)))
        .returning();

      if (!updated) return null;

      // Revert old advance cash impact, apply new advance cash impact
      const oldMethod = (oldDeduction.paymentMethod || 'CASH').toUpperCase();
      const oldIsCash = !['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'BANK'].includes(oldMethod);
      const oldAdvCash = (oldDeduction.type === 'ADVANCE' && oldIsCash) ? parseFloat(oldDeduction.amount) : 0;

      const newMethod = (updated.paymentMethod || 'CASH').toUpperCase();
      const newIsCash = !['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'BANK'].includes(newMethod);
      const newAdvCash = (updated.type === 'ADVANCE' && newIsCash) ? parseFloat(updated.amount) : 0;

      const cashDiff = oldAdvCash - newAdvCash;
      if (cashDiff !== 0) {
        await tx.update(salons)
          .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric + ${cashDiff.toString()}::numeric)` })
          .where(eq(salons.id, salonId as string));
      }

      const resolvedAccountName = matchedAccount?.accountName || null;
      const structuredNotes = JSON.stringify({
        paymentMethod: newMethod,
        paymentAccountId: matchedAccount?.id || undefined,
        paymentAccountName: resolvedAccountName || undefined,
        userNotes: `Updated Staff ${type || updated.type}${resolvedAccountName ? ` (${resolvedAccountName})` : ''}: ${reason || updated.reason || 'N/A'}`
      });

      // Update corresponding Ledger Entry
      await tx.update(ledgerEntries)
        .set({
          amount: amount ? amount.toString() : undefined,
          type: type ? (type === 'ADVANCE' ? 'DEBIT' : 'CREDIT') : undefined,
          category: type ? (type === 'ADVANCE' ? 'STAFF_ADVANCE' : 'STAFF_DEDUCTION') : undefined,
          notes: structuredNotes,
          date: date ? new Date(date) : undefined,
        })
        .where(eq(ledgerEntries.salaryDeductionId, id as string));

      return {
        ...updated,
        paymentAccount: matchedAccount || null
      };
    });

    if (!result) return res.status(404).json({ message: 'Salary deduction not found' });
    res.json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error updating salary deduction' });
  }
});

// Delete salary deduction (Owner only)
router.delete('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.salonId;

  try {
    const result = await db.transaction(async (tx) => {
      const [deleted] = await tx.delete(salaryDeductions)
        .where(and(eq(salaryDeductions.id, id as string), eq(salaryDeductions.salonId, salonId as string)))
        .returning();

      if (!deleted) return null;

      // Delete corresponding ledger entry
      await tx.delete(ledgerEntries)
        .where(eq(ledgerEntries.salaryDeductionId, id as string));

      // Reverse Cash Balance Deduction only if it was an ADVANCE paid in Cash
      if (deleted.type === 'ADVANCE') {
        const isOnline = ['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL', 'BANK'].includes((deleted.paymentMethod || 'CASH').toUpperCase());
        if (!isOnline) {
          await tx.update(salons)
            .set({ cashBalance: sql`${salons.cashBalance} + ${deleted.amount}` })
            .where(eq(salons.id, salonId as string));
        }
      }
      return deleted;
    });

    if (!result) return res.status(404).json({ message: 'Salary deduction not found' });
    res.json({ message: 'Salary deduction deleted successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error deleting salary deduction' });
  }
});

export default router;
