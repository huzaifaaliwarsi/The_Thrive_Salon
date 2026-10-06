import { Router } from 'express';
import { db } from '../db';
import { ledgerEntries, clients, vendors, salons, staff, purchases, sales } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, desc, asc, sql, or } from 'drizzle-orm';
import { isCashSql } from '../utils/ledger';

const router = Router();

// List Ledger Entries
router.get('/', authenticate, authorize(['OWNER', 'STAFF', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const { clientId, vendorId, staffId, salonId: querySalonId, limit, offset, includeOnline } = req.query;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (querySalonId || req.user.salonId) : req.user.salonId;
  if (!salonId) return res.status(403).json({ message: 'Unauthorized: No salon ID' });

  try {
    let whereClause = eq(ledgerEntries.salonId, salonId as string);
    if (clientId) {
      whereClause = and(whereClause, eq(ledgerEntries.clientId, clientId as string))!;
    } else if (vendorId) {
      whereClause = and(whereClause, eq(ledgerEntries.vendorId, vendorId as string))!;
    } else if (staffId) {
      whereClause = and(whereClause, eq(ledgerEntries.staffId, staffId as string))!;
    } else {
      // General Salon Ledger / Cash Drawer: Only display actual cash flows unless includeOnline is true
      const cashFilter = includeOnline === 'true' ? sql`true` : isCashSql;
      whereClause = and(
        whereClause,
        sql`(
          (${ledgerEntries.category} = 'PAYMENT' AND ${ledgerEntries.type} = 'DEBIT' AND ${cashFilter}) OR
          (${ledgerEntries.category} = 'STAFF_DEDUCTION' AND ${ledgerEntries.type} = 'CREDIT' AND ${cashFilter}) OR
          (${ledgerEntries.category} = 'RECONCILIATION_ADJUSTMENT') OR
          (${ledgerEntries.category} = 'EXPENSE' AND ${cashFilter}) OR
          (${ledgerEntries.category} = 'PURCHASE' AND ${ledgerEntries.type} = 'DEBIT' AND ${cashFilter}) OR
          (${ledgerEntries.category} = 'STAFF_ADVANCE' AND ${ledgerEntries.type} = 'DEBIT' AND ${cashFilter}) OR
          (${ledgerEntries.category} = 'SALARY' AND ${ledgerEntries.type} = 'DEBIT' AND ${cashFilter}) OR
          (${ledgerEntries.category} = 'STAFF_PAYMENT' AND ${ledgerEntries.type} = 'DEBIT' AND ${cashFilter}) OR
          (${ledgerEntries.category} = 'VOID_REVERSAL' AND ${ledgerEntries.type} = 'CREDIT' AND ${cashFilter})
        )`
      )!;
    }

    const entries = await db.query.ledgerEntries.findMany({
      where: whereClause,
      orderBy: [desc(ledgerEntries.date)],
      limit: limit ? parseInt(limit as string) : 50,
      offset: offset ? parseInt(offset as string) : 0,
      with: {
        client: true,
        vendor: true,
        staff: true
      }
    });

    // Calculate totals and balance based on filter
    let totalCredit = 0;
    let totalDebit = 0;
    let balance = 0;

    if (!clientId && !vendorId && !staffId) {
      // General Salon Ledger: Calculate based on actual cash flows
      const sumResult = await db.select({
        moneyIn: sql`SUM(
          CASE 
            -- Cash received from clients (both registered and walk-in)
            WHEN (${ledgerEntries.category} = 'PAYMENT' AND ${ledgerEntries.type} = 'DEBIT' AND ${ledgerEntries.vendorId} IS NULL AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Cash collected from staff deductions
            WHEN (${ledgerEntries.category} = 'STAFF_DEDUCTION' AND ${ledgerEntries.type} = 'CREDIT' AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Reconciliation Surplus Inflow
            WHEN (${ledgerEntries.category} = 'RECONCILIATION_ADJUSTMENT' AND ${ledgerEntries.type} = 'CREDIT') THEN ${ledgerEntries.amount}::numeric
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
            WHEN (${ledgerEntries.category} = 'PAYMENT' AND ${ledgerEntries.type} = 'DEBIT' AND ${ledgerEntries.vendorId} IS NOT NULL AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Staff advances paid
            WHEN (${ledgerEntries.category} = 'STAFF_ADVANCE' AND ${ledgerEntries.type} = 'DEBIT' AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Cash refunded to client on voided sale
            WHEN (${ledgerEntries.category} = 'VOID_REVERSAL' AND ${ledgerEntries.type} = 'CREDIT' AND ${isCashSql}) THEN ${ledgerEntries.amount}::numeric
            -- Reconciliation Shortage Outflow
            WHEN (${ledgerEntries.category} = 'RECONCILIATION_ADJUSTMENT' AND ${ledgerEntries.type} = 'DEBIT') THEN ${ledgerEntries.amount}::numeric
            ELSE 0 
          END
        )`
      }).from(ledgerEntries).where(whereClause);

      const sums = sumResult[0] || { moneyIn: '0', moneyOut: '0' };
      totalCredit = parseFloat(sums.moneyIn as string || '0');
      totalDebit = parseFloat(sums.moneyOut as string || '0');
      balance = totalCredit - totalDebit;
    } else {
      // Individual client / vendor / staff ledger
      const totalsResult = await db.select({
        totalCredit: sql`SUM(CASE WHEN ${ledgerEntries.type} = 'CREDIT' THEN ${ledgerEntries.amount}::numeric ELSE 0 END)`,
        totalDebit: sql`SUM(CASE WHEN ${ledgerEntries.type} = 'DEBIT' THEN ${ledgerEntries.amount}::numeric ELSE 0 END)`
      }).from(ledgerEntries)
      .leftJoin(sales, eq(ledgerEntries.saleId, sales.id))
      .where(and(whereClause, sql`(${sales.id} IS NULL OR ${sales.status} != 'VOID')`));

      const summaryRaw = totalsResult[0] || { totalCredit: '0', totalDebit: '0' };
      totalCredit = parseFloat(summaryRaw.totalCredit as string || '0');
      totalDebit = parseFloat(summaryRaw.totalDebit as string || '0');
      
      balance = totalCredit - totalDebit;
      if (staffId) {
        balance = totalDebit - totalCredit;
      }
    }

    // Map entries to assign correct visual type for General view without breaking individual accounts
    const mappedEntries = entries.map(entry => {
      let displayType = entry.type;
      
      if (!clientId && !vendorId && !staffId) {
        // Map to user-friendly "CREDIT" (Inflow) or "DEBIT" (Outflow) for General Salon Ledger
        if (entry.category === 'PAYMENT' && entry.type === 'DEBIT' && !entry.vendorId) {
          displayType = 'CREDIT'; // Client payment received (Inflow)
        } else if (entry.category === 'STAFF_DEDUCTION' && entry.type === 'CREDIT') {
          displayType = 'CREDIT'; // Staff deduction received (Inflow)
        } else if (entry.category === 'RECONCILIATION_ADJUSTMENT' && entry.type === 'CREDIT') {
          displayType = 'CREDIT'; // Reconciliation surplus (Inflow)
        } else if (entry.category === 'EXPENSE') {
          displayType = 'DEBIT'; // Expense paid (Outflow)
        } else if (entry.category === 'PURCHASE' && entry.type === 'DEBIT' && !entry.vendorId) {
          displayType = 'DEBIT'; // Cash purchase paid (Outflow)
        } else if (entry.category === 'PAYMENT' && entry.type === 'DEBIT' && entry.vendorId) {
          displayType = 'DEBIT'; // Vendor payment paid (Outflow)
        } else if (entry.category === 'STAFF_ADVANCE' && entry.type === 'DEBIT') {
          displayType = 'DEBIT'; // Staff advance paid (Outflow)
        } else if (entry.category === 'VOID_REVERSAL' && entry.type === 'CREDIT') {
          displayType = 'DEBIT'; // Cash refunded to client (Outflow)
        } else if (entry.category === 'RECONCILIATION_ADJUSTMENT' && entry.type === 'DEBIT') {
          displayType = 'DEBIT'; // Reconciliation shortage (Outflow)
        }
      }
      
      return {
        ...entry,
        type: displayType
      };
    });

    res.json({
      entries: mappedEntries,
      summary: {
        totalCredit,
        totalDebit,
        balance
      }
    });
  } catch (error) {
    console.error('[Ledger Error]:', error);
    res.status(500).json({ message: 'Error fetching ledger', details: error instanceof Error ? error.message : String(error) });
  }
});

// Helper to calculate financial impact of a ledger entry
function getLedgerImpact(entry: { clientId?: string | null; vendorId?: string | null; staffId?: string | null; amount: string; type: string; notes?: string | null }) {
  let clientBalanceDiff = 0;
  let vendorBalanceDiff = 0;
  let cashDiff = 0;

  let structData: any = null;
  try {
    if (entry.notes && entry.notes.trim().startsWith('{') && entry.notes.trim().endsWith('}')) {
      structData = JSON.parse(entry.notes);
    }
  } catch (e) {}

  const amtNum = parseFloat(structData?.paidAmount || structData?.amount || entry.amount || '0');
  const remaining = parseFloat(structData?.remainingAmount || '0');

  const rawNotesStr = (entry.notes || '').toUpperCase();
  const method = (structData?.paymentMethod || '').toString().toUpperCase();
  const isOnline = method === 'ONLINE' || method === 'CARD' || method === 'BANK_TRANSFER' || method === 'UPI' || method === 'DIGITAL' || method === 'CHECK' || method === 'CHEQUE' || method === 'CHQ' || 
                   rawNotesStr.includes('ONLINE') || rawNotesStr.includes('CARD') || rawNotesStr.includes('BANK') || rawNotesStr.includes('UPI') || rawNotesStr.includes('CHECK') || rawNotesStr.includes('CHEQUE') || rawNotesStr.includes('CHQ');

  if (entry.clientId) {
    if (entry.type === 'DEBIT' || structData?.transactionType === 'PURE_PAYMENT') {
      clientBalanceDiff = -amtNum; // DEBIT decreases debt owed by client
      cashDiff = isOnline ? 0 : amtNum; // Money IN to salon
    } else {
      clientBalanceDiff = remaining > 0 ? remaining : amtNum; // CREDIT increases debt
      cashDiff = isOnline ? 0 : amtNum;
    }
  } else if (entry.vendorId) {
    if (entry.type === 'DEBIT' || structData?.transactionType === 'PURE_PAYMENT') {
      vendorBalanceDiff = amtNum; // DEBIT decreases debt owed to vendor
      cashDiff = isOnline ? 0 : -amtNum; // Money OUT from salon cash drawer
    } else {
      vendorBalanceDiff = -(remaining > 0 ? remaining : amtNum); // CREDIT increases debt owed to vendor
      cashDiff = 0; // Credit purchase does not affect cash drawer until paid
    }
  } else {
    // General entries or staff entries
    if (entry.type === 'CREDIT') {
      cashDiff = isOnline ? 0 : amtNum; // Inflow
    } else {
      cashDiff = isOnline ? 0 : -amtNum; // Outflow
    }
  }

  return { clientBalanceDiff, vendorBalanceDiff, cashDiff };
}

// Add Manual Payment / Settlement
router.post('/payment', authenticate, authorize(['OWNER', 'STAFF', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const { clientId, vendorId, amount, type, notes: rawNotes, date, salonId: bodySalonId, purchaseId, saleId, paymentMethod: rawPaymentMethod } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (bodySalonId || req.user.salonId) : req.user.salonId;

  let detectedMethod = (rawPaymentMethod || '').toUpperCase();
  if (!detectedMethod && rawNotes && rawNotes.trim().startsWith('{') && rawNotes.trim().endsWith('}')) {
    try {
      const parsed = JSON.parse(rawNotes);
      if (parsed.paymentMethod) detectedMethod = parsed.paymentMethod.toString().toUpperCase();
    } catch (_) {}
  }
  const paymentMethod = detectedMethod || 'CASH';

  let notes = rawNotes;
  if (!rawNotes || (!rawNotes.trim().startsWith('{') || !rawNotes.trim().endsWith('}'))) {
    notes = JSON.stringify({
      paymentMethod,
      transactionType: 'PURE_PAYMENT',
      paidAmount: parseFloat(amount?.toString() || '0'),
      userNotes: rawNotes || `Payment of PKR ${amount}`
    });
  } else {
    try {
      const parsed = JSON.parse(rawNotes);
      parsed.paymentMethod = paymentMethod;
      notes = JSON.stringify(parsed);
    } catch (_) {}
  }

  try {
    const result = await db.transaction(async (tx) => {
      // Calculate impact using helper
      const { clientBalanceDiff, vendorBalanceDiff, cashDiff } = getLedgerImpact({
        clientId,
        vendorId,
        amount: amount.toString(),
        type,
        notes
      });

      let newEntries: any[] = [];
      // Parse payment date: if client sends local time (no tz suffix), convert to UTC using timezoneOffset (PKT=300 min)
      let paymentDate: Date;
      if (date) {
        const dateStr = date.toString();
        // If date string has explicit Z or +HH:mm offset, parse directly (already UTC or tz-aware)
        if (dateStr.includes('Z') || dateStr.match(/[+-]\d{2}:\d{2}$/)) {
          paymentDate = new Date(dateStr);
        } else {
          // No timezone suffix → treat as local time, convert to UTC using offset (default PKT = UTC+5 = 300 min)
          const offsetMin = parseInt(req.body.timezoneOffset?.toString() || '300', 10);
          paymentDate = new Date(new Date(dateStr).getTime() - offsetMin * 60 * 1000);
        }
      } else {
        paymentDate = new Date();
      }


      let structData: any = null;
      try {
        if (notes && notes.trim().startsWith('{') && notes.trim().endsWith('}')) {
          structData = JSON.parse(notes);
        }
      } catch (e) {}

      if (clientId && type === 'DEBIT' && !saleId) {
        // FIFO Auto-Allocation
        let remainingToAllocate = parseFloat(amount.toString());
        
        const clientObj = await tx.query.clients.findFirst({ where: eq(clients.id, clientId as string) });

        // Find unpaid sales for this client (matching clientId, client phone, or client name)
        const clientSales = await tx.select({
          id: sales.id,
          total: sales.total,
          amountPaid: sales.amountPaid,
          createdAt: sales.createdAt
        })
        .from(sales)
        .where(and(
           eq(sales.salonId, salonId as string),
           eq(sales.status, 'ACTIVE'),
           sql`CAST(COALESCE(${sales.amountPaid}, '0') AS NUMERIC) < CAST(${sales.total} AS NUMERIC)`,
           or(
             clientObj?.phone ? eq(sales.customerPhone, clientObj.phone) : sql`false`,
             clientObj?.name ? eq(sales.customerName, clientObj.name) : sql`false`,
             sql`EXISTS (SELECT 1 FROM ledger_entries le WHERE le.sale_id = sales.id AND le.client_id = ${clientId}::uuid)`
           )
        ))
        .orderBy(asc(sales.createdAt));

        for (const sale of clientSales) {
           if (remainingToAllocate <= 0) break;
           const saleDebt = parseFloat(sale.total) - parseFloat(sale.amountPaid || '0');
           const allocated = Math.min(saleDebt, remainingToAllocate);
           
           if (allocated > 0) {
             await tx.update(sales)
                .set({ amountPaid: sql`CAST(COALESCE(${sales.amountPaid}, '0') AS NUMERIC) + ${allocated}::numeric` })
                .where(eq(sales.id, sale.id));
                
             const [allocatedEntry] = await tx.insert(ledgerEntries).values({
                salonId: salonId as string,
                clientId,
                saleId: sale.id,
                amount: allocated.toString(),
                type: 'DEBIT',
                category: 'PAYMENT',
                notes: notes,
                date: paymentDate,
             }).returning();
             
             newEntries.push(allocatedEntry);
             remainingToAllocate -= allocated;
           }
        }
        
        if (remainingToAllocate > 0) {
           const [unallocatedEntry] = await tx.insert(ledgerEntries).values({
              salonId: salonId as string,
              clientId,
              amount: remainingToAllocate.toString(),
              type: 'DEBIT',
              category: 'PAYMENT',
              notes: notes,
              date: paymentDate,
           }).returning();
           newEntries.push(unallocatedEntry);
        }
      } else if (vendorId && type === 'DEBIT' && !purchaseId) {
        // FIFO Auto-Allocation for Vendor Purchases
        let remainingToAllocate = parseFloat(amount.toString());

        const unpaidPurchases = await tx.select({
          id: purchases.id,
          total: purchases.total,
          amountPaid: purchases.amountPaid,
          date: purchases.date,
          createdAt: purchases.createdAt
        })
        .from(purchases)
        .where(and(
          eq(purchases.salonId, salonId as string),
          eq(purchases.vendorId, vendorId as string),
          sql`CAST(COALESCE(${purchases.amountPaid}, '0') AS NUMERIC) < CAST(${purchases.total} AS NUMERIC)`
        ))
        .orderBy(asc(purchases.date), asc(purchases.createdAt));

        for (const purchase of unpaidPurchases) {
          if (remainingToAllocate <= 0) break;
          const purchaseDebt = parseFloat(purchase.total) - parseFloat(purchase.amountPaid || '0');
          const allocated = Math.min(purchaseDebt, remainingToAllocate);

          if (allocated > 0) {
            await tx.update(purchases)
              .set({ amountPaid: sql`CAST(COALESCE(${purchases.amountPaid}, '0') AS NUMERIC) + ${allocated}::numeric` })
              .where(eq(purchases.id, purchase.id));

            const [allocatedEntry] = await tx.insert(ledgerEntries).values({
              salonId: salonId as string,
              vendorId,
              purchaseId: purchase.id,
              amount: allocated.toString(),
              type: 'DEBIT',
              category: 'PAYMENT',
              notes: notes,
              date: paymentDate,
            }).returning();

            newEntries.push(allocatedEntry);
            remainingToAllocate -= allocated;
          }
        }

        if (remainingToAllocate > 0) {
          const [unallocatedEntry] = await tx.insert(ledgerEntries).values({
            salonId: salonId as string,
            vendorId,
            amount: remainingToAllocate.toString(),
            type: 'DEBIT',
            category: 'PAYMENT',
            notes: notes,
            date: paymentDate,
          }).returning();
          newEntries.push(unallocatedEntry);
        }
      } else {
        // Standard single ledger entry creation
        const [singleEntry] = await tx.insert(ledgerEntries).values({
          salonId: salonId as string,
          clientId,
          vendorId,
          purchaseId: purchaseId || null,
          saleId: saleId || null,
          amount: amount.toString(),
          type,
          category: 'PAYMENT',
          notes,
          date: paymentDate,
        }).returning();
        
        newEntries.push(singleEntry);

        // Update Specific Sale Payment
        if (saleId && type === 'DEBIT') {
          await tx.update(sales)
            .set({ amountPaid: sql`CAST(COALESCE(${sales.amountPaid}, '0') AS NUMERIC) + ${amount.toString()}::numeric` })
            .where(eq(sales.id, saleId));
        }

        // Update Specific Purchase Payment
        if (purchaseId && type === 'DEBIT') {
          await tx.update(purchases)
            .set({ amountPaid: sql`CAST(COALESCE(${purchases.amountPaid}, '0') AS NUMERIC) + ${amount.toString()}::numeric` })
            .where(eq(purchases.id, purchaseId));
        }
      }

      // Apply Balance Updates
      if (clientId && clientBalanceDiff !== 0) {
        await tx.update(clients)
          .set({ balance: sql`${clients.balance} + ${clientBalanceDiff.toString()}::numeric` })
          .where(eq(clients.id, clientId));
      }

      if (vendorId && vendorBalanceDiff !== 0) {
        await tx.update(vendors)
          .set({ balance: sql`${vendors.balance} + ${vendorBalanceDiff.toString()}::numeric` })
          .where(eq(vendors.id, vendorId));
      }

      if (cashDiff !== 0) {
        await tx.update(salons)
          .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric + ${cashDiff.toString()}::numeric)` })
          .where(eq(salons.id, salonId as string));
      }

      return newEntries[0];
    });

    res.status(201).json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error recording payment' });
  }
});

// Update Ledger Entry
router.put('/payment/:id', authenticate, authorize(['OWNER', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { amount, type, notes, date, purchaseId } = req.body;
  const salonId = req.user.salonId;

  try {
    const result = await db.transaction(async (tx) => {
      // 1. Get old entry to reverse its impact
      const oldEntry = await tx.query.ledgerEntries.findFirst({
        where: and(eq(ledgerEntries.id, id as string), eq(ledgerEntries.salonId, salonId as string))
      });
      if (!oldEntry) throw new Error('Entry not found');

      const oldImpact = getLedgerImpact(oldEntry);

      if (oldEntry.purchaseId && oldEntry.type === 'DEBIT') {
        await tx.update(purchases)
          .set({ amountPaid: sql`CAST(COALESCE(${purchases.amountPaid}, '0') AS NUMERIC) - ${oldEntry.amount}::numeric` })
          .where(eq(purchases.id, oldEntry.purchaseId));
      }

      if (oldEntry.saleId && oldEntry.type === 'DEBIT') {
        await tx.update(sales)
          .set({ amountPaid: sql`CAST(COALESCE(${sales.amountPaid}, '0') AS NUMERIC) - ${oldEntry.amount}::numeric` })
          .where(eq(sales.id, oldEntry.saleId));
      }

      // 2. Update Entry
      const [updated] = await tx.update(ledgerEntries)
        .set({ 
          amount: amount.toString(), 
          type, 
          notes, 
          purchaseId: purchaseId !== undefined ? purchaseId : oldEntry.purchaseId,
          saleId: oldEntry.saleId,
          date: date ? new Date(date) : undefined 
        })
        .where(eq(ledgerEntries.id, id as string))
        .returning();

      const newImpact = getLedgerImpact(updated);

      if (updated.purchaseId && updated.type === 'DEBIT') {
        await tx.update(purchases)
          .set({ amountPaid: sql`CAST(COALESCE(${purchases.amountPaid}, '0') AS NUMERIC) + ${updated.amount}::numeric` })
          .where(eq(purchases.id, updated.purchaseId));
      }

      if (updated.saleId && updated.type === 'DEBIT') {
        await tx.update(sales)
          .set({ amountPaid: sql`CAST(COALESCE(${sales.amountPaid}, '0') AS NUMERIC) + ${updated.amount}::numeric` })
          .where(eq(sales.id, updated.saleId));
      }

      // 3. Apply Difference (New Impact - Old Impact)
      if (oldEntry.clientId) {
        const netClientBalance = newImpact.clientBalanceDiff - oldImpact.clientBalanceDiff;
        if (netClientBalance !== 0) {
          await tx.update(clients)
            .set({ balance: sql`${clients.balance} + ${netClientBalance.toString()}::numeric` })
            .where(eq(clients.id, oldEntry.clientId));
        }
      }

      if (oldEntry.vendorId) {
        const netVendorBalance = newImpact.vendorBalanceDiff - oldImpact.vendorBalanceDiff;
        if (netVendorBalance !== 0) {
          await tx.update(vendors)
            .set({ balance: sql`${vendors.balance} + ${netVendorBalance.toString()}::numeric` })
            .where(eq(vendors.id, oldEntry.vendorId));
        }
      }

      const netCash = newImpact.cashDiff - oldImpact.cashDiff;
      if (netCash !== 0) {
        await tx.update(salons)
          .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric + ${netCash.toString()}::numeric)` })
          .where(eq(salons.id, salonId as string));
      }

      return updated;
    });

    res.json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: error instanceof Error ? error.message : 'Error updating ledger entry' });
  }
});

// Delete Ledger Entry
router.delete('/payment/:id', authenticate, authorize(['OWNER', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.salonId;

  try {
    await db.transaction(async (tx) => {
      const entry = await tx.query.ledgerEntries.findFirst({
        where: and(eq(ledgerEntries.id, id as string), eq(ledgerEntries.salonId, salonId as string))
      });
      if (!entry) throw new Error('Entry not found');

      const oldImpact = getLedgerImpact(entry);

      if (entry.purchaseId && entry.type === 'DEBIT') {
        await tx.update(purchases)
          .set({ amountPaid: sql`CAST(COALESCE(${purchases.amountPaid}, '0') AS NUMERIC) - ${entry.amount}::numeric` })
          .where(eq(purchases.id, entry.purchaseId));
      }

      if (entry.saleId && entry.type === 'DEBIT') {
        await tx.update(sales)
          .set({ amountPaid: sql`CAST(COALESCE(${sales.amountPaid}, '0') AS NUMERIC) - ${entry.amount}::numeric` })
          .where(eq(sales.id, entry.saleId));
      }

      // 1. Delete Entry
      await tx.delete(ledgerEntries).where(eq(ledgerEntries.id, id as string));

      // 2. Reverse Balance (Subtract original impact)
      if (entry.clientId && oldImpact.clientBalanceDiff !== 0) {
        await tx.update(clients)
          .set({ balance: sql`${clients.balance} - ${oldImpact.clientBalanceDiff.toString()}::numeric` })
          .where(eq(clients.id, entry.clientId));
      }

      if (entry.vendorId && oldImpact.vendorBalanceDiff !== 0) {
        await tx.update(vendors)
          .set({ balance: sql`${vendors.balance} - ${oldImpact.vendorBalanceDiff.toString()}::numeric` })
          .where(eq(vendors.id, entry.vendorId));
      }

      if (oldImpact.cashDiff !== 0) {
        await tx.update(salons)
          .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric - ${oldImpact.cashDiff.toString()}::numeric)` })
          .where(eq(salons.id, salonId as string));
      }
    });

    res.json({ message: 'Entry deleted and balance adjusted' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: error instanceof Error ? error.message : 'Error deleting ledger entry' });
  }
});

// Add Reconciliation Adjustment
router.post('/reconcile', authenticate, authorize(['OWNER', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const { amount, type, notes } = req.body;
  const salonId = req.user.salonId;
  if (!salonId) return res.status(403).json({ message: 'Unauthorized: No salon ID' });

  try {
    const result = await db.transaction(async (tx) => {
      const amtNum = parseFloat(amount.toString());
      const cashDiff = type === 'CREDIT' ? amtNum : -amtNum; // CREDIT = Surplus, DEBIT = Shortage

      // Insert ledger entry
      const [newEntry] = await tx.insert(ledgerEntries).values({
        salonId: salonId as string,
        amount: amount.toString(),
        type,
        category: 'RECONCILIATION_ADJUSTMENT',
        notes: notes || 'Cash Drawer Reconciliation Adjustment',
        date: new Date(),
      }).returning();

      if (cashDiff !== 0) {
        await tx.update(salons)
          .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric + ${cashDiff.toString()}::numeric)` })
          .where(eq(salons.id, salonId as string));
      }

      return newEntry;
    });

    res.status(201).json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error recording reconciliation adjustment' });
  }
});

// Get Unpaid Sales for Client
router.get('/unpaid-sales/:clientId', authenticate, authorize(['OWNER', 'STAFF', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const { clientId } = req.params;
  const salonId = req.user.salonId;

  try {
    const clientSales = await db.select({
      id: sales.id,
      total: sales.total,
      amountPaid: sales.amountPaid,
      createdAt: sales.createdAt
    })
    .from(sales)
    .innerJoin(ledgerEntries, and(eq(ledgerEntries.saleId, sales.id), eq(ledgerEntries.category, 'SALE')))
    .where(and(
       eq(ledgerEntries.clientId, clientId as string),
       eq(sales.status, 'ACTIVE'),
       sql`CAST(COALESCE(${sales.amountPaid}, '0') AS NUMERIC) < CAST(${sales.total} AS NUMERIC)`
    ))
    .orderBy(asc(sales.createdAt));

    res.json(clientSales);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching unpaid sales' });
  }
});

export default router;
