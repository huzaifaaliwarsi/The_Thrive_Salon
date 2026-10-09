import { Router } from 'express';
import { db } from '../db';
import { salons, users, ledgerEntries } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { hashPassword, validatePassword } from '../utils/auth';
import { eq, and, sql, inArray } from 'drizzle-orm';
import { isCashSql, getSalonGallaBalances } from '../utils/ledger';

const router = Router();

// Create Salon and Owner (Super Admin only)
router.post('/', authenticate, authorize(['SUPER_ADMIN']), async (req, res) => {
  const { name, logo, address, timezone, inTimeLimit, outTimeLimit, lateTimeLimit, earlyExitTimeLimit, vatNumber } = req.body;
  const ownerEmail = req.body.ownerEmail?.toString().trim().toLowerCase();
  const ownerPassword = req.body.ownerPassword?.toString().trim();

  if (!ownerEmail || !ownerPassword) {
    return res.status(400).json({ message: 'Owner email and password are required' });
  }

  const pwdCheck = validatePassword(ownerPassword);
  if (!pwdCheck.valid) {
    return res.status(400).json({ message: pwdCheck.error });
  }

  try {
    const result = await db.transaction(async (tx) => {
      // Create Salon
      const [newSalon] = await tx.insert(salons).values({
        name,
        logo,
        address,
        timezone: timezone || 'Asia/Karachi',
        inTimeLimit: inTimeLimit || '09:00',
        outTimeLimit: outTimeLimit || '18:00',
        lateTimeLimit: lateTimeLimit || '09:15',
        earlyExitTimeLimit: earlyExitTimeLimit || '17:45',
        lateDeductionRate: req.body.lateDeductionRate ? req.body.lateDeductionRate.toString() : '10',
        earlyExitDeductionRate: req.body.earlyExitDeductionRate ? req.body.earlyExitDeductionRate.toString() : '10',
        vatNumber,
      }).returning();

      // Create Owner Account
      const hashedPassword = await hashPassword(ownerPassword);
      const [newOwner] = await tx.insert(users).values({
        email: ownerEmail,
        password: hashedPassword,
        plainPassword: ownerPassword,
        role: 'OWNER',
        salonId: newSalon.id,
      }).returning();

      const { password, plainPassword, ...safeOwner } = newOwner;
      return { salon: newSalon, owner: safeOwner };
    });

    res.status(201).json(result);
  } catch (error: any) {
    console.error(error);
    // Handle unique constraint violations specifically if possible
    const pgError = error.cause || error;
    if (pgError.code === '23505') {
       return res.status(400).json({ message: 'A user with this email already exists' });
    }
    res.status(500).json({ message: `Error: ${error.message || 'Internal Server Error'}` });
  }
});

// List Salons (Super Admin, Owner, or Staff)
router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), async (req: AuthRequest, res) => {
  try {
    const gallaEnd = new Date();
    gallaEnd.setHours(23, 59, 59, 999);
    const gallaStart = new Date();
    gallaStart.setDate(gallaStart.getDate() - 365);
    gallaStart.setHours(0, 0, 0, 0);

    if (req.user.role === 'OWNER' || req.user.role === 'STAFF') {
      const mySalon = await db.query.salons.findFirst({
        where: eq(salons.id, req.user.salonId as string),
        with: {
          users: {
            columns: {
              password: false,
              plainPassword: false,
            }
          },
        },
      });
      if (mySalon) {
        let cashBalance = Number(mySalon.cashBalance || 0);
        let onlineBalance = 0;
        try {
          const balances = await getSalonGallaBalances(mySalon.id, gallaStart, gallaEnd);
          cashBalance = balances.cashBalance;
          onlineBalance = balances.onlineBalance;
        } catch (balErr: any) {
          console.error('getSalonGallaBalances failed for mySalon:', balErr?.message);
        }
        return res.json([{
          ...mySalon,
          cashBalance,
          onlineBalance,
        }]);
      }
      return res.json([]);
    }

    const allSalons = await db.query.salons.findMany({
      with: {
        users: {
          columns: {
            password: false,
          }
        },
      },
    });

    const salonsWithBalances = await Promise.all(
      allSalons.map(async (salon) => {
        let cashBalance = Number(salon.cashBalance || 0);
        let onlineBalance = 0;
        try {
          const balances = await getSalonGallaBalances(salon.id, gallaStart, gallaEnd);
          cashBalance = balances.cashBalance;
          onlineBalance = balances.onlineBalance;
        } catch (balErr: any) {
          console.error('getSalonGallaBalances failed for salon:', salon.id, balErr?.message);
        }
        return {
          ...salon,
          cashBalance,
          onlineBalance,
        };
      })
    );

    res.json(salonsWithBalances);
  } catch (error: any) {
    console.error('Error fetching salons:', error);
    res.status(500).json({ message: 'Error fetching salons', error: error?.message || String(error) });
  }
});

// Refill / Extend Subscription (Super Admin only)
router.patch('/:id/subscription', authenticate, authorize(['SUPER_ADMIN']), async (req, res) => {
  const { id } = req.params;
  const { days, newDate, isLifetime } = req.body;

  try {
    const salon = await db.query.salons.findFirst({ where: eq(salons.id, id as string) });
    if (!salon) return res.status(404).json({ message: 'Salon not found' });

    let newEnd: Date;
    if (isLifetime === true || isLifetime === 'true') {
      newEnd = new Date('2099-12-31T23:59:59.999Z');
    } else if (newDate) {
      newEnd = new Date(newDate);
      if (isNaN(newEnd.getTime())) {
        return res.status(400).json({ message: 'Invalid expiry date format' });
      }
    } else {
      const numDays = Number(days);
      if (isNaN(numDays) || numDays <= 0) {
        return res.status(400).json({ message: 'Valid number of days is required' });
      }

      const currentEnd = salon.subscriptionEnd ? new Date(salon.subscriptionEnd) : new Date();
      const now = new Date();
      // If active and expires in the future, extend beyond current end date.
      // If already expired, start extending from now (today).
      const baseDate = currentEnd > now ? currentEnd : now;
      newEnd = new Date(baseDate.getTime() + (numDays * 24 * 60 * 60 * 1000));
    }

    await db.update(salons).set({ subscriptionEnd: newEnd }).where(eq(salons.id, id as string));
    res.json({ message: 'Branch subscription refilled successfully', newEnd: newEnd.toISOString() });
  } catch (error: any) {
    console.error(error);
    res.status(500).json({ message: 'Error refilling subscription: ' + (error?.message || 'Internal Server Error') });
  }
});

// Toggle Suspension (Super Admin only)
router.patch('/:id/toggle-suspension', authenticate, authorize(['SUPER_ADMIN']), async (req, res) => {
  const { id } = req.params;

  try {
    const salon = await db.query.salons.findFirst({ where: eq(salons.id, id as string) });
    if (!salon) return res.status(404).json({ message: 'Salon not found' });

    const newSuspended = salon.isSuspended === 'true' ? 'false' : 'true';
    await db.update(salons).set({ isSuspended: newSuspended }).where(eq(salons.id, id as string));
    res.json({ message: `Salon ${newSuspended === 'true' ? 'suspended' : 'activated'} successfully`, isSuspended: newSuspended });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error toggling suspension' });
  }
});

// Update Salon Details (Super Admin only)
router.patch('/:id', authenticate, authorize(['SUPER_ADMIN']), async (req, res) => {
  const { id } = req.params;
  const { name, address, logo, timezone, inTimeLimit, outTimeLimit, lateTimeLimit, earlyExitTimeLimit, lateDeductionRate, earlyExitDeductionRate, vatNumber, qrDomain } = req.body;

  if (lateDeductionRate !== undefined && Number(lateDeductionRate) < 0) {
    return res.status(400).json({ message: 'Late deduction rate/amount cannot be negative.' });
  }
  if (earlyExitDeductionRate !== undefined && Number(earlyExitDeductionRate) < 0) {
    return res.status(400).json({ message: 'Early exit deduction rate/amount cannot be negative.' });
  }

  try {
    const [updatedSalon] = await db.update(salons)
      .set({ name, address, logo, timezone, inTimeLimit, outTimeLimit, lateTimeLimit, earlyExitTimeLimit, lateDeductionRate, earlyExitDeductionRate, vatNumber, qrDomain })
      .where(eq(salons.id, id as string))
      .returning();
    
    if (!updatedSalon) return res.status(404).json({ message: 'Salon not found' });
    res.json(updatedSalon);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error updating salon' });
  }
});

// Reset Owner Password (Super Admin only)
router.patch('/:id/owner-password', authenticate, authorize(['SUPER_ADMIN']), async (req, res) => {
  const { id } = req.params;
  const { newPassword } = req.body;

  if (!newPassword) return res.status(400).json({ message: 'New password is required' });

  const pwdCheck = validatePassword(newPassword);
  if (!pwdCheck.valid) {
    return res.status(400).json({ message: pwdCheck.error });
  }

  try {
    const hashedPassword = await hashPassword(newPassword);
    // Find the owner of this salon
    const [updatedUser] = await db.update(users)
      .set({ 
        password: hashedPassword,
        plainPassword: newPassword // Still keeping plain password for admin view
      })
      .where(and(eq(users.salonId, id as string), eq(users.role, 'OWNER')))
      .returning();

    if (!updatedUser) return res.status(404).json({ message: 'Owner user not found for this salon' });
    res.json({ message: 'Owner password reset successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error resetting owner password' });
  }
});

// Update Salon Settings (Owner only)
router.patch('/settings/me', authenticate, authorize(['OWNER']), async (req: AuthRequest, res) => {
  const salonId = req.user.salonId;
  const { name, address, logo, timezone, inTimeLimit, outTimeLimit, lateTimeLimit, earlyExitTimeLimit, lateDeductionRate, earlyExitDeductionRate, vatNumber, qrDomain } = req.body;

  if (!salonId) return res.status(403).json({ message: 'No salon associated with this user' });

  if (lateDeductionRate !== undefined && Number(lateDeductionRate) < 0) {
    return res.status(400).json({ message: 'Late deduction rate/amount cannot be negative.' });
  }
  if (earlyExitDeductionRate !== undefined && Number(earlyExitDeductionRate) < 0) {
    return res.status(400).json({ message: 'Early exit deduction rate/amount cannot be negative.' });
  }

  try {
    const [updatedSalon] = await db.update(salons)
      .set({ name, address, logo, timezone, inTimeLimit, outTimeLimit, lateTimeLimit, earlyExitTimeLimit, lateDeductionRate, earlyExitDeductionRate, vatNumber, qrDomain })
      .where(eq(salons.id, salonId))
      .returning();
    
    res.json(updatedSalon);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error updating salon settings' });
  }
});

// Delete Salon (Super Admin only)
router.delete('/:id', authenticate, authorize(['SUPER_ADMIN']), async (req, res) => {
  const { id } = req.params;

  try {
    const [deletedSalon] = await db.delete(salons)
      .where(eq(salons.id, id as string))
      .returning();

    if (!deletedSalon) return res.status(404).json({ message: 'Salon not found' });
    res.json({ message: 'Salon deleted successfully' });
  } catch (error: any) {
    console.error(error);
    res.status(500).json({ message: `Error deleting salon: ${error.message}` });
  }
});

// Recalculate Cash Drawer (Owner/Super Admin)
router.post('/settings/me/recalculate-cash', authenticate, authorize(['OWNER', 'SUPER_ADMIN']), async (req: AuthRequest, res) => {
  const salonId = req.user.salonId || req.body.salonId;
  if (!salonId) return res.status(403).json({ message: 'No salon associated with this user' });

  try {
    const result = await db.transaction(async (tx) => {
      // General Salon Ledger: Calculate based on actual cash flows
      const sumResult = await tx.select({
        moneyIn: sql`SUM(
          CASE 
            -- Cash received from clients (both registered and walk-in)
            WHEN (${ledgerEntries.category} = 'PAYMENT' AND ${ledgerEntries.type} = 'DEBIT' AND ${ledgerEntries.vendorId} IS NULL AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Cash collected from staff deductions
            WHEN (${ledgerEntries.category} = 'STAFF_DEDUCTION' AND ${ledgerEntries.type} = 'CREDIT' AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Reconciliation Surplus Inflow
            WHEN (${ledgerEntries.category} = 'RECONCILIATION_ADJUSTMENT' AND ${ledgerEntries.type} = 'CREDIT') THEN ${ledgerEntries.amount}::numeric
            -- Staff Advance Repayment Inflow
            WHEN (${ledgerEntries.category} = 'STAFF_ADVANCE' AND ${ledgerEntries.type} = 'CREDIT' AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Vendor Refunds received
            WHEN (${ledgerEntries.category} = 'PAYMENT' AND ${ledgerEntries.type} = 'DEBIT' AND ${ledgerEntries.vendorId} IS NOT NULL AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            ELSE 0 
          END
        )`,
        moneyOut: sql`SUM(
          CASE 
            -- Expenses paid
            WHEN (${ledgerEntries.category} = 'EXPENSE' AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Cash purchases (anonymous)
            WHEN (${ledgerEntries.category} = 'PURCHASE' AND ${ledgerEntries.type} = 'DEBIT' AND ${ledgerEntries.vendorId} IS NULL AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Cash paid to vendors
            WHEN (${ledgerEntries.category} = 'PAYMENT' AND ${ledgerEntries.type} = 'CREDIT' AND ${ledgerEntries.vendorId} IS NOT NULL AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Staff advances paid
            WHEN (${ledgerEntries.category} = 'STAFF_ADVANCE' AND ${ledgerEntries.type} = 'DEBIT' AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Cash refunded to client on voided sale
            WHEN (${ledgerEntries.category} = 'VOID_REVERSAL' AND ${ledgerEntries.type} = 'CREDIT' AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Reconciliation Shortage Outflow
            WHEN (${ledgerEntries.category} = 'RECONCILIATION_ADJUSTMENT' AND ${ledgerEntries.type} = 'DEBIT') THEN ${ledgerEntries.amount}::numeric
            -- Salaries paid
            WHEN (${ledgerEntries.category} = 'SALARY' AND ${ledgerEntries.type} = 'DEBIT' AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            ELSE 0 
          END
        )`
      }).from(ledgerEntries).where(eq(ledgerEntries.salonId, salonId as string));

      const sums = sumResult[0] || { moneyIn: '0', moneyOut: '0' };
      const totalCredit = parseFloat(sums.moneyIn as string || '0');
      const totalDebit = parseFloat(sums.moneyOut as string || '0');
      const balance = Math.max(0, totalCredit - totalDebit);

      await tx.update(salons)
        .set({ cashBalance: balance.toString() })
        .where(eq(salons.id, salonId as string));

      return { balance };
    });

    res.json({ message: 'Cash drawer recalculated successfully', newBalance: result.balance });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error recalculating cash drawer' });
  }
});

export default router;
