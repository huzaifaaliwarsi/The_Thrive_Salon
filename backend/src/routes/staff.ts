import { Router } from 'express';
import { db } from '../db';
import { staff, users, sales, ledgerEntries, staffSalaryHistory } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { hashPassword, validatePassword } from '../utils/auth';
import { eq, and, sql, or, ne } from 'drizzle-orm';

const router = Router();

// Validation Utilities
const validateEmail = (email: string): boolean => {
  // RFC 5322 simplified - accepts most common valid email formats
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
};

const validatePakistaniPhone = (phone: string): { valid: boolean; error?: string } => {
  if (!phone || phone.length === 0) {
    return { valid: true }; // Phone is optional
  }
  
  // Remove common separators and spaces
  const cleaned = phone.replace(/[\s\-()]/g, '');
  
  // Allow general international format: 5 to 20 digits, optional leading '+'
  const isValid = /^\+?[0-9]{5,20}$/.test(cleaned);
  
  if (!isValid) {
    return { 
      valid: false, 
      error: 'Invalid phone number format. Phone must contain between 5 and 20 digits.' 
    };
  }
  
  return { valid: true };
};

const validateSalaryAmount = (salaryValue: any, salaryType: string): { valid: boolean; error?: string } => {
  if (salaryType === 'COMMISSION') {
    return { valid: true }; // Salary not required for commission-only
  }
  
  if (salaryValue === undefined || salaryValue === null || salaryValue === '') {
    return { valid: false, error: `Salary amount required for salary type: ${salaryType}` };
  }
  
  const parsed = parseFloat(salaryValue?.toString() || '0');
  if (isNaN(parsed)) {
    return { valid: false, error: 'Salary must be a valid number' };
  }
  if (parsed < 0) {
    return { valid: false, error: 'Salary cannot be negative' };
  }
  
  return { valid: true };
};

const validateCommission = (commissionPercentage: any): { valid: boolean; error?: string } => {
  const parsed = parseFloat(commissionPercentage?.toString() || '0');
  if (isNaN(parsed)) {
    return { valid: false, error: 'Commission must be a valid number' };
  }
  if (parsed < 0 || parsed > 100) {
    return { valid: false, error: 'Commission percentage must be between 0 and 100' };
  }
  return { valid: true };
};


// Create Staff (Owner only)
router.post('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  let { 
    name, 
    phone, 
    biometricPin,
    salaryType, 
    salaryValue, 
    commissionPercentage,
    inTimeLimit,
    outTimeLimit,
    lateTimeLimit,
    earlyExitTimeLimit,
    lateDeductionRate,
    earlyExitDeductionRate,
    allowedLeaves,
    joiningDate
  } = req.body;
  const email = req.body.email?.toString().trim().toLowerCase() || null;
  const password = req.body.password?.toString().trim();
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  // Validate salonId
  if (!salonId) {
    return res.status(403).json({ message: 'Unauthorized: No salon ID found' });
  }

  // Input Validation
  if (!name || !email || !password) {
    return res.status(400).json({ message: 'Name, Email, and Password are required' });
  }

  // Validate email
  if (!validateEmail(email)) {
    return res.status(400).json({ message: 'Invalid email format' });
  }

  // Validate password
  const pwdCheck = validatePassword(password);
  if (!pwdCheck.valid) {
    return res.status(400).json({ message: pwdCheck.error });
  }

  // Sanitize and validate phone (Pakistan-specific)
  // Empty string must become null to avoid UNIQUE constraint on empty strings
  const rawPhone = phone?.toString().trim();
  let cleanPhone: string | null = (rawPhone && rawPhone.length > 0) ? rawPhone : null;
  if (cleanPhone) {
    const phoneCheck = validatePakistaniPhone(cleanPhone);
    if (!phoneCheck.valid) {
      return res.status(400).json({ message: phoneCheck.error });
    }
  }

  // Validate salaryType
  const validSalaryTypes = ['MONTHLY', 'DAILY', 'COMMISSION', 'MONTHLY_PLUS_COMMISSION', 'DAILY_PLUS_COMMISSION'];
  if (!validSalaryTypes.includes(salaryType)) {
    return res.status(400).json({ 
      message: `Invalid salary type. Must be one of: ${validSalaryTypes.join(', ')}` 
    });
  }

  // Validate salary amount
  const salaryCheck = validateSalaryAmount(salaryValue, salaryType);
  if (!salaryCheck.valid) {
    return res.status(400).json({ message: salaryCheck.error });
  }

  // Validate commission percentage
  const commissionCheck = validateCommission(commissionPercentage);
  if (!commissionCheck.valid) {
    return res.status(400).json({ message: commissionCheck.error });
  }

  // Validate late/early exit deduction rates (non-negative)
  if (lateDeductionRate !== undefined && Number(lateDeductionRate) < 0) {
    return res.status(400).json({ message: 'Late deduction rate/amount cannot be negative.' });
  }
  if (earlyExitDeductionRate !== undefined && Number(earlyExitDeductionRate) < 0) {
    return res.status(400).json({ message: 'Early exit deduction rate/amount cannot be negative.' });
  }

  // Pre-check for duplicate email/phone scoped to this salon only (multi-tenant)
  const emailConflict = await db.query.users.findFirst({
    where: and(eq(users.salonId, salonId), eq(users.email, email as string)),
  });
  if (emailConflict) {
    return res.status(409).json({ message: 'A staff member with this email already exists in your salon.' });
  }

  if (cleanPhone) {
    const phoneConflict = await db.query.users.findFirst({
      where: and(eq(users.salonId, salonId), eq(users.phone, cleanPhone)),
    });
    if (phoneConflict) {
      return res.status(409).json({ message: 'A staff member with this phone number already exists in your salon.' });
    }
  }

  try {
    const result = await db.transaction(async (tx) => {
      // Create User Account
      const hashedPassword = await hashPassword(password);
      const [newUser] = await tx.insert(users).values({
        name,
        email,
        phone: cleanPhone,
        password: hashedPassword,
        plainPassword: password,
        role: 'STAFF',
        salonId,
      }).returning();

      // Auto-assign biometric PIN if not provided
      let finalPin = biometricPin ? biometricPin.toString().trim() : null;
      if (!finalPin) {
        const existingStaff = await tx.query.staff.findMany({
          where: eq(staff.salonId, salonId),
          columns: { biometricPin: true }
        });
        const pins = existingStaff
          .map(s => parseInt(s.biometricPin || '0', 10))
          .filter(n => !isNaN(n) && n > 0);
        const maxPin = pins.length > 0 ? Math.max(...pins) : 0;
        finalPin = (maxPin + 1).toString();
      }

      // Create Staff Profile with audit trail
      const [newStaff] = await tx.insert(staff).values({
        userId: newUser.id,
        name,
        phone: cleanPhone,
        biometricPin: finalPin,
        salaryType,
        salaryValue: salaryValue?.toString(),
        commissionPercentage: commissionPercentage?.toString() || '0',
        salonId,
        inTimeLimit: inTimeLimit || null,
        outTimeLimit: outTimeLimit || null,
        lateTimeLimit: lateTimeLimit || null,
        earlyExitTimeLimit: earlyExitTimeLimit || null,
        lateDeductionRate: lateDeductionRate?.toString() || '0',
        earlyExitDeductionRate: earlyExitDeductionRate?.toString() || '0',
        allowedLeaves: allowedLeaves != null ? Number(allowedLeaves) : 0,
        joiningDate: joiningDate || undefined,
      }).returning();

      // Create initial Salary History record
      await tx.insert(staffSalaryHistory).values({
        staffId: newStaff.id,
        salonId,
        salaryType,
        salaryValue: salaryValue?.toString(),
        commissionPercentage: commissionPercentage?.toString() || '0',
        effectiveDate: joiningDate || new Date().toISOString().split('T')[0],
      });

      return { ...newStaff };
    });

    console.log(`[Staff Create] ✅ Staff ${result.id} created by user ${req.user.id} for salon ${salonId}`);
    res.status(201).json(result);
  } catch (error: any) {
    console.error('[Staff Creation Error] Detailed Trace:', error);
    
    // Resolve DrizzleQueryError nested pg causes
    const pgError = error.cause || error;
    
    // Check for Drizzle/Postgres specific errors
    if (pgError.code === '23505') {
      const detail = pgError.detail || '';
      if (detail.includes('email')) {
        return res.status(400).json({ message: 'A staff member with this email already exists.' });
      }
      if (detail.includes('phone')) {
        return res.status(400).json({ message: 'This phone number is already registered to another staff member.' });
      }
      return res.status(400).json({ message: 'Duplicate data detected. This staff member may already exist.' });
    }

    res.status(500).json({ 
      message: 'Failed to create staff member.', 
      error: error.message,
      code: pgError.code || error.code
    });
  }
});

// List Staff (Super Admin, Owner, and Staff)
router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  let salonId = req.user.salonId;
  if (req.user.role === 'SUPER_ADMIN') {
    salonId = req.query.salonId as string;
  }
  try {
    // Allow STAFF to fetch the full list of staff (e.g. for booking appointments)
    const whereClause = eq(staff.salonId, salonId as string);

    const allStaff = await db.query.staff.findMany({
      where: whereClause,
      with: {
        user: {
          columns: {
            password: false,
            plainPassword: false,
          }
        },
      },
    });

    // Fetch aggregate sales for each staff member
    if (allStaff.length > 0) {
      const aggSales = await db.select({
        staffId: sales.staffId,
        salesCount: sql<number>`count(${sales.id})`,
        totalSalesRevenue: sql<number>`sum(${sales.total})`
      }).from(sales).where(and(eq(sales.salonId, salonId as string), eq(sales.status, 'ACTIVE'))).groupBy(sales.staffId);

      const aggLedger = await db.select({
        staffId: ledgerEntries.staffId,
        balance: sql<string>`sum(CASE WHEN ${ledgerEntries.type} = 'DEBIT' THEN ${ledgerEntries.amount}::numeric ELSE -(${ledgerEntries.amount}::numeric) END)`
      }).from(ledgerEntries)
        .where(and(
          eq(ledgerEntries.salonId, salonId as string),
          sql`${ledgerEntries.staffId} IS NOT NULL`,
          or(
            eq(ledgerEntries.category, 'STAFF_ADVANCE'),
            eq(ledgerEntries.category, 'STAFF_DEDUCTION')
          )
        ))
        .groupBy(ledgerEntries.staffId);

      const finalStaff = allStaff.map(s => {
        const stats = aggSales.find((a: any) => a.staffId === s.id) || { salesCount: 0, totalSalesRevenue: 0 };
        const ledger = aggLedger.find((l: any) => l.staffId === s.id) || { balance: '0' };
        
        const isOwnProfile = req.user.role === 'OWNER' || s.userId === req.user.id;

        return {
          ...s,
          // Mask sensitive info if it's not their own profile
          salaryValue: isOwnProfile ? s.salaryValue : null,
          salaryType: isOwnProfile ? s.salaryType : 'CONFIDENTIAL',
          commissionPercentage: isOwnProfile ? s.commissionPercentage : null,
          phone: isOwnProfile ? s.phone : (s.phone ? '***' : null),
          user: s.user ? {
            ...s.user,
            email: isOwnProfile ? s.user.email : '***@***.com',
            phone: isOwnProfile ? s.user.phone : (s.user.phone ? '***' : null)
          } : null,
          salesCount: isOwnProfile ? Number(stats.salesCount) : 0,
          totalSalesRevenue: isOwnProfile ? Number(stats.totalSalesRevenue) : 0,
          balance: isOwnProfile ? parseFloat(ledger.balance || '0') : 0
        };
      });
      return res.json(finalStaff);
    }

    res.json(allStaff);
  } catch (error: any) {
    console.error(error);
    res.status(500).json({ 
      message: 'Error fetching staff', 
      error: error.message,
      stack: error.stack,
      details: error
    });
  }
});

// Get Staff by ID (Owner and Staff)
router.get('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.salonId;

  try {
    let whereClause = and(eq(staff.id, id as string), eq(staff.salonId, salonId));
    if (req.user.role === 'STAFF') {
      whereClause = and(whereClause, eq(staff.userId, req.user.id))!;
    }

    const singleStaff = await db.query.staff.findFirst({
      where: whereClause,
      with: {
        user: {
          columns: {
            password: false,
            plainPassword: false,
          }
        },
      },
    });

    if (!singleStaff) {
      return res.status(404).json({ message: 'Staff not found' });
    }
    res.json(singleStaff);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching staff member' });
  }
});

// Update Staff (Owner only)
router.put('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const { 
    name, email, phone, salaryType, salaryValue, commissionPercentage, effectiveDate,
    inTimeLimit, outTimeLimit, lateTimeLimit, earlyExitTimeLimit,
    lateDeductionRate, earlyExitDeductionRate, allowedLeaves, joiningDate
  } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  // Validate salonId
  if (!salonId) {
    return res.status(403).json({ message: 'Unauthorized: No salon ID found' });
  }

  try {
    // Validate email if provided
    if (email) {
      if (!validateEmail(email)) {
        return res.status(400).json({ message: 'Invalid email format' });
      }
    }

    // Validate salaryType if provided
    if (salaryType) {
      const validSalaryTypes = ['MONTHLY', 'DAILY', 'COMMISSION', 'MONTHLY_PLUS_COMMISSION', 'DAILY_PLUS_COMMISSION'];
      if (!validSalaryTypes.includes(salaryType)) {
        return res.status(400).json({ 
          message: `Invalid salary type. Must be one of: ${validSalaryTypes.join(', ')}` 
        });
      }

      // Validate salary amount if salaryType is being changed
      const salaryCheck = validateSalaryAmount(salaryValue, salaryType);
      if (!salaryCheck.valid) {
        return res.status(400).json({ message: salaryCheck.error });
      }
    }

    // Validate phone if provided (Pakistan-specific)
    let cleanPhone = phone?.toString().trim() || null;
    if (cleanPhone) {
      const phoneCheck = validatePakistaniPhone(cleanPhone);
      if (!phoneCheck.valid) {
        return res.status(400).json({ message: phoneCheck.error });
      }
    }

    // Validate commission if provided
    if (commissionPercentage !== undefined && commissionPercentage !== null) {
      const commissionCheck = validateCommission(commissionPercentage);
      if (!commissionCheck.valid) {
        return res.status(400).json({ message: commissionCheck.error });
      }
    }

    // Validate late/early exit deduction rates (non-negative)
    if (lateDeductionRate !== undefined && Number(lateDeductionRate) < 0) {
      return res.status(400).json({ message: 'Late deduction rate/amount cannot be negative.' });
    }
    if (earlyExitDeductionRate !== undefined && Number(earlyExitDeductionRate) < 0) {
      return res.status(400).json({ message: 'Early exit deduction rate/amount cannot be negative.' });
    }

    // Fetch the current staff profile first
    const currentStaffProfile = await db.query.staff.findFirst({
      where: and(eq(staff.id, id as string), eq(staff.salonId, salonId as string)),
    });
    if (!currentStaffProfile) {
      return res.status(404).json({ message: 'Staff not found' });
    }

    // Pre-check duplicate email/phone
    if (email || cleanPhone) {
      const existingUser = await db.query.users.findFirst({
        where: and(
          eq(users.salonId, salonId as string),
          currentStaffProfile.userId ? ne(users.id, currentStaffProfile.userId) : undefined,
          or(
            email ? eq(users.email, email) : undefined,
            cleanPhone ? eq(users.phone, cleanPhone) : undefined
          )
        )
      });
      if (existingUser) {
        return res.status(499).json({ message: 'A user with this email or phone already exists in this salon.' });
      }
    }

    const result = await db.transaction(async (tx) => {
      // 1. Update user details
      if (currentStaffProfile.userId) {
        await tx.update(users)
          .set({
            name,
            email: email ? email.toString().trim().toLowerCase() : undefined,
            phone: cleanPhone
          })
          .where(eq(users.id, currentStaffProfile.userId));
      }

      // 2. Update staff profile
      const updateData: any = { 
        name, 
        phone: cleanPhone, 
        salaryType, 
        salaryValue: salaryValue?.toString(),
        commissionPercentage: commissionPercentage?.toString()
      };
      if (req.body.biometricPin !== undefined) {
        updateData.biometricPin = req.body.biometricPin ? req.body.biometricPin.toString().trim() : null;
      }
      // Only update timing fields if explicitly provided
      if (inTimeLimit !== undefined) updateData.inTimeLimit = inTimeLimit || null;
      if (outTimeLimit !== undefined) updateData.outTimeLimit = outTimeLimit || null;
      if (lateTimeLimit !== undefined) updateData.lateTimeLimit = lateTimeLimit || null;
      if (earlyExitTimeLimit !== undefined) updateData.earlyExitTimeLimit = earlyExitTimeLimit || null;
      if (lateDeductionRate !== undefined) updateData.lateDeductionRate = lateDeductionRate?.toString();
      if (earlyExitDeductionRate !== undefined) updateData.earlyExitDeductionRate = earlyExitDeductionRate?.toString();
      if (allowedLeaves !== undefined) updateData.allowedLeaves = Number(allowedLeaves);
      if (joiningDate !== undefined) updateData.joiningDate = joiningDate || null;

      const [updatedStaff] = await tx.update(staff)
        .set(updateData)
        .where(and(eq(staff.id, id as string), eq(staff.salonId, salonId as string)))
        .returning();

      if (!updatedStaff) throw new Error('Staff update failed');

      // 3. Track Salary History changes
      const salaryChanged = 
        (salaryType && salaryType !== currentStaffProfile.salaryType) ||
        (salaryValue !== undefined && salaryValue?.toString() !== currentStaffProfile.salaryValue?.toString()) ||
        (commissionPercentage !== undefined && commissionPercentage?.toString() !== currentStaffProfile.commissionPercentage?.toString());

      if (salaryChanged) {
        const effDate = effectiveDate ? effectiveDate.toString().trim() : new Date().toISOString().split('T')[0];
        
        await tx.insert(staffSalaryHistory).values({
          staffId: updatedStaff.id,
          salonId,
          salaryType: salaryType || currentStaffProfile.salaryType,
          salaryValue: salaryValue !== undefined ? salaryValue.toString() : currentStaffProfile.salaryValue,
          commissionPercentage: commissionPercentage !== undefined ? commissionPercentage.toString() : currentStaffProfile.commissionPercentage,
          effectiveDate: effDate,
        });
      }

      return updatedStaff;
    });

    console.log(`[Staff Update] ✅ Staff ${id} updated by user ${req.user.id} for salon ${salonId}`);
    res.json(result);
  } catch (error: any) {
    console.error('[Staff Update Error]:', error);
    if (error.code === '23505') {
      if (error.message.includes('email')) {
        return res.status(400).json({ message: 'Email already in use' });
      }
      if (error.message.includes('phone')) {
        return res.status(400).json({ message: 'Phone number already in use' });
      }
      return res.status(400).json({ message: 'Email or phone number already in use' });
    }
    res.status(500).json({ message: 'Error updating staff', error: error.message });
  }
});

// Delete Staff (Owner only)
router.delete('/:id', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  try {
    const [deletedStaff] = await db.delete(staff)
      .where(and(eq(staff.id, id as string), eq(staff.salonId, salonId as string)))
      .returning();

    if (!deletedStaff) return res.status(404).json({ message: 'Staff not found' });
    
    if (deletedStaff.userId) {
      await db.delete(users).where(eq(users.id, deletedStaff.userId));
    }

    res.json({ message: 'Staff and associated user account deleted successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error deleting staff' });
  }
});

// Bulk Create Staff (Owner only)
router.post('/bulk', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { staffList } = req.body;
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;

  if (!Array.isArray(staffList) || staffList.length === 0) {
    return res.status(400).json({ message: 'staffList must be a non-empty array' });
  }

  try {
    for (const s of staffList) {
      const email = s.email;
      let userId: string | null = null;

      // Ensure user exists if email is provided
      if (email) {
        const existingUsers = await db.select().from(users).where(eq(users.email, email));
        if (existingUsers.length > 0) {
          userId = existingUsers[0].id;
        } else {
          const passwordHash = await hashPassword(s.password || 'Staff@123');
          const [newUser] = await db.insert(users).values({
            name: s.name,
            email,
            password: passwordHash,
            plainPassword: s.password || 'Staff@123',
            role: 'STAFF',
            salonId,
          }).returning();
          userId = newUser.id;
        }
      }

      // Insert staff
      await db.insert(staff).values({
        name: s.name,
        phone: s.phone || '',
        salaryType: s.salaryType || 'MONTHLY',
        salaryValue: (s.salaryValue || 0).toString(),
        commissionPercentage: (s.commissionPercentage || 0).toString(),
        salonId,
        userId,
      });
    }

    res.status(201).json({ message: 'Staff bulk created successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error bulk creating staff' });
  }
});

export default router;
