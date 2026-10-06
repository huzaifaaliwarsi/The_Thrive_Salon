import { Router } from 'express';
import { db } from '../db';
import { inventoryItems, vendors, inventoryTransactions } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, desc, sql, gte, lte } from 'drizzle-orm';

const router = Router();

// --- Vendors ---

router.post('/vendors', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { name, contactPerson, phone, email, address } = req.body;
  const salonId = req.user.salonId;
  try {
    const [newVendor] = await db.insert(vendors).values({ name, contactPerson, phone, email, address, salonId }).returning();
    res.status(201).json(newVendor);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error creating vendor' });
  }
});

router.get('/vendors', authenticate, authorize(['OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.salonId;
  if (!salonId) return res.status(403).json({ message: 'Unauthorized: No salon ID' });
  try {
    const allVendors = await db.query.vendors.findMany({
      where: eq(vendors.salonId, salonId as string),
      orderBy: [desc(vendors.createdAt)]
    });
    res.json(allVendors);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching vendors' });
  }
});

router.put('/vendors/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { name, contactPerson, phone, email, address } = req.body;
  const salonId = req.user.salonId;
  try {
    const [updated] = await db.update(vendors).set({ name, contactPerson, phone, email, address }).where(and(eq(vendors.id, id as string), eq(vendors.salonId, salonId as string))).returning();
    res.json(updated);
  } catch (error) {
    res.status(500).json({ message: 'Error updating vendor' });
  }
});

router.delete('/vendors/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.salonId;
  try {
    await db.delete(vendors).where(and(eq(vendors.id, id as string), eq(vendors.salonId, salonId as string)));
    res.json({ message: 'Vendor deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting vendor' });
  }
});

// --- Inventory Items ---

router.post('/items', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { name, sku, vendorId, unit, unitPrice, initialStock, expiryDate, lowStockThreshold, sellingPrice, canBeSold } = req.body;
  const salonId = req.user.salonId;
  try {
    const [newItem] = await db.insert(inventoryItems).values({
      name, sku, vendorId, unit, 
      unitPrice: unitPrice?.toString(), 
      sellingPrice: sellingPrice?.toString() || '0',
      canBeSold: canBeSold?.toString() || 'false',
      stockQuantity: initialStock?.toString() || '0', 
      expiryDate,
      lowStockThreshold: lowStockThreshold?.toString() || '5',
      salonId 
    }).returning();
    
    if (initialStock && initialStock > 0) {
        await db.insert(inventoryTransactions).values({
            itemId: newItem.id,
            salonId,
            type: 'IN',
            quantity: initialStock.toString(),
            notes: 'Initial Stock'
        });
    }

    res.status(201).json(newItem);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error creating inventory item' });
  }
});

router.get('/items', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.query.salonId as string) : req.user.salonId;
  if (!salonId) return res.status(403).json({ message: 'Unauthorized: No salon ID' });
  try {
    const items = await db.query.inventoryItems.findMany({
      where: eq(inventoryItems.salonId, salonId as string),
      with: { vendor: true },
      orderBy: [desc(inventoryItems.createdAt)]
    });
    res.json(items);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching items' });
  }
});

router.put('/items/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { name, sku, vendorId, unit, unitPrice, expiryDate, lowStockThreshold, sellingPrice, canBeSold } = req.body;
  const salonId = req.user.salonId;
  try {
    const [updated] = await db.update(inventoryItems).set({
      name, sku, vendorId, unit, 
      unitPrice: unitPrice?.toString(), 
      sellingPrice: sellingPrice?.toString(),
      canBeSold: canBeSold?.toString(),
      expiryDate,
      lowStockThreshold: lowStockThreshold?.toString()
    }).where(and(eq(inventoryItems.id, id as string), eq(inventoryItems.salonId, salonId as string))).returning();
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error updating inventory item' });
  }
});

router.delete('/items/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.salonId;
  try {
    const [deleted] = await db.delete(inventoryItems)
      .where(and(eq(inventoryItems.id, id as string), eq(inventoryItems.salonId, salonId as string)))
      .returning();
    
    if (!deleted) return res.status(404).json({ message: 'Inventory item not found' });
    res.json({ message: 'Inventory item deleted successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error deleting inventory item' });
  }
});

// --- Stock Transactions ---

router.post('/transactions', authenticate, authorize(['OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const { itemId, type, quantity, notes } = req.body;
  const salonId = req.user.salonId;
  try {
    // Record transaction
    const [transaction] = await db.insert(inventoryTransactions).values({
      itemId, salonId, type, quantity: quantity.toString(), notes
    }).returning();

    // Update stock quantity
    const multiplier = type === 'IN' ? 1 : -1;
    await db.update(inventoryItems)
      .set({ 
        stockQuantity: sql`${inventoryItems.stockQuantity} + ${sql.raw(quantity.toString())} * ${sql.raw(multiplier.toString())}`
      })
      .where(and(
        eq(inventoryItems.id, itemId as string),
        eq(inventoryItems.salonId, salonId as string)
      ));

    res.status(201).json(transaction);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error recording transaction' });
  }
});

router.get('/transactions', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.query.salonId as string) : req.user.salonId;
  if (!salonId) return res.status(403).json({ message: 'Unauthorized: No salon ID' });
  const { startDate, endDate } = req.query;

  try {
    let whereClause = eq(inventoryTransactions.salonId, salonId as string);
    if (startDate) {
      whereClause = and(whereClause, gte(inventoryTransactions.createdAt, new Date(startDate as string)))!;
    }
    if (endDate) {
      whereClause = and(whereClause, lte(inventoryTransactions.createdAt, new Date(endDate as string)))!;
    }

    const transactions = await db.select().from(inventoryTransactions)
      .where(whereClause)
      .orderBy(desc(inventoryTransactions.createdAt));
    res.json(transactions);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching all transactions' });
  }
});

router.get('/transactions/:itemId', authenticate, authorize(['OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const { itemId } = req.params;
  const salonId = req.user.salonId;
  if (!salonId) return res.status(403).json({ message: 'Unauthorized: No salon ID' });

  try {
    const transactions = await db.select().from(inventoryTransactions)
      .where(and(
        eq(inventoryTransactions.itemId, itemId as string),
        eq(inventoryTransactions.salonId, salonId as string)
      ))
      .orderBy(desc(inventoryTransactions.createdAt));
    res.json(transactions);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching transactions' });
  }
});

export default router;
