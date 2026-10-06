import { Request, Response, NextFunction } from 'express';
import { verifyToken } from '../utils/auth';
import { db } from '../db';
import { users } from '../db/schema';
import { eq } from 'drizzle-orm';

export interface AuthRequest extends Request {
  user?: any;
}

export const authenticate = async (req: AuthRequest, res: Response, next: NextFunction): Promise<any> => {
  const token = req.headers.authorization?.split(' ')[1];

  if (!token) {
    return res.status(401).json({ message: 'Authentication required' });
  }

  try {
    const decoded = verifyToken(token) as any;
    
    // Check if token is expired (verifyToken should throw if expired, but double-check)
    const tokenExpiry = decoded.exp ? new Date(decoded.exp * 1000) : null;
    if (tokenExpiry && tokenExpiry < new Date()) {
      return res.status(401).json({ message: 'Token expired. Please login again.' });
    }
    
    const user = await db.query.users.findFirst({
      where: eq(users.id, decoded.id)
    });

    if (!user || (user.isActive !== null && user.isActive === 'false')) {
      return res.status(401).json({ message: 'Invalid or deactivated user' });
    }
    
    // Use fresh DB user for permissions (token might have stale data)
    req.user = {
      id: user.id,
      email: user.email,
      role: user.role,
      salonId: user.salonId,
      name: user.name
    };
    next();
  } catch (error: any) {
    // Check if error is specifically a token expiration
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ message: 'Token expired. Please login again.' });
    }
    return res.status(401).json({ message: 'Invalid token' });
  }
};

export const authorize = (roles: string[]) => {
  return (req: AuthRequest, res: Response, next: NextFunction) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ message: 'Unauthorized' });
    }
    next();
  };
};
