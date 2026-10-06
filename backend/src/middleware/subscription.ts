import { Response, NextFunction } from 'express';
import { db } from '../db';
import { salons } from '../db/schema';
import { eq } from 'drizzle-orm';
import { AuthRequest } from './auth';
import { isPgSequence } from 'drizzle-orm/pg-core';

export const checkSubscription = async (req: AuthRequest, res: Response, next: NextFunction) => {
  const user = req.user;

  // Super Admin bypasses subscription checks
  if (!user || user.role === 'SUPER_ADMIN') {
    return next();
  }


  const salonId = user.salonId;
  if (!salonId) {
    return res.status(403).json({ message: 'No salon associated with this user' });
  }

  try {
    const salon = await db.query.salons.findFirst({
      
      where: eq(salons.id, salonId),
    });

    if (!salon) {
      return res.status(404).json({ message: 'Salon not found' });
    }

    if (salon.isSuspended === 'true') {
      return res.status(403).json({ message: 'Access Suspended: Please contact the administrator.' });
    }

    if (salon.subscriptionEnd) {
      const subEnd = new Date(salon.subscriptionEnd);
      // Exclude lifetime subscriptions (year 2099 or above)
      if (subEnd.getFullYear() < 2099 && subEnd < new Date()) {
        return res.status(403).json({ message: 'Subscription Expired: Please recharge to continue.' });
      }
    }

    next();
  } catch (error) {
    console.error('Subscription check error:', error);
    res.status(500).json({ message: 'Internal server error during subscription check' });
  }
};
