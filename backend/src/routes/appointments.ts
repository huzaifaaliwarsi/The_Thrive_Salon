import { Router } from 'express';
import { db } from '../db';
import { appointments, staff, clients } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, or, isNull } from 'drizzle-orm';

const router = Router();

// Create Appointment
router.post('/', authenticate, authorize(['OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const { serviceId, serviceIds, serviceDetails, staffId: rawStaffId, customerName, customerPhone, appointmentTime, notes } = req.body;
  const staffId = (rawStaffId && rawStaffId !== '' && rawStaffId !== 'null') ? rawStaffId : null;
  const salonId = req.user.salonId;

  try {
    // Security: Validate staff and service ownership
    if (staffId) {
      const staffRecord = await db.query.staff.findFirst({
        where: and(eq(staff.id, staffId as string), eq(staff.salonId, salonId as string))
      });
      if (!staffRecord) return res.status(403).json({ message: 'Staff member does not belong to your salon' });
    }

    const { services } = require('../db/schema');
    
    // Determine the list of service IDs
    let resolvedServiceIds: string[] = [];
    if (Array.isArray(serviceIds) && serviceIds.length > 0) {
      resolvedServiceIds = serviceIds;
    } else if (serviceId) {
      resolvedServiceIds = [serviceId];
    }

    if (resolvedServiceIds.length === 0) {
      return res.status(400).json({ message: 'At least one service must be selected' });
    }

    // Validate that all services belong to the salon
    for (const sId of resolvedServiceIds) {
      const serviceRecord = await db.query.services.findFirst({
        where: and(eq(services.id, sId), eq(services.salonId, salonId as string))
      });
      if (!serviceRecord) return res.status(403).json({ message: `Service ${sId} does not belong to your salon` });
    }

    const mainServiceId = resolvedServiceIds[0];

    const [newAppointment] = await db.insert(appointments).values({
      salonId: salonId as string,
      serviceId: mainServiceId,
      serviceIds: resolvedServiceIds.join(','),
      serviceDetails: serviceDetails ? JSON.stringify(serviceDetails) : null,
      staffId,
      customerName,
      customerPhone,
      appointmentTime: new Date(appointmentTime),
      notes,
    }).returning();

    // Handle Client logic
    if (customerPhone && customerName) {
      const existingClient = await db.query.clients.findFirst({
        where: and(eq(clients.phone, customerPhone as string), eq(clients.salonId, salonId as string))
      });

      if (existingClient) {
        // Update name if it was empty before but provided now
        if ((existingClient.name === 'Unknown' || !existingClient.name) && customerName) {
          await db.update(clients).set({ name: customerName }).where(eq(clients.id, existingClient.id));
        }
      } else {
        // Create new client
        await db.insert(clients).values({
          salonId: salonId as string,
          name: customerName,
          phone: customerPhone,
          totalSpent: '0',
          lastVisit: new Date()
        });
      }
    }

    res.status(201).json(newAppointment);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error creating appointment' });
  }
});

// List Appointments
router.get('/', authenticate, authorize(['OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.salonId;
  const { staffId } = req.query;

  try {
    let whereClause = eq(appointments.salonId, salonId as string);
    
    if (staffId) {
      whereClause = and(whereClause, eq(appointments.staffId, staffId as string))!;
    }

    const allAppointments = await db.query.appointments.findMany({
      where: whereClause,
      with: {
        service: {
          with: { bundleItems: { with: { service: true } } }
        },
        staff: true,
      },
      orderBy: (appointments, { asc }) => [asc(appointments.appointmentTime)],
    });

    const { services } = require('../db/schema');
    const salonServices = await db.query.services.findMany({
      where: eq(services.salonId, salonId as string),
      with: {
        bundleItems: {
          with: { service: true }
        }
      }
    });
    const serviceMap = new Map(salonServices.map(s => [s.id, s]));

    const formattedAppointments = allAppointments.map(app => {
      const ids = app.serviceIds ? app.serviceIds.split(',') : (app.serviceId ? [app.serviceId] : []);
      const resolvedServices = ids.map(id => serviceMap.get(id)).filter(Boolean);
      return {
        ...app,
        services: resolvedServices,
      };
    });

    res.json(formattedAppointments);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching appointments' });
  }
});

// Update Appointment (Status / Reschedule / Assign Staff)
router.patch('/:id', authenticate, authorize(['OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const { status, staffId, appointmentTime, notes, serviceIds, serviceDetails } = req.body;
  const { id } = req.params;
  const salonId = req.user.salonId;

  let cleanStaffId: string | null | undefined = undefined;
  if (staffId !== undefined) {
    cleanStaffId = (staffId && staffId !== '' && staffId !== 'null') ? staffId : null;
  }

  try {
    // Security: Validate staff ownership if being assigned
    if (cleanStaffId) {
      const staffRecord = await db.query.staff.findFirst({
        where: and(eq(staff.id, cleanStaffId as string), eq(staff.salonId, salonId as string))
      });
      if (!staffRecord) return res.status(403).json({ message: 'Staff member does not belong to your salon' });
    }

    // Determine and validate service IDs if provided
    let resolvedServiceIds: string[] = [];
    let mainServiceId: string | undefined;
    if (Array.isArray(serviceIds) && serviceIds.length > 0) {
      resolvedServiceIds = serviceIds;
      const { services } = require('../db/schema');
      
      // Validate that all services belong to the salon
      for (const sId of resolvedServiceIds) {
        const serviceRecord = await db.query.services.findFirst({
          where: and(eq(services.id, sId), eq(services.salonId, salonId as string))
        });
        if (!serviceRecord) return res.status(403).json({ message: `Service ${sId} does not belong to your salon` });
      }
      mainServiceId = resolvedServiceIds[0];
    }

    const updates: any = {
        ...(status && { status }),
        ...(cleanStaffId !== undefined && { staffId: cleanStaffId }),
        ...(appointmentTime && { appointmentTime: new Date(appointmentTime) }),
        ...(notes !== undefined && { notes }),
        ...(resolvedServiceIds.length > 0 && {
          serviceId: mainServiceId,
          serviceIds: resolvedServiceIds.join(','),
        }),
        ...(serviceDetails !== undefined && { serviceDetails: serviceDetails ? JSON.stringify(serviceDetails) : null }),
    };

    const [updated] = await db.update(appointments)
      .set(updates)
      .where(and(eq(appointments.id, id as string), eq(appointments.salonId, salonId as string)))
      .returning();

    if (!updated) return res.status(404).json({ message: 'Appointment not found' });
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error updating appointment' });
  }
});

export default router;
