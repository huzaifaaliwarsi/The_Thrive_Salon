import { Router } from 'express';
import { db } from '../db';
import { clients } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, desc, sql } from 'drizzle-orm';
import { normalizePhone } from '../utils/phone';

const router = Router();

// Create Client
router.post('/', authenticate, authorize(['OWNER', 'STAFF', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const { name, phone, email, notes, source, salonId: providedSalonId } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? providedSalonId : req.user.salonId;

  if (!salonId) return res.status(400).json({ message: 'Salon ID is required' });

  try {
    const [newClient] = await db.insert(clients).values({
      name,
      phone: normalizePhone(phone),
      email,
      notes,
      source: source || 'WALK_IN',
      salonId,
    }).returning();

    res.status(201).json(newClient);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error creating client' });
  }
});

// Bulk Create Clients
router.post('/bulk', authenticate, authorize(['OWNER', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const { clients: clientsData } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? req.body.salonId : req.user.salonId;

  if (!salonId) return res.status(400).json({ message: 'Salon ID is required' });
  if (!Array.isArray(clientsData)) return res.status(400).json({ message: 'Clients data must be an array' });

  try {
    const values = clientsData.map(c => ({
      name: c.name,
      phone: normalizePhone(c.phone),
      email: c.email,
      notes: c.notes,
      source: c.source || 'WALK_IN',
      salonId,
    }));

    const result = await db.insert(clients).values(values).returning();
    res.status(201).json({ message: `Successfully imported ${result.length} clients`, count: result.length });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error during bulk import' });
  }
});

// List Clients
router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.query.salonId as string) : req.user.salonId;
  try {
    const allClients = await db.query.clients.findMany({
      where: eq(clients.salonId, salonId as string),
      orderBy: [desc(clients.createdAt)]
    });

    const activeDebtRes = await db.execute(sql`
      SELECT 
        customer_phone,
        customer_name,
        sum(GREATEST(0, CAST(total AS NUMERIC) - CAST(COALESCE(amount_paid, '0') AS NUMERIC))) as active_debt
      FROM sales
      WHERE salon_id = ${salonId}::uuid AND status = 'ACTIVE'
      GROUP BY customer_phone, customer_name
    `);

    const debtMap: Record<string, number> = {};
    (activeDebtRes.rows as any[]).forEach(r => {
      const debt = Number(r.active_debt || 0);
      if (r.customer_phone) debtMap[r.customer_phone] = debt;
      if (r.customer_name) debtMap[r.customer_name] = debt;
    });

    const reconciledClients = allClients.map(c => {
      let trueDebt = 0;
      if (c.phone && debtMap[c.phone] !== undefined) {
        trueDebt = debtMap[c.phone];
      } else if (c.name && debtMap[c.name] !== undefined) {
        trueDebt = debtMap[c.name];
      }
      return {
        ...c,
        balance: trueDebt.toFixed(2)
      };
    });

    res.json(reconciledClients);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching clients' });
  }
});

// Update Client
router.put('/:id', authenticate, authorize(['OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { name, phone, email, notes, source } = req.body;
  const salonId = req.user.salonId;

  try {
    const [updatedClient] = await db.update(clients)
      .set({ name, phone: normalizePhone(phone), email, notes, source })
      .where(and(eq(clients.id, id as string), eq(clients.salonId, salonId as string)))
      .returning();

    if (!updatedClient) return res.status(404).json({ message: 'Client not found' });
    res.json(updatedClient);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error updating client' });
  }
});

// Delete Client
router.delete('/:id', authenticate, authorize(['OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.salonId;

  try {
    const [deletedClient] = await db.delete(clients)
      .where(and(eq(clients.id, id as string), eq(clients.salonId, salonId as string)))
      .returning();

    if (!deletedClient) return res.status(404).json({ message: 'Client not found' });
    res.json({ message: 'Client deleted successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error deleting client' });
  }
});

export default router;
