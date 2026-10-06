import { Router } from 'express';
import { db } from '../db';
import { services } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and } from 'drizzle-orm';
import { servicePackageItems } from '../db/schema';

const router = Router();

// Create Service (Owner only)
router.post('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { name, category, price, duration, isPackage, bundledServices, description, arabicName } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  try {
    const isPkgStr = isPackage ? 'true' : 'false';
    const [newService] = await db.insert(services).values({
      name,
      category,
      price: price.toString(),
      salonId,
      isPackage: isPkgStr,
      description,
      arabicName,
    }).returning();

    if (isPackage && Array.isArray(bundledServices) && bundledServices.length > 0) {
      const itemsToInsert = bundledServices.map((bs: any) => ({
        packageId: newService.id,
        serviceId: bs.serviceId,
        price: (bs.price || 0).toString()
      }));
      await db.insert(servicePackageItems).values(itemsToInsert);
    }

    res.status(201).json(newService);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error creating service' });
  }
});

// List Services (Owner and Staff)
router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.query.salonId as string) : req.user.salonId;
  try {
    const allServices = await db.query.services.findMany({
      where: and(eq(services.salonId, salonId as string), eq(services.isActive, 'true')),
      with: {
        bundleItems: {
          with: { service: true }
        }
      }
    });
    res.json(allServices);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching services' });
  }
});

// Update Service (Owner only)
router.put('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { name, category, price, duration, isPackage, bundledServices, description, arabicName } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  try {
    const isPkgStr = isPackage ? 'true' : 'false';
    const [updatedService] = await db.update(services)
      .set({ name, category, price: price.toString(), isPackage: isPkgStr, description, arabicName })
      .where(and(eq(services.id, id as string), eq(services.salonId, salonId as string)))
      .returning();

    if (!updatedService) return res.status(404).json({ message: 'Service not found' });

    if (isPackage && Array.isArray(bundledServices)) {
      await db.delete(servicePackageItems).where(eq(servicePackageItems.packageId, id as string));
      if (bundledServices.length > 0) {
        const itemsToInsert = bundledServices.map((bs: any) => ({
          packageId: id as string,
          serviceId: bs.serviceId,
          price: (bs.price || 0).toString()
        }));
        await db.insert(servicePackageItems).values(itemsToInsert);
      }
    }

    res.json(updatedService);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error updating service' });
  }
});

// Delete Service (Owner only)
router.delete('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  try {
    const [deletedService] = await db.update(services)
      .set({ isActive: 'false' })
      .where(and(eq(services.id, id as string), eq(services.salonId, salonId as string)))
      .returning();

    if (!deletedService) return res.status(404).json({ message: 'Service not found' });
    res.json({ message: 'Service deleted (soft) successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error deleting service' });
  }
});

// Bulk Create Services (Owner only)
router.post('/bulk', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { servicesList } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  if (!Array.isArray(servicesList) || servicesList.length === 0) {
    return res.status(400).json({ message: 'servicesList must be a non-empty array' });
  }

  try {
    const itemsToInsert = servicesList.map((s: any) => ({
      name: s.name,
      category: s.category || 'General',
      price: (s.price || 0).toString(),
      salonId,
      isPackage: 'false',
    }));

    await db.insert(services).values(itemsToInsert);
    res.status(201).json({ message: 'Services bulk created successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error bulk creating services' });
  }
});

export default router;
