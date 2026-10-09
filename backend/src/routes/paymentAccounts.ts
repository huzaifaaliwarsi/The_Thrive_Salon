import { Router } from 'express';
import { db } from '../db';
import { paymentAccounts, sales, expenses, purchases, salaryDeductions } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, desc } from 'drizzle-orm';
import { getSalonGallaBalances } from '../utils/ledger';

const router = Router();

router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN'
    ? (req.query.salonId as string || req.user.salonId)
    : req.user.salonId;

  if (!salonId) {
    return res.status(400).json({ message: 'Salon ID is required' });
  }

  const includeInactive = req.query.all === 'true' || req.query.includeInactive === 'true';

  try {
    const whereConditions = [eq(paymentAccounts.salonId, salonId as string)];
    if (!includeInactive) {
      whereConditions.push(eq(paymentAccounts.isActive, true));
    }

    const accounts = await db.query.paymentAccounts.findMany({
      where: and(...whereConditions),
      orderBy: [desc(paymentAccounts.createdAt)],
    });

    res.json(accounts);
  } catch (error: any) {
    console.error('Error fetching payment accounts:', error);
    res.status(500).json({ message: 'Error fetching payment accounts', error: error.message });
  }
});

router.post('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { accountName, accountTitle, accountNumber, iban, type, isActive } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN'
    ? (req.body.salonId || req.query.salonId || req.user.salonId)
    : req.user.salonId;

  if (!salonId) {
    return res.status(400).json({ message: 'Salon ID is required' });
  }

  const trimmedName = accountName?.toString().trim();
  if (!trimmedName) {
    return res.status(400).json({ message: 'Account name is required' });
  }

  try {
    const [newAccount] = await db.insert(paymentAccounts).values({
      salonId: salonId as string,
      accountName: trimmedName,
      accountTitle: accountTitle ? accountTitle.toString().trim() : null,
      accountNumber: accountNumber ? accountNumber.toString().trim() : null,
      iban: iban ? iban.toString().trim().toUpperCase() : null,
      type: type ? type.toString().trim().toUpperCase() : 'BANK',
      isActive: typeof isActive === 'boolean' ? isActive : true,
    }).returning();

    res.status(201).json(newAccount);
  } catch (error: any) {
    console.error('Error creating payment account:', error);
    res.status(500).json({ message: 'Error creating payment account', error: error.message });
  }
});

router.put('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const id = req.params.id as string;
  const { accountName, accountTitle, accountNumber, iban, type, isActive } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN'
    ? (req.body.salonId || req.query.salonId || req.user.salonId)
    : req.user.salonId;

  try {
    const existing = await db.query.paymentAccounts.findFirst({
      where: and(
        eq(paymentAccounts.id, id),
        eq(paymentAccounts.salonId, salonId as string)
      ),
    });

    if (!existing) {
      return res.status(404).json({ message: 'Payment account not found' });
    }

    const updatePayload: Record<string, any> = {
      updatedAt: new Date(),
    };

    if (accountName !== undefined) updatePayload.accountName = accountName.toString().trim();
    if (accountTitle !== undefined) updatePayload.accountTitle = accountTitle ? accountTitle.toString().trim() : null;
    if (accountNumber !== undefined) updatePayload.accountNumber = accountNumber ? accountNumber.toString().trim() : null;
    if (iban !== undefined) updatePayload.iban = iban ? iban.toString().trim().toUpperCase() : null;
    if (type !== undefined) updatePayload.type = type.toString().trim().toUpperCase();
    if (isActive !== undefined) updatePayload.isActive = Boolean(isActive);

    const [updated] = await db.update(paymentAccounts)
      .set(updatePayload)
      .where(and(
        eq(paymentAccounts.id, id),
        eq(paymentAccounts.salonId, salonId as string)
      ))
      .returning();

    res.json(updated);
  } catch (error: any) {
    console.error('Error updating payment account:', error);
    res.status(500).json({ message: 'Error updating payment account', error: error.message });
  }
});

router.delete('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const id = req.params.id as string;
  const salonId = req.user.role === 'SUPER_ADMIN'
    ? (req.query.salonId as string || req.user.salonId)
    : req.user.salonId;
  const permanent = req.query.permanent === 'true' || req.query.hard === 'true';

  try {
    const existing = await db.query.paymentAccounts.findFirst({
      where: and(
        eq(paymentAccounts.id, id),
        eq(paymentAccounts.salonId, salonId as string)
      ),
    });

    if (!existing) {
      return res.status(404).json({ message: 'Payment account not found' });
    }

    const { onlineBreakdown } = await getSalonGallaBalances(salonId as string);
    const currentBalance = Number(onlineBreakdown[existing.accountName] || 0);
    if (currentBalance !== 0) {
      return res.status(400).json({
        message: 'Cannot delete payment account with an active balance. Please transfer or withdraw funds first.'
      });
    }

    if (permanent) {
      await db.update(sales)
        .set({ paymentAccountId: null })
        .where(eq(sales.paymentAccountId, id))
        .catch(() => {});

      await db.update(expenses)
        .set({ paymentAccountId: null })
        .where(eq(expenses.paymentAccountId, id))
        .catch(() => {});

      await db.update(purchases)
        .set({ paymentAccountId: null })
        .where(eq(purchases.paymentAccountId, id))
        .catch(() => {});

      await db.update(salaryDeductions)
        .set({ paymentAccountId: null })
        .where(eq(salaryDeductions.paymentAccountId, id))
        .catch(() => {});

      await db.delete(paymentAccounts)
        .where(and(
          eq(paymentAccounts.id, id),
          eq(paymentAccounts.salonId, salonId as string)
        ));

      return res.json({ message: 'Payment account deleted successfully', id });
    }

    const [deactivated] = await db.update(paymentAccounts)
      .set({ isActive: false, updatedAt: new Date() })
      .where(and(
        eq(paymentAccounts.id, id),
        eq(paymentAccounts.salonId, salonId as string)
      ))
      .returning();

    res.json({ message: 'Payment account deactivated successfully', account: deactivated });
  } catch (error: any) {
    console.error('Error deleting payment account:', error);
    res.status(500).json({ message: 'Error deleting payment account', error: error.message });
  }
});

export default router;
