import { Router } from 'express';
import { db } from '../db';
import { users } from '../db/schema';
import { eq, ilike } from 'drizzle-orm';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { comparePassword, generateToken, hashPassword } from '../utils/auth';

const router = Router();

router.post('/login', async (req, res) => {
  const email = req.body.email?.toString().trim().toLowerCase();
  const password = req.body.password?.toString().trim();

  try {
    const user = await db.query.users.findFirst({
      where: ilike(users.email, email || ''),
      with: {
        salon: true,
      },
    });

    if (!user || !(await comparePassword(password, user.password))) {
      return res.status(401).json({ message: 'Invalid email or password' });
    }

    if (user.isActive === 'false') {
      return res.status(403).json({ message: 'Account is locked. Please contact admin.' });
    }

    const token = generateToken({
      id: user.id,
      email: user.email,
      role: user.role,
      salonId: user.salonId,
    });

    res.json({
      token,
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role,
        salonId: user.salonId,
        salon: user.salon, // Includes subscriptionEnd and isSuspended
      },
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.get('/me', authenticate, async (req: AuthRequest, res) => {
  try {
    const user = await db.query.users.findFirst({
      where: eq(users.id, req.user.id),
      with: {
        salon: true,
      },
    });

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      salonId: user.salonId,
      salon: user.salon,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// Toggle User Account Status (Admin/Owner Only)
router.patch('/users/:id/toggle-lock', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), async (req: AuthRequest, res) => {
  const id = req.params.id as string;
  try {
    const user = await db.query.users.findFirst({ where: eq(users.id, id) });
    if (!user) return res.status(404).json({ message: 'User not found' });

    const newStatus = user.isActive === 'false' ? 'true' : 'false';
    await db.update(users).set({ isActive: newStatus }).where(eq(users.id, id));
    
    res.json({ message: `User account ${newStatus === 'true' ? 'unlocked' : 'locked'} successfully` });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error toggling account status' });
  }
});

// Reset User Password (Admin/Owner Only)
router.post('/users/:id/reset-password', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), async (req: AuthRequest, res) => {
  const id = req.params.id as string;
  const { newPassword } = req.body;
  
  if (!newPassword) return res.status(400).json({ message: 'New password is required' });

  try {
    const targetUser = await db.query.users.findFirst({ where: eq(users.id, id) });
    if (!targetUser) return res.status(404).json({ message: 'User not found' });

    // OWNER can only reset passwords of users in their own salon
    if (req.user.role === 'OWNER' && targetUser.salonId !== req.user.salonId) {
      return res.status(403).json({ message: 'Unauthorized: Cannot reset password for users outside your salon' });
    }

    const hashedPassword = await hashPassword(newPassword);
    await db.update(users).set({ 
      password: hashedPassword
    }).where(eq(users.id, id));
    res.json({ message: 'Password reset successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error resetting password' });
  }
});

export default router;
