import { Router } from 'express';
import { db } from '../db';
import { sales, expenses, attendance, ledgerEntries, inventoryTransactions, salaryDeductions, appointments, purchases } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq } from 'drizzle-orm';

const router = Router();

router.post('/clear-history', authenticate, authorize(['OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.salonId;
  const { confirm } = req.body;

  if (confirm !== 'PERMANENTLY DELETE HISTORY') {
    return res.status(400).json({ message: 'Invalid confirmation phrase' });
  }

  try {
    await db.transaction(async (tx) => {
      // Delete transactional data
      await tx.delete(sales).where(eq(sales.salonId, salonId as string));
      await tx.delete(expenses).where(eq(expenses.salonId, salonId as string));
      await tx.delete(attendance).where(eq(attendance.salonId, salonId as string));
      await tx.delete(ledgerEntries).where(eq(ledgerEntries.salonId, salonId as string));
      await tx.delete(inventoryTransactions).where(eq(inventoryTransactions.salonId, salonId as string));
      await tx.delete(salaryDeductions).where(eq(salaryDeductions.salonId, salonId as string));
      await tx.delete(appointments).where(eq(appointments.salonId, salonId as string));
      await tx.delete(purchases).where(eq(purchases.salonId, salonId as string));
    });

    res.json({ message: 'History cleared successfully. Core data (Staff, Services, Clients, Vendors, Inventory) remains intact.' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error clearing history' });
  }
});

export default router;
