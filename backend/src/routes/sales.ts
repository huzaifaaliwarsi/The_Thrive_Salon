import { Router } from 'express';
import { db } from '../db';
import { sales, saleItems, staff, clients, inventoryItems, inventoryTransactions, ledgerEntries, salons } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, sql, desc, gte, lte, isNotNull, or, inArray, ne } from 'drizzle-orm';
import { normalizePhone } from '../utils/phone';

const uuidValidate = (uuid: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(uuid);

const router = Router();

// Create Sale (Staff and Owner)
router.post('/', authenticate, authorize(['SUPER_ADMIN', 'STAFF', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id: clientProvidedId, customerPhone: rawPhone, customerName, customerSource, subtotal, discount, total, paymentMethod, amountPaid, items, staffId: providedStaffId, customCommissionRate, taxRate, status, createdAt } = req.body;
  const customerPhone = normalizePhone(rawPhone);
  let staffId = (providedStaffId && providedStaffId !== '' && providedStaffId !== 'null') ? providedStaffId : null;
  const salonId = req.user.salonId;
  let commissionRate = customCommissionRate?.toString() || '0';

  const subtotalStr = subtotal?.toString() || '0';
  const discountStr = discount?.toString() || '0';
  const totalStr = total?.toString() || '0';
  const taxRateStr = taxRate?.toString() || '0';
  const paidAmountStr = amountPaid?.toString() || (paymentMethod === 'CREDIT' ? '0' : totalStr);

  const subtotalNum = parseFloat(subtotalStr);
  const discountNum = parseFloat(discountStr);
  const totalNum = parseFloat(totalStr);
  const taxRateNum = parseFloat(taxRateStr);
  const paidAmount = parseFloat(paidAmountStr);
  const debt = totalNum - paidAmount;

  try {
    // Resolve staffId if not provided, and only fetch current percentage if not custom
    const staffRecord = await db.query.staff.findFirst({
        where: and(
          eq(staff.salonId, salonId as string),
          staffId 
            ? eq(staff.id, staffId as string) 
            : eq(staff.userId, req.user.id as string)
        )
    });
    
    if (staffRecord) {
      staffId = staffRecord.id;
      if (!customCommissionRate) {
        commissionRate = staffRecord.commissionPercentage || '0';
      }
    }

    if (!staffId && req.user.role === 'STAFF') {
       return res.status(400).json({ message: 'Could not resolve staff profile' });
    }

    // Validate commission rate (Bug #21: Commission validation)
    const commissionRateNum = parseFloat(commissionRate);
    if (isNaN(commissionRateNum) || commissionRateNum < 0 || commissionRateNum > 100) {
      return res.status(400).json({ message: 'Commission rate must be between 0 and 100' });
    }

    const existingClient = customerPhone ? await db.query.clients.findFirst({
      where: and(eq(clients.phone, customerPhone), eq(clients.salonId, salonId as string))
    }) : null;

    const result = await db.transaction(async (tx) => {
      // Create Sale record with commission snapshot
      const [newSale] = await tx.insert(sales).values({
        id: (clientProvidedId && uuidValidate(clientProvidedId)) ? clientProvidedId : undefined,
        customerPhone,
        customerName,
        customerSource,
        subtotal: subtotalStr,
        discount: discountStr,
        total: totalStr,
        amountPaid: paidAmount.toString(),
        paymentMethod,
        staffId: staffId as string,
        salonId: salonId as string,
        commissionRate: commissionRate,
        taxRate: taxRateStr,
        taxAmount: ((subtotalNum - discountNum) * (taxRateNum / 100)).toString(),
        status: status || 'ACTIVE',
        createdAt: createdAt ? new Date(createdAt) : undefined,
      }).returning();

      // Create Sale Items
      if (items && items.length > 0) {
        for (const item of items) {
          const rawServiceId = item.serviceId ? String(item.serviceId) : null;
          const rawProductId = item.productId ? String(item.productId) : null;
          let cleanId = rawProductId || (rawServiceId ? rawServiceId.replace('inv_', '') : null);
          let isInv = !!(rawProductId || (rawServiceId && rawServiceId.startsWith('inv_')));

          if (!isInv && cleanId) {
            const invMatch = await tx.query.inventoryItems.findFirst({
              where: and(eq(inventoryItems.id, cleanId), eq(inventoryItems.salonId, salonId as string))
            });
            if (invMatch) isInv = true;
          }

          const itemStaffId = (item.staffId && item.staffId !== '' && item.staffId !== 'null') ? item.staffId : (staffId as string);

          let itemCommissionRateNum = commissionRateNum;
          if (itemStaffId !== staffId) {
             const itemStaffRecord = await tx.query.staff.findFirst({
               where: eq(staff.id, itemStaffId)
             });
             itemCommissionRateNum = parseFloat(itemStaffRecord?.commissionPercentage || '0');
          }

          const itemGross = parseFloat(item.price) * parseFloat(item.quantity);
          const itemProportion = subtotalNum > 0 ? (itemGross / subtotalNum) : 0;
          
          const itemDiscountAmount = discountNum * itemProportion;
          const itemNetPrice = itemGross - itemDiscountAmount;

          const itemTaxAmount = itemNetPrice * (taxRateNum / 100);
          const itemCommissionAmount = itemNetPrice * (itemCommissionRateNum / 100);
          
          await tx.insert(saleItems).values({
            saleId: newSale.id,
            serviceId: isInv ? null : cleanId,
            productId: isInv ? cleanId : null,
            staffId: itemStaffId,
            quantity: item.quantity.toString(),
            price: item.price.toString(),
            discountAmount: itemDiscountAmount.toString(),
            taxAmount: itemTaxAmount.toString(),
            commissionAmount: itemCommissionAmount.toString(),
            isInternal: item.isInternal || false,
          });

          // If it's an inventory product, deduct stock and record transaction (skip for draft)
          if (isInv && cleanId && status !== 'DRAFT') {
            // Strict Stock Check
            const currentItem = await tx.query.inventoryItems.findFirst({
              where: and(eq(inventoryItems.id, cleanId), eq(inventoryItems.salonId, salonId as string))
            });

            if (!currentItem || parseFloat(currentItem.stockQuantity || '0') < parseFloat(item.quantity.toString())) {
              throw new Error(`Insufficient stock for ${currentItem?.name || 'item'}. Available: ${currentItem?.stockQuantity || 0}`);
            }

            // Low-margin / Below unit cost warning
            const itemPrice = parseFloat(item.price?.toString() || '0');
            const unitCostPrice = parseFloat(currentItem.unitPrice || '0');
            if (unitCostPrice > 0 && itemPrice < unitCostPrice && req.body.allowBelowCost !== true && req.body.allowBelowCost !== 'true') {
              console.warn(`[Sales] Warning: Product ${currentItem.name} sold below unit cost (Price: ${itemPrice}, Unit Cost: ${unitCostPrice})`);
            }

            // Use sql template with explicit cast to handle numeric subtraction safely
            await tx.update(inventoryItems)
              .set({ 
                stockQuantity: sql`CAST(${inventoryItems.stockQuantity} AS NUMERIC) - CAST(${item.quantity.toString()} AS NUMERIC)` 
              })
              .where(and(
                eq(inventoryItems.id, cleanId),
                eq(inventoryItems.salonId, salonId as string)
              ));

            await tx.insert(inventoryTransactions).values({
              itemId: cleanId,
              salonId: salonId as string,
              type: item.isInternal ? 'INTERNAL_USE' : 'OUT',
              quantity: item.quantity.toString(),
              notes: `Sale #${newSale.id.substring(0, 8)}`,
              date: newSale.createdAt,
              createdAt: newSale.createdAt,
            });
          }
        }
      }

      // Handle Client logic (save if name given with number)
      let targetClientId: string | null = null;
      let targetClientName = customerName || 'Walk-in Customer';

      if (status !== 'DRAFT') {
        if (customerPhone) {
          if (existingClient) {
            targetClientId = existingClient.id;
            targetClientName = (existingClient.name === 'Unknown' || !existingClient.name) && customerName ? customerName : existingClient.name;

            // Update last visit and total spent
            const updateData: any = {
              lastVisit: new Date(),
              totalSpent: sql`${clients.totalSpent} + ${total.toString()}`,
              name: targetClientName
            };

            if (customerSource) {
              updateData.source = customerSource;
            }

            updateData.balance = sql`${clients.balance} + ${debt.toString()}`;

            await tx.update(clients).set(updateData).where(eq(clients.id, existingClient.id));
          } else if (customerName) {
            // Create new client if name is provided
            const [newClient] = await tx.insert(clients).values({
              salonId: salonId as string,
              name: customerName,
              phone: customerPhone,
              totalSpent: total.toString(),
              balance: debt.toString(),
              lastVisit: new Date(),
              source: customerSource || 'WALK_IN',
            }).returning();

            targetClientId = newClient.id;
            targetClientName = newClient.name;
          }
        }

        // Record Double-Entry in Ledger
        // Entry 1: Total Sale Bill
        await tx.insert(ledgerEntries).values({
          salonId: salonId as string,
          clientId: targetClientId,
          type: 'CREDIT',
          amount: total.toString(),
          category: 'SALE',
          notes: `Sale Bill Total - Sale #${newSale.id.substring(0, 8)}`,
          personName: targetClientName,
          saleId: newSale.id,
          date: newSale.createdAt,
        });

        // Entry 2: Immediate cash/online payment received at sale
        if (paidAmount > 0) {
          const methodUpper = (paymentMethod || 'CASH').toUpperCase();
          let cashPaid = 0;
          let onlinePaid = 0;

          if (req.body.cashAmount !== undefined || req.body.onlineAmount !== undefined) {
            cashPaid = parseFloat(req.body.cashAmount?.toString() || '0');
            onlinePaid = parseFloat(req.body.onlineAmount?.toString() || '0');
          } else if (methodUpper === 'SPLIT') {
            cashPaid = Math.round((paidAmount / 2) * 100) / 100;
            onlinePaid = Math.round((paidAmount - cashPaid) * 100) / 100;
          } else if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL'].includes(methodUpper)) {
            onlinePaid = paidAmount;
          } else {
            cashPaid = paidAmount;
          }

          if (cashPaid > 0) {
            const cashNotes = JSON.stringify({
              paymentMethod: 'CASH',
              userNotes: `Amount Paid at Sale (Cash) - Sale #${newSale.id.substring(0, 8)}`
            });

            await tx.insert(ledgerEntries).values({
              salonId: salonId as string,
              clientId: targetClientId,
              type: 'DEBIT',
              amount: cashPaid.toString(),
              category: 'PAYMENT',
              notes: cashNotes,
              personName: targetClientName,
              saleId: newSale.id,
              date: newSale.createdAt,
            });

            await tx.update(salons)
              .set({ cashBalance: sql`${salons.cashBalance} + ${cashPaid.toString()}` })
              .where(eq(salons.id, salonId as string));
          }

          if (onlinePaid > 0) {
            const onlineMethod = methodUpper === 'SPLIT' || methodUpper === 'CASH' ? 'ONLINE' : methodUpper;
            const onlineNotes = JSON.stringify({
              paymentMethod: onlineMethod,
              userNotes: `Amount Paid at Sale (${onlineMethod}) - Sale #${newSale.id.substring(0, 8)}`
            });

            await tx.insert(ledgerEntries).values({
              salonId: salonId as string,
              clientId: targetClientId,
              type: 'DEBIT',
              amount: onlinePaid.toString(),
              category: 'PAYMENT',
              notes: onlineNotes,
              personName: targetClientName,
              saleId: newSale.id,
              date: newSale.createdAt,
            });
          }
        }
      }

      return newSale;
    });

    res.status(201).json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error creating sale' });
  }
});

// List Sales (Super Admin, Owner, and Staff)
router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  let salonId = req.user.salonId;
  if (req.user.role === 'SUPER_ADMIN') {
    salonId = req.query.salonId as string;
  }
  const statusQuery = req.query.status as string;
  const { startDate, endDate } = req.query;
  
  try {
    let statusCondition;
    if (statusQuery) {
      statusCondition = eq(sales.status, statusQuery);
    } else {
      statusCondition = sql`${sales.status} != 'DRAFT'`;
    }

    let whereClause = and(eq(sales.salonId, salonId as string), statusCondition)!;

    if (startDate || endDate) {
      const offsetMinutes = parseInt(req.query.timezoneOffset as string) || 0;
      const offsetMs = (offsetMinutes > 0 ? -offsetMinutes : Math.abs(offsetMinutes)) * 60 * 1000;

      let startD: Date;
      let endD: Date;

      const startParam = (startDate as string) || '';
      const endParam = (endDate as string) || '';

      if (startParam.length === 10 && endParam.length === 10) {
        const [sy, sm, sd] = startParam.split('-').map(Number);
        const [ey, em, ed] = endParam.split('-').map(Number);
        const baseStartUtc = Date.UTC(sy, sm - 1, sd, 0, 0, 0, 0);
        const baseEndUtc = Date.UTC(ey, em - 1, ed, 23, 59, 59, 999);
        startD = offsetMinutes !== 0 ? new Date(baseStartUtc + offsetMs) : new Date(baseStartUtc);
        endD = offsetMinutes !== 0 ? new Date(baseEndUtc + offsetMs) : new Date(baseEndUtc);
      } else {
        startD = startDate ? new Date(startParam) : new Date('2000-01-01');
        endD = endDate ? new Date(endParam) : new Date('2100-01-01');
        if (endParam.length === 10) endD.setHours(23, 59, 59, 999);
      }

      // Find sale IDs that had payments recorded in this date range
      const paymentSaleIds = await db.execute(sql`
        SELECT DISTINCT sale_id FROM ledger_entries 
        WHERE salon_id = ${salonId}::uuid AND category = 'PAYMENT' AND sale_id IS NOT NULL
          AND date >= ${startD.toISOString()}::timestamptz AND date <= ${endD.toISOString()}::timestamptz
      `);
      const matchedIds = (paymentSaleIds.rows as any[]).map((r: any) => r.sale_id).filter(Boolean);

      const dateCond = and(
        startDate ? gte(sales.createdAt, startD) : sql`true`,
        endDate ? lte(sales.createdAt, endD) : sql`true`
      );

      if (matchedIds.length > 0) {
        const inList = sql`${sales.id} IN (${sql.raw(matchedIds.map((id: string) => `'${id}'`).join(','))})`;
        whereClause = and(whereClause, or(dateCond, inList))!;
      } else {
        whereClause = and(whereClause, dateCond)!;
      }
    }


    if (req.user.role === 'STAFF') {
      const staffRecord = await db.query.staff.findFirst({
        where: eq(staff.userId, req.user.id as string)
      });
      if (staffRecord) {
        const staffSaleItemIds = await db.execute(sql`
          SELECT DISTINCT si.sale_id FROM sale_items si WHERE si.staff_id = ${staffRecord.id}::uuid
        `);
        const saleIdsFromItems = (staffSaleItemIds.rows as any[]).map((r: any) => r.sale_id).filter(Boolean);
        if (saleIdsFromItems.length > 0) {
          const inList = sql`${sales.id} IN (${sql.raw(saleIdsFromItems.map((id: string) => `'${id}'`).join(','))})`;
          whereClause = and(whereClause, or(eq(sales.staffId, staffRecord.id), inList))!;
        } else {
          whereClause = and(whereClause, eq(sales.staffId, staffRecord.id))!;
        }
      }
    }

    const allSales = await db.query.sales.findMany({
      where: whereClause,
      with: {
        saleItems: {
          with: {
            service: true,
            product: true,
            staff: true,
          },
        },
        staff: true,
        salon: true,
      },
      orderBy: (sales, { desc }) => [desc(sales.createdAt)],
    });

    // Fetch ledger payment entries for all returned sales
    const saleIds = allSales.map(s => s.id);
    let paymentsMap: Record<string, Array<{ amount: number; date: string; paymentMethod?: string; notes?: string }>> = {};


    if (saleIds.length > 0) {
      const paymentEntries = await db.query.ledgerEntries.findMany({
        where: and(
          eq(ledgerEntries.category, 'PAYMENT'),
          inArray(ledgerEntries.saleId, saleIds)
        )
      });

      for (const entry of paymentEntries) {
        if (!entry.saleId) continue;
        if (!paymentsMap[entry.saleId]) paymentsMap[entry.saleId] = [];

        let pMethod = 'CASH';
        if (entry.notes) {
          try {
            const trimmed = entry.notes.trim();
            if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
              const parsed = JSON.parse(trimmed);
              if (parsed.paymentMethod) pMethod = String(parsed.paymentMethod).toUpperCase();
            }
          } catch (_) {}
          if (pMethod === 'CASH' && (entry.notes.toUpperCase().includes('ONLINE') || entry.notes.toUpperCase().includes('CARD') || entry.notes.toUpperCase().includes('BANK') || entry.notes.toUpperCase().includes('UPI'))) {
            pMethod = 'ONLINE';
          }
        }

        paymentsMap[entry.saleId].push({
          amount: parseFloat(entry.amount || '0'),
          date: entry.date ? new Date(entry.date).toISOString() : new Date().toISOString(),
          paymentMethod: pMethod,
          notes: entry.notes || '',
        });
      }

    }

    const salesWithPaymentStatus = allSales.map(s => {
      const tot = parseFloat(s.total || '0');
      const paid = parseFloat(s.amountPaid || '0');
      const taxAmt = parseFloat(s.taxAmount || '0');
      let pStatus = 'Paid';
      let due = Math.max(0, tot - paid);

      if (s.status === 'VOID') {
        pStatus = 'Voided';
        due = 0;
      } else if (paid <= 0) {
        pStatus = 'Unpaid';
      } else if (paid < tot - 0.01) {
        pStatus = 'Partially Paid';
      } else {
        due = 0;
      }

      const collectedTax = s.status === 'VOID' ? 0 : (tot > 0 ? (taxAmt * Math.min(1, paid / tot)) : 0);

      let payments = paymentsMap[s.id] || [];
      if (payments.length === 0 && paid > 0) {
        payments = [{
          amount: paid,
          date: s.createdAt ? new Date(s.createdAt).toISOString() : new Date().toISOString()
        }];
      }

      return {
        ...s,
        payments,
        paymentStatus: pStatus,
        due: Number(due.toFixed(2)),
        remainingAmount: Number(due.toFixed(2)),
        collectedTax: Number(collectedTax.toFixed(2))
      };
    });
    res.json(salesWithPaymentStatus);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching sales' });
  }
});

// Void Sale (Owner only) - Full Reversal Logic
router.patch('/:id/void', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { reason } = req.body;
  const salonId = req.user.salonId;

  if (!reason) return res.status(400).json({ message: 'Void reason is required' });

  try {
    const result = await db.transaction(async (tx) => {
      // 1. Fetch the sale with items
      const saleToVoid = await tx.query.sales.findFirst({
        where: and(eq(sales.id, id as string), eq(sales.salonId, salonId as string)),
        with: { saleItems: true }
      });

      if (!saleToVoid) throw new Error('Sale not found');
      if (saleToVoid.status === 'VOID') throw new Error('Sale is already voided');

      // 2. Reverse Inventory for each item
      for (const item of saleToVoid.saleItems) {
        let prodId = item.productId;
        if (!prodId && item.serviceId) {
          const sId = item.serviceId.toString();
          const cleanId = sId.startsWith('inv_') ? sId.replace('inv_', '') : sId;
          const invItem = await tx.query.inventoryItems.findFirst({
            where: and(eq(inventoryItems.id, cleanId), eq(inventoryItems.salonId, salonId as string))
          });
          if (invItem) prodId = invItem.id;
        }

        if (prodId) {
          await tx.update(inventoryItems)
            .set({ stockQuantity: sql`CAST(${inventoryItems.stockQuantity} AS NUMERIC) + CAST(${item.quantity} AS NUMERIC)` })
            .where(and(eq(inventoryItems.id, prodId), eq(inventoryItems.salonId, salonId as string)));

          await tx.insert(inventoryTransactions).values({
            itemId: prodId,
            salonId: salonId as string,
            type: 'IN',
            quantity: String(item.quantity),
            notes: `VOID Reversal - Sale #${saleToVoid.id.substring(0, 8)}`
          });
        }
      }

      // 3. Handle Client Balance & Ledger Reversal
      let targetClientId: string | null = null;
      let targetClientName = saleToVoid.customerName || 'Walk-in Customer';

      // Look up client from existing sale ledger entries first, then by phone
      const saleLedgerEntry = await tx.query.ledgerEntries.findFirst({
        where: and(eq(ledgerEntries.saleId, saleToVoid.id), isNotNull(ledgerEntries.clientId))
      });

      let clientRecord = null;
      if (saleLedgerEntry && saleLedgerEntry.clientId) {
        clientRecord = await tx.query.clients.findFirst({
          where: and(eq(clients.id, saleLedgerEntry.clientId), eq(clients.salonId, salonId as string))
        });
      }

      if (!clientRecord && saleToVoid.customerPhone) {
        const normPhone = normalizePhone(saleToVoid.customerPhone);
        if (normPhone) {
          clientRecord = await tx.query.clients.findFirst({
            where: and(eq(clients.phone, normPhone), eq(clients.salonId, salonId as string))
          });
        }
      }

      if (!clientRecord && saleToVoid.customerName && saleToVoid.customerName !== 'Walk-in Customer') {
        clientRecord = await tx.query.clients.findFirst({
          where: and(eq(clients.name, saleToVoid.customerName), eq(clients.salonId, salonId as string))
        });
      }

      if (clientRecord) {
        targetClientId = clientRecord.id;
        targetClientName = clientRecord.name;

        // Calculate actual payments recorded in ledger
        const paymentEntries = await tx.query.ledgerEntries.findMany({
          where: and(
            eq(ledgerEntries.saleId, saleToVoid.id),
            eq(ledgerEntries.category, 'PAYMENT'),
            eq(ledgerEntries.type, 'DEBIT')
          )
        });
        const ledgerPaid = paymentEntries.reduce((sum, e) => sum + Number(e.amount || 0), 0);
        const actualPaid = Math.max(Number(saleToVoid.amountPaid || 0), ledgerPaid);
        const debt = Math.max(0, Number(saleToVoid.total || 0) - actualPaid);

        // Revert outstanding balance of the sale
        await tx.update(clients)
          .set({ balance: sql`ROUND(GREATEST(-100000, CAST(${clients.balance} AS NUMERIC) - ${debt.toString()}::numeric), 2)` })
          .where(eq(clients.id, clientRecord.id));

        // Strictly reconcile client balance against remaining active unpaid sales
        const activeSalesRes = await tx.select({
          totalDebt: sql<number>`sum(GREATEST(0, CAST(${sales.total} AS NUMERIC) - CAST(COALESCE(${sales.amountPaid}, '0') AS NUMERIC)))`
        }).from(sales).where(and(
          eq(sales.salonId, salonId as string),
          eq(sales.status, 'ACTIVE'),
          ne(sales.id, saleToVoid.id),
          or(
            clientRecord.phone ? eq(sales.customerPhone, clientRecord.phone) : sql`false`,
            eq(sales.customerName, clientRecord.name)
          )
        ));

        const remainingDebt = Number(activeSalesRes[0]?.totalDebt || 0);
        if (remainingDebt <= 0.01) {
          await tx.update(clients).set({ balance: '0' }).where(eq(clients.id, clientRecord.id));
        } else {
          await tx.update(clients).set({ balance: remainingDebt.toFixed(2) }).where(eq(clients.id, clientRecord.id));
        }
      }

      // Reverse double-entry in general/client ledger
      // Entry 1 Reversal: Revert total sale bill (DEBIT)
      await tx.insert(ledgerEntries).values({
        salonId: salonId as string,
        clientId: targetClientId,
        type: 'DEBIT',
        amount: saleToVoid.total.toString(),
        category: 'VOID_REVERSAL',
        notes: `VOID Reversal (Total Bill) - Sale #${saleToVoid.id.substring(0, 8)}`,
        personName: targetClientName,
        saleId: saleToVoid.id,
      });

      // Entry 2 Reversal: Revert payments made (CREDIT) by looking up all actual payment ledger entries for this sale
      const existingPaymentEntries = await tx.query.ledgerEntries.findMany({
        where: and(
          eq(ledgerEntries.saleId, saleToVoid.id),
          eq(ledgerEntries.category, 'PAYMENT'),
          eq(ledgerEntries.type, 'DEBIT')
        )
      });

      if (existingPaymentEntries && existingPaymentEntries.length > 0) {
        for (const pEntry of existingPaymentEntries) {
          const amtNum = parseFloat(pEntry.amount || '0');
          if (amtNum <= 0) continue;

          let pMethod = (saleToVoid.paymentMethod || 'CASH').toUpperCase();
          try {
            if (pEntry.notes && pEntry.notes.trim().startsWith('{')) {
              const parsed = JSON.parse(pEntry.notes);
              if (parsed.paymentMethod) pMethod = parsed.paymentMethod.toUpperCase();
            }
          } catch (_) {}

          const isOnline = pMethod === 'ONLINE' || pMethod === 'CARD' || pMethod === 'BANK_TRANSFER' || pMethod === 'UPI' || pMethod === 'DIGITAL';

          const structuredNotes = JSON.stringify({
            paymentMethod: pMethod,
            userNotes: `VOID Reversal (${pMethod}) - Sale #${saleToVoid.id.substring(0, 8)}`
          });

          await tx.insert(ledgerEntries).values({
            salonId: salonId as string,
            clientId: targetClientId,
            type: 'CREDIT',
            amount: amtNum.toString(),
            category: 'VOID_REVERSAL',
            notes: structuredNotes,
            personName: targetClientName,
            saleId: saleToVoid.id,
          });

          // Revert Salon Cash Balance (only for cash payments)
          if (!isOnline) {
            await tx.update(salons)
              .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric - ${amtNum.toString()}::numeric)` })
              .where(eq(salons.id, salonId as string));
          }
        }
      } else if (parseFloat(saleToVoid.amountPaid || '0') > 0) {
        // Fallback for sales without explicit payment ledger entries
        const pMethod = (saleToVoid.paymentMethod || 'CASH').toUpperCase();
        const isOnline = pMethod === 'ONLINE' || pMethod === 'CARD' || pMethod === 'BANK_TRANSFER' || pMethod === 'UPI' || pMethod === 'DIGITAL';

        const structuredNotes = JSON.stringify({
          paymentMethod: pMethod,
          userNotes: `VOID Reversal (${pMethod}) - Sale #${saleToVoid.id.substring(0, 8)}`
        });

        await tx.insert(ledgerEntries).values({
          salonId: salonId as string,
          clientId: targetClientId,
          type: 'CREDIT',
          amount: saleToVoid.amountPaid!.toString(),
          category: 'VOID_REVERSAL',
          notes: structuredNotes,
          personName: targetClientName,
          saleId: saleToVoid.id,
        });

        if (!isOnline) {
          await tx.update(salons)
            .set({ cashBalance: sql`GREATEST(0, ${salons.cashBalance}::numeric - ${saleToVoid.amountPaid!.toString()}::numeric)` })
            .where(eq(salons.id, salonId as string));
        }
      }

      // 5. Update Sale Status
      const [updated] = await tx.update(sales)
        .set({ status: 'VOID', voidReason: reason })
        .where(eq(sales.id, id as string))
        .returning();

      return updated;
    });

    res.json(result);
  } catch (error: any) {
    console.error(error);
    res.status(400).json({ message: error.message || 'Error voiding sale' });
  }
});

// Update / Finalize Sale (Staff and Owner)
router.put('/:id', authenticate, authorize(['SUPER_ADMIN', 'STAFF', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const id = req.params.id as string;
  const { customerPhone: rawPhone, customerName, customerSource, subtotal, discount, total, paymentMethod, amountPaid, items, staffId: providedStaffId, customCommissionRate, taxRate, status, createdAt } = req.body;
  const customerPhone = normalizePhone(rawPhone);
  let staffId = (providedStaffId && providedStaffId !== '' && providedStaffId !== 'null') ? providedStaffId : null;
  const salonId = req.user.salonId;

  try {
    // 1. Fetch the sale to see if it exists and is a DRAFT
    const existingSale = await db.query.sales.findFirst({
      where: and(eq(sales.id, id as string), eq(sales.salonId, salonId as string)),
    });

    if (!existingSale) {
      return res.status(404).json({ message: 'Sale not found' });
    }

    if (existingSale.status !== 'DRAFT') {
      return res.status(400).json({ message: 'Only draft/quotation sales can be updated' });
    }

    // Resolve commission rate
    let commissionRate = customCommissionRate?.toString();
    const staffRecord = await db.query.staff.findFirst({
        where: and(
          eq(staff.salonId, salonId as string),
          staffId 
            ? eq(staff.id, staffId as string) 
            : eq(staff.userId, req.user.id as string)
        )
    });
    
    if (staffRecord) {
      staffId = staffRecord.id;
      if (!customCommissionRate) {
        commissionRate = staffRecord.commissionPercentage || '0';
      }
    }
    if (!commissionRate) commissionRate = '0';

    const commissionRateNum = parseFloat(commissionRate);
    if (isNaN(commissionRateNum) || commissionRateNum < 0 || commissionRateNum > 100) {
      return res.status(400).json({ message: 'Commission rate must be between 0 and 100' });
    }

    const subtotalStr = subtotal?.toString() || '0';
    const discountStr = discount?.toString() || '0';
    const totalStr = total?.toString() || '0';
    const taxRateStr = taxRate?.toString() || '0';
    const paidAmountStr = amountPaid?.toString() || (paymentMethod === 'CREDIT' ? '0' : totalStr);

    const subtotalNum = parseFloat(subtotalStr);
    const discountNum = parseFloat(discountStr);
    const totalNum = parseFloat(totalStr);
    const taxRateNum = parseFloat(taxRateStr);
    const paidAmount = parseFloat(paidAmountStr);
    const debt = totalNum - paidAmount;

    const existingClient = customerPhone ? await db.query.clients.findFirst({
      where: and(eq(clients.phone, customerPhone), eq(clients.salonId, salonId as string))
    }) : null;

    const result = await db.transaction(async (tx) => {
      // Update Sale record
      await tx.update(sales)
        .set({
          customerPhone,
          customerName,
          customerSource,
          subtotal: subtotalStr,
          discount: discountStr,
          total: totalStr,
          amountPaid: paidAmount.toString(),
          paymentMethod,
          staffId: staffId as string,
          commissionRate: commissionRate,
          taxRate: taxRateStr,
          taxAmount: ((subtotalNum - discountNum) * (taxRateNum / 100)).toString(),
          status: status || 'DRAFT',
          ...(createdAt ? { createdAt: new Date(createdAt) } : {}),
        })
        .where(eq(sales.id, id as string));

      // Remove existing items
      await tx.delete(saleItems).where(eq(saleItems.saleId, id as string));

      // Re-insert updated items
      if (items && items.length > 0) {
        for (const item of items) {
          const rawServiceId = item.serviceId ? String(item.serviceId) : null;
          const rawProductId = item.productId ? String(item.productId) : null;
          let cleanId = rawProductId || (rawServiceId ? rawServiceId.replace('inv_', '') : null);
          let isInv = !!(rawProductId || (rawServiceId && rawServiceId.startsWith('inv_')));

          if (!isInv && cleanId) {
            const invMatch = await tx.query.inventoryItems.findFirst({
              where: and(eq(inventoryItems.id, cleanId), eq(inventoryItems.salonId, salonId as string))
            });
            if (invMatch) isInv = true;
          }

          const itemStaffId = (item.staffId && item.staffId !== '' && item.staffId !== 'null') ? item.staffId : (staffId as string);

          let itemCommissionRateNum = commissionRateNum;
          if (itemStaffId !== staffId) {
             const itemStaffRecord = await tx.query.staff.findFirst({
               where: eq(staff.id, itemStaffId)
             });
             itemCommissionRateNum = parseFloat(itemStaffRecord?.commissionPercentage || '0');
          }

          const itemGross = parseFloat(item.price) * parseFloat(item.quantity);
          const itemProportion = subtotalNum > 0 ? (itemGross / subtotalNum) : 0;
          
          const itemDiscountAmount = discountNum * itemProportion;
          const itemNetPrice = itemGross - itemDiscountAmount;

          const itemTaxAmount = itemNetPrice * (taxRateNum / 100);
          const itemCommissionAmount = itemNetPrice * (itemCommissionRateNum / 100);
          
          await tx.insert(saleItems).values({
            saleId: id as string,
            serviceId: isInv ? null : cleanId,
            productId: isInv ? cleanId : null,
            staffId: itemStaffId,
            quantity: item.quantity.toString(),
            price: item.price.toString(),
            discountAmount: itemDiscountAmount.toString(),
            taxAmount: itemTaxAmount.toString(),
            commissionAmount: itemCommissionAmount.toString(),
            isInternal: item.isInternal || false,
          });

          // Stock deduction (only if finalized to ACTIVE)
          if (isInv && cleanId && status === 'ACTIVE') {
            const currentItem = await tx.query.inventoryItems.findFirst({
              where: and(eq(inventoryItems.id, cleanId), eq(inventoryItems.salonId, salonId as string))
            });

            if (!currentItem || parseFloat(currentItem.stockQuantity || '0') < parseFloat(item.quantity.toString())) {
              throw new Error(`Insufficient stock for ${currentItem?.name || 'item'}. Available: ${currentItem?.stockQuantity || 0}`);
            }

            await tx.update(inventoryItems)
              .set({ 
                stockQuantity: sql`CAST(${inventoryItems.stockQuantity} AS NUMERIC) - CAST(${item.quantity.toString()} AS NUMERIC)` 
              })
              .where(and(
                eq(inventoryItems.id, cleanId),
                eq(inventoryItems.salonId, salonId as string)
              ));

            await tx.insert(inventoryTransactions).values({
              itemId: cleanId,
              salonId: salonId as string,
              type: 'OUT',
              quantity: item.quantity.toString(),
              notes: `Sale Finalized #${(id as string).substring(0, 8)}`
            });
          }
        }
      }

      // Ledger and client finalization updates (only if finalized to ACTIVE)
      if (status === 'ACTIVE') {
        let targetClientId: string | null = null;
        let targetClientName = customerName || 'Walk-in Customer';

        if (customerPhone) {
          if (existingClient) {
            targetClientId = existingClient.id;
            targetClientName = (existingClient.name === 'Unknown' || !existingClient.name) && customerName ? customerName : existingClient.name;

            const updateData: any = {
              lastVisit: new Date(),
              totalSpent: sql`${clients.totalSpent} + ${total.toString()}`,
              name: targetClientName
            };

            if (customerSource) {
              updateData.source = customerSource;
            }

            updateData.balance = sql`${clients.balance} + ${debt.toString()}`;

            await tx.update(clients).set(updateData).where(eq(clients.id, existingClient.id));
          } else if (customerName) {
            const [newClient] = await tx.insert(clients).values({
              salonId: salonId as string,
              name: customerName,
              phone: customerPhone,
              totalSpent: total.toString(),
              balance: debt.toString(),
              lastVisit: new Date(),
              source: customerSource || 'WALK_IN',
            }).returning();

            targetClientId = newClient.id;
            targetClientName = newClient.name;
          }
        }

        const saleEntryDate = createdAt ? new Date(createdAt) : new Date();

        // Ledger Entry 1: Total Sale Bill
        await tx.insert(ledgerEntries).values({
          salonId: salonId as string,
          clientId: targetClientId,
          type: 'CREDIT',
          amount: total.toString(),
          category: 'SALE',
          notes: `Sale Bill Total - Sale #${id.substring(0, 8)}`,
          personName: targetClientName,
          saleId: id as string,
          date: saleEntryDate,
        });

        // Ledger Entry 2: Immediate cash/online payment received at sale
        if (paidAmount > 0) {
          const methodUpper = (paymentMethod || 'CASH').toUpperCase();
          let cashPaid = 0;
          let onlinePaid = 0;

          if (req.body.cashAmount !== undefined || req.body.onlineAmount !== undefined) {
            cashPaid = parseFloat(req.body.cashAmount?.toString() || '0');
            onlinePaid = parseFloat(req.body.onlineAmount?.toString() || '0');
          } else if (methodUpper === 'SPLIT') {
            cashPaid = Math.round((paidAmount / 2) * 100) / 100;
            onlinePaid = Math.round((paidAmount - cashPaid) * 100) / 100;
          } else if (['ONLINE', 'CARD', 'BANK_TRANSFER', 'UPI', 'DIGITAL'].includes(methodUpper)) {
            onlinePaid = paidAmount;
          } else {
            cashPaid = paidAmount;
          }

          if (cashPaid > 0) {
            const cashNotes = JSON.stringify({
              paymentMethod: 'CASH',
              userNotes: `Amount Paid at Sale (Cash) - Sale #${id.substring(0, 8)}`
            });

            await tx.insert(ledgerEntries).values({
              salonId: salonId as string,
              clientId: targetClientId,
              type: 'DEBIT',
              amount: cashPaid.toString(),
              category: 'PAYMENT',
              notes: cashNotes,
              personName: targetClientName,
              saleId: id as string,
              date: saleEntryDate,
            });

            await tx.update(salons)
              .set({ cashBalance: sql`${salons.cashBalance} + ${cashPaid.toString()}` })
              .where(eq(salons.id, salonId as string));
          }

          if (onlinePaid > 0) {
            const onlineMethod = methodUpper === 'SPLIT' || methodUpper === 'CASH' ? 'ONLINE' : methodUpper;
            const onlineNotes = JSON.stringify({
              paymentMethod: onlineMethod,
              userNotes: `Amount Paid at Sale (${onlineMethod}) - Sale #${id.substring(0, 8)}`
            });

            await tx.insert(ledgerEntries).values({
              salonId: salonId as string,
              clientId: targetClientId,
              type: 'DEBIT',
              amount: onlinePaid.toString(),
              category: 'PAYMENT',
              notes: onlineNotes,
              personName: targetClientName,
              saleId: id as string,
              date: saleEntryDate,
            });
          }
        }
      }

      // Return the updated sale record
      const updatedSale = await tx.query.sales.findFirst({
        where: eq(sales.id, id as string),
        with: {
          saleItems: true,
          staff: true,
        }
      });
      return updatedSale;
    });

    res.json(result);
  } catch (error: any) {
    console.error(error);
    res.status(500).json({ message: error.message || 'Error updating sale' });
  }
});

// Delete Draft Sale (Staff and Owner)
router.delete('/:id', authenticate, authorize(['SUPER_ADMIN', 'STAFF', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const id = req.params.id as string;
  const salonId = req.user.salonId;

  try {
    const existingSale = await db.query.sales.findFirst({
      where: and(eq(sales.id, id as string), eq(sales.salonId, salonId as string)),
    });

    if (!existingSale) {
      return res.status(404).json({ message: 'Sale not found' });
    }

    if (existingSale.status !== 'DRAFT') {
      return res.status(400).json({ message: 'Only draft sales can be deleted' });
    }

    await db.transaction(async (tx) => {
      // Delete sale items
      await tx.delete(saleItems).where(eq(saleItems.saleId, id as string));
      // Delete sale
      await tx.delete(sales).where(eq(sales.id, id as string));
    });

    res.json({ message: 'Draft deleted successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error deleting draft sale' });
  }
});
// Public Invoice Endpoint (No auth required)
router.get('/public/:id', async (req, res) => {
  const id = req.params.id as string;
  const verifyHash = req.query.verify as string;

  if (!uuidValidate(id)) {
    return res.status(404).json({ message: 'Invoice not found' });
  }

  try {
    const saleRecord = await db.query.sales.findFirst({
      where: eq(sales.id, id),
      with: {
        saleItems: true,
        staff: true,
      }
    });

    if (!saleRecord) {
      return res.status(404).json({ message: 'Invoice not found' });
    }

    const salonRecord = await db.query.salons.findFirst({
      where: eq(salons.id, saleRecord.salonId as string)
    });

    if (!salonRecord) {
      return res.status(404).json({ message: 'Salon not found' });
    }

    res.json({
      sale: saleRecord,
      salon: salonRecord
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching public invoice' });
  }
});

export default router;
