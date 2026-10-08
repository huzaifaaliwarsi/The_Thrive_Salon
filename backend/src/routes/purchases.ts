import { Router } from 'express';
import { db } from '../db';
import { purchases, inventoryItems, inventoryTransactions, ledgerEntries, vendors, salons, paymentAccounts } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, desc, sql } from 'drizzle-orm';

const router = Router();

router.post('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;
  const { vendorId, total, amountPaid, paymentMethod, paymentAccountId, paymentBreakdown, items, notes, date } = req.body;

  try {
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

      const [newPurchase] = await tx.insert(purchases).values({
        salonId: salonId as string,
        vendorId,
        total: total.toString(),
        amountPaid: amountPaid.toString(),
        paymentMethod,
        paymentAccountId: matchedAccount?.id || paymentAccountId || null,
        paymentBreakdown: paymentBreakdown ? (typeof paymentBreakdown === 'string' ? paymentBreakdown : JSON.stringify(paymentBreakdown)) : null,
        notes,
        date: date ? new Date(date) : new Date(),
      }).returning();

      if (items && items.length > 0) {
        for (const item of items) {
          const currentItemRes = await tx.select({
            stockQuantity: inventoryItems.stockQuantity,
            unitPrice: inventoryItems.unitPrice
          })
          .from(inventoryItems)
          .where(and(eq(inventoryItems.id, item.id), eq(inventoryItems.salonId, salonId as string)))
          .limit(1);

          let newUnitPrice = Number(item.unitPrice || 0);
          if (currentItemRes.length > 0) {
            const prevQty = Number(currentItemRes[0].stockQuantity || 0);
            const prevPrice = Number(currentItemRes[0].unitPrice || 0);
            const newQty = Number(item.quantity || 0);
            const newPrice = Number(item.unitPrice || 0);

            const totalQty = prevQty + newQty;
            if (totalQty > 0) {
              newUnitPrice = ((prevQty * prevPrice) + (newQty * newPrice)) / totalQty;
            } else {
              newUnitPrice = newPrice;
            }
          }

          await tx.update(inventoryItems)
            .set({ 
              stockQuantity: sql`${inventoryItems.stockQuantity} + ${item.quantity.toString()}`,
              unitPrice: newUnitPrice.toFixed(2)
            })
            .where(and(eq(inventoryItems.id, item.id), eq(inventoryItems.salonId, salonId as string)));

          await tx.insert(inventoryTransactions).values({
            itemId: item.id,
            salonId: salonId as string,
            type: 'IN',
            quantity: item.quantity.toString(),
            notes: `Purchase #${newPurchase.id.substring(0, 8)}`
          });
        }
      }

      const methodUpper = (paymentMethod || 'CASH').toUpperCase();
      const totalPaidNum = parseFloat(amountPaid || '0');
      let cashPaid = 0;
      let onlinePaid = 0;

      if (req.body.cashAmount !== undefined || req.body.onlineAmount !== undefined) {
        cashPaid = parseFloat(req.body.cashAmount?.toString() || '0');
        onlinePaid = parseFloat(req.body.onlineAmount?.toString() || '0');
      } else if (methodUpper === 'SPLIT') {
        cashPaid = Math.round((totalPaidNum / 2) * 100) / 100;
        onlinePaid = Math.round((totalPaidNum - cashPaid) * 100) / 100;
      } else if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL'].includes(methodUpper)) {
        onlinePaid = totalPaidNum;
      } else {
        cashPaid = totalPaidNum;
      }

      const resolvedAccountName = matchedAccount?.accountName || null;

      if (vendorId) {
        await tx.insert(ledgerEntries).values({
          salonId: salonId as string,
          vendorId,
          type: 'CREDIT',
          amount: total.toString(),
          category: 'PURCHASE',
          notes: `Purchase Bill - Total: PKR ${total}, Balance: PKR ${parseFloat(total) - (cashPaid + onlinePaid)}`,
          purchaseId: newPurchase.id,
          date: date ? new Date(date) : new Date(),
        });

        if (cashPaid > 0) {
          const cashNotes = JSON.stringify({
            paymentMethod: 'CASH',
            userNotes: `Payment for Purchase (Cash) #${newPurchase.id.substring(0, 8)}`
          });

          await tx.insert(ledgerEntries).values({
            salonId: salonId as string,
            vendorId,
            type: 'DEBIT',
            amount: cashPaid.toString(),
            category: 'PAYMENT',
            notes: cashNotes,
            purchaseId: newPurchase.id,
            date: date ? new Date(date) : new Date(),
          });
        }

        if (onlinePaid > 0) {
          const onlineMethod = methodUpper === 'SPLIT' || methodUpper === 'CASH' ? 'ONLINE' : methodUpper;
          const onlineNotes = JSON.stringify({
            paymentMethod: onlineMethod,
            paymentAccountId: matchedAccount?.id || paymentAccountId || undefined,
            paymentAccountName: resolvedAccountName || undefined,
            userNotes: `Payment for Purchase (${onlineMethod}${resolvedAccountName ? ` - ${resolvedAccountName}` : ''}) #${newPurchase.id.substring(0, 8)}`
          });

          await tx.insert(ledgerEntries).values({
            salonId: salonId as string,
            vendorId,
            type: 'DEBIT',
            amount: onlinePaid.toString(),
            category: 'PAYMENT',
            notes: onlineNotes,
            purchaseId: newPurchase.id,
            date: date ? new Date(date) : new Date(),
          });
        }

        const balanceImpact = parseFloat(total) - (cashPaid + onlinePaid);
        await tx.update(vendors)
          .set({ balance: sql`${vendors.balance} - ${balanceImpact.toString()}` })
          .where(eq(vendors.id, vendorId));

        if (cashPaid > 0) {
          await tx.update(salons)
            .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric - ${cashPaid.toString()}::numeric)` })
            .where(eq(salons.id, salonId as string));
        }
      } else {
        if (cashPaid > 0) {
          const cashNotes = JSON.stringify({
            paymentMethod: 'CASH',
            userNotes: `Purchase (Cash): ${notes || 'N/A'}`
          });

          await tx.insert(ledgerEntries).values({
            salonId: salonId as string,
            vendorId: null,
            type: 'DEBIT',
            amount: cashPaid.toString(),
            category: 'PURCHASE',
            notes: cashNotes,
            purchaseId: newPurchase.id,
            date: date ? new Date(date) : new Date(),
          });

          await tx.update(salons)
            .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric - ${cashPaid.toString()}::numeric)` })
            .where(eq(salons.id, salonId as string));
        }

        if (onlinePaid > 0) {
          const onlineMethod = methodUpper === 'SPLIT' || methodUpper === 'CASH' ? 'ONLINE' : methodUpper;
          const onlineNotes = JSON.stringify({
            paymentMethod: onlineMethod,
            paymentAccountId: matchedAccount?.id || paymentAccountId || undefined,
            paymentAccountName: resolvedAccountName || undefined,
            userNotes: `Purchase (${onlineMethod}${resolvedAccountName ? ` - ${resolvedAccountName}` : ''}): ${notes || 'N/A'}`
          });

          await tx.insert(ledgerEntries).values({
            salonId: salonId as string,
            vendorId: null,
            type: 'DEBIT',
            amount: onlinePaid.toString(),
            category: 'PURCHASE',
            notes: onlineNotes,
            purchaseId: newPurchase.id,
            date: date ? new Date(date) : new Date(),
          });
        }
      }

      return newPurchase;
    });

    res.status(201).json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error recording purchase' });
  }
});

router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.query.salonId as string) : req.user.salonId;
  try {
    const allPurchases = await db.query.purchases.findMany({
      where: eq(purchases.salonId, salonId as string),
      orderBy: [desc(purchases.createdAt)],
      with: {
        vendor: true,
        paymentAccount: true
      }
    });
    res.json(allPurchases);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching purchases' });
  }
});

export default router;
