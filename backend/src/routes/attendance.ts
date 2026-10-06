import { Router } from 'express';
import { db } from '../db';
import { attendance, staff, salons, attendanceLocks } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, isNull, gte, lte } from 'drizzle-orm';

const router = Router();

// Helper: Check if date attendance is locked
const checkIfLocked = async (salonId: string, dateStr: string): Promise<boolean> => {
  const lock = await db.query.attendanceLocks.findFirst({
    where: and(
      eq(attendanceLocks.salonId, salonId),
      eq(attendanceLocks.date, dateStr)
    )
  });
  return !!lock;
};

// Check-in
router.post('/check-in', authenticate, authorize(['STAFF', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const userId = req.user.id;
  const salonId = req.user.salonId;

  try {
    const staffRecord = await db.query.staff.findFirst({
      where: and(eq(staff.userId, userId as string), eq(staff.salonId, salonId as string))
    });
    if (!staffRecord) return res.status(403).json({ message: 'Staff profile not found' });

    const attendanceDate = new Date().toISOString().split('T')[0];
    if (await checkIfLocked(salonId as string, attendanceDate)) {
      return res.status(400).json({ message: 'Attendance for today is locked and cannot be modified.' });
    }

    // Prevent double check-in
    const activeCheckIn = await db.query.attendance.findFirst({
      where: and(
        eq(attendance.staffId, staffRecord.id),
        eq(attendance.salonId, salonId as string),
        isNull(attendance.checkOut)
      )
    });

    if (activeCheckIn) {
      return res.status(400).json({ message: 'You already have an active check-in. Please check-out first.' });
    }

    // Resolve late status limit — prefer staff-level timing, fallback to salon-level
    const salonRecord = await db.query.salons.findFirst({
      where: eq(salons.id, salonId as string)
    });
    const timezone = salonRecord?.timezone || 'Asia/Karachi';
    const lateTimeLimit = staffRecord.lateTimeLimit || salonRecord?.lateTimeLimit || '09:15';

    const now = new Date();
    const localTimeStr = new Intl.DateTimeFormat('en-GB', {
      timeZone: timezone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    }).format(now);

    const finalStatus = localTimeStr > lateTimeLimit ? 'LATE' : 'PRESENT';

    const [newAttendance] = await db.insert(attendance).values({
      staffId: staffRecord.id,
      salonId: salonId as string,
      status: finalStatus,
      approvalStatus: 'PENDING',
      date: new Date().toISOString().split('T')[0],
      checkIn: now,
    }).returning();
    res.status(201).json(newAttendance);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error during check-in' });
  }
});

// Check-out
router.post('/check-out', authenticate, authorize(['STAFF', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { staffId: providedStaffId } = req.body || {};
  const userId = req.user.id;
  const salonId = req.user.salonId;
  let staffIdToUpdate: string;

  try {
    const attendanceDate = new Date().toISOString().split('T')[0];
    if (await checkIfLocked(salonId as string, attendanceDate)) {
      return res.status(400).json({ message: 'Attendance for today is locked and checkout is disabled.' });
    }

    if (providedStaffId && req.user.role === 'OWNER') {
      staffIdToUpdate = providedStaffId;
    } else {
      const staffRecord = await db.query.staff.findFirst({
        where: and(eq(staff.userId, userId as string), eq(staff.salonId, salonId as string))
      });
      if (!staffRecord) return res.status(403).json({ message: 'Staff profile not found' });
      staffIdToUpdate = staffRecord.id;
    }

    // Security: If owner provides a staffId, ensure it belongs to their salon
    if (providedStaffId && req.user.role === 'OWNER') {
      const targetStaff = await db.query.staff.findFirst({
        where: and(eq(staff.id, staffIdToUpdate), eq(staff.salonId, salonId as string))
      });
      if (!targetStaff) return res.status(403).json({ message: 'Staff member does not belong to your salon' });
    }

    // Resolve timezone and early exit time limit — prefer staff-level, fallback to salon
    const salonRecord = await db.query.salons.findFirst({
      where: eq(salons.id, salonId as string)
    });
    const staffRecord = await db.query.staff.findFirst({
      where: eq(staff.id, staffIdToUpdate)
    });
    const earlyExitTimeLimit = staffRecord?.earlyExitTimeLimit || salonRecord?.earlyExitTimeLimit || '17:45';
    const timezone = salonRecord?.timezone || 'Asia/Karachi';

    const now = new Date();
    const localTimeStr = new Intl.DateTimeFormat('en-GB', {
      timeZone: timezone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    }).format(now);

    const isEarlyExit = localTimeStr < earlyExitTimeLimit;

    const [updatedAttendance] = await db.update(attendance)
      .set({ 
        checkOut: new Date(),
        earlyExit: isEarlyExit,
        approvalStatus: 'PENDING' // Reset to pending for approval of checkout time
      })
      .where(and(
        eq(attendance.staffId, staffIdToUpdate),
        eq(attendance.salonId, salonId as string),
        isNull(attendance.checkOut)
      ))
      .returning();

    if (!updatedAttendance) return res.status(404).json({ message: 'Active check-in not found' });
    res.json(updatedAttendance);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error during check-out' });
  }
});

// List Attendance
router.get('/', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.query.salonId as string) : req.user.salonId;
  const { staffId } = req.query;

  try {
    let whereClause = eq(attendance.salonId, salonId as string);
    if (req.user.role === 'STAFF') {
      const staffRecord = await db.query.staff.findFirst({
        where: eq(staff.userId, req.user.id as string)
      });
      if (staffRecord) {
        whereClause = and(whereClause, eq(attendance.staffId, staffRecord.id))!;
      }
    } else if (staffId) {
      whereClause = and(whereClause, eq(attendance.staffId, staffId as string))!;
    }

    const allAttendances = await db.query.attendance.findMany({
      where: whereClause,
      with: {
        staff: true,
      },
      orderBy: (attendance, { desc }) => [desc(attendance.date), desc(attendance.createdAt)],
    });
    res.json(allAttendances);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error fetching attendance' });
  }
});

// Approve Attendance (Owner only)
router.patch('/:id/approve', authenticate, authorize(['OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.salonId;

  try {
    const [updated] = await db.update(attendance)
      .set({ approvalStatus: 'APPROVED' })
      .where(and(eq(attendance.id, id as string), eq(attendance.salonId, salonId as string)))
      .returning();

    if (!updated) return res.status(404).json({ message: 'Attendance record not found' });
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error approving attendance' });
  }
});

// Reject Attendance (Owner only)
router.patch('/:id/reject', authenticate, authorize(['OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { id } = req.params;
  const salonId = req.user.salonId;

  try {
    const [updated] = await db.update(attendance)
      .set({ approvalStatus: 'REJECTED' })
      .where(and(eq(attendance.id, id as string), eq(attendance.salonId, salonId as string)))
      .returning();

    if (!updated) return res.status(404).json({ message: 'Attendance record not found' });
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error rejecting attendance' });
  }
});

// Mark Attendance Manually (Owner only)
router.post('/mark', authenticate, authorize(['OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { staffId, status, date, checkIn, checkOut } = req.body || {};
  const salonId = req.user.salonId;

  try {
    // Validate dates (Bug #23: Date validation)
    const validateDate = (dateStr: string, fieldName: string): Date | null => {
      if (!dateStr) return null;
      const parsed = new Date(dateStr);
      if (isNaN(parsed.getTime())) {
        throw new Error(`Invalid ${fieldName} format: ${dateStr}`);
      }
      return parsed;
    };

    const hasCheckIn = req.body && 'checkIn' in req.body;
    const hasCheckOut = req.body && 'checkOut' in req.body;
    const checkInDate = checkIn ? validateDate(checkIn, 'checkIn') : null;
    const checkOutDate = checkOut ? validateDate(checkOut, 'checkOut') : null;
    const attendanceDate = date || new Date().toISOString().split('T')[0];

    const todayStr = new Date().toISOString().split('T')[0];
    if (attendanceDate > todayStr) {
      return res.status(400).json({ message: 'Cannot mark attendance for future dates' });
    }

    if (await checkIfLocked(salonId as string, attendanceDate)) {
      return res.status(400).json({ message: 'Attendance for this date is locked and cannot be modified.' });
    }

    // Security: Ensure staff member belongs to this salon
    const staffRecord = await db.query.staff.findFirst({
      where: and(eq(staff.id, staffId), eq(staff.salonId, salonId as string))
    });
    if (!staffRecord) {
      return res.status(403).json({ message: 'Staff member does not belong to your salon' });
    }

    const salonRecord = await db.query.salons.findFirst({
      where: eq(salons.id, salonId as string)
    });
    const timezone = salonRecord?.timezone || 'Asia/Karachi';
    const resolvedLateLimit = staffRecord.lateTimeLimit || salonRecord?.lateTimeLimit || '09:15';
    const resolvedEarlyExitLimit = staffRecord.earlyExitTimeLimit || salonRecord?.earlyExitTimeLimit || '17:45';

    const getLocalTimeStr = (dateObj: Date, tz: string): string => {
      return new Intl.DateTimeFormat('en-GB', {
        timeZone: tz,
        hour: '2-digit',
        minute: '2-digit',
        hour12: false
      }).format(dateObj);
    };

    const existing = await db.query.attendance.findFirst({
      where: and(
        eq(attendance.staffId, staffId),
        eq(attendance.salonId, salonId as string),
        eq(attendance.date, attendanceDate)
      )
    });

    let finalStatus = status || 'ABSENT';
    if (checkInDate && (finalStatus === 'PRESENT' || finalStatus === 'LATE')) {
      const localCheckInTime = getLocalTimeStr(checkInDate, timezone);
      finalStatus = localCheckInTime > resolvedLateLimit ? 'LATE' : 'PRESENT';
    }

    if (finalStatus === 'LEAVE') {
      const [yearStr, monthStr] = attendanceDate.split('-');
      const year = parseInt(yearStr);
      const month = parseInt(monthStr);
      const monthStart = `${yearStr}-${monthStr}-01`;
      const lastDay = new Date(year, month, 0).getDate();
      const monthEnd = `${yearStr}-${monthStr}-${lastDay.toString().padStart(2, '0')}`;

      const existingLeaves = await db.query.attendance.findMany({
        where: and(
          eq(attendance.staffId, staffId),
          eq(attendance.salonId, salonId as string),
          eq(attendance.status, 'LEAVE'),
          gte(attendance.date, monthStart),
          lte(attendance.date, monthEnd)
        )
      });

      const leaveCount = existingLeaves.filter(el => !existing || el.id !== existing.id).length;
      const allowed = staffRecord.allowedLeaves || 0;
      if (leaveCount >= allowed) {
        finalStatus = 'ABSENT';
      }
    }

    let isEarlyExit = false;
    if (checkOutDate && finalStatus !== 'ABSENT' && finalStatus !== 'LEAVE') {
      const localCheckOutTime = getLocalTimeStr(checkOutDate, timezone);
      isEarlyExit = localCheckOutTime < resolvedEarlyExitLimit;
    }

    let result;
    if (existing) {
      const [updated] = await db.update(attendance)
        .set({ 
          status: finalStatus, 
          checkIn: hasCheckIn ? checkInDate : existing.checkIn, 
          checkOut: hasCheckOut ? checkOutDate : existing.checkOut,
          earlyExit: hasCheckOut ? isEarlyExit : (finalStatus === 'ABSENT' || finalStatus === 'LEAVE' ? false : existing.earlyExit),
          approvalStatus: 'APPROVED'
        })
        .where(eq(attendance.id, existing.id))
        .returning();
      result = updated;
    } else {
      const [inserted] = await db.insert(attendance).values({
        staffId,
        salonId: salonId as string,
        status: finalStatus,
        date: attendanceDate,
        checkIn: hasCheckIn ? checkInDate : null,
        checkOut: hasCheckOut ? checkOutDate : null,
        earlyExit: isEarlyExit,
        approvalStatus: 'APPROVED'
      }).returning();
      result = inserted;
    }
    
    res.status(200).json(result);
  } catch (error) {
    console.error(error);
    const message = error instanceof Error ? error.message : 'Error marking attendance';
    res.status(400).json({ message });
  }
});

const getDatesInRange = (startStr: string, endStr: string): string[] => {
  const dates: string[] = [];
  const current = new Date(`${startStr}T00:00:00`);
  const end = new Date(`${endStr}T00:00:00`);
  while (current <= end) {
    dates.push(current.toISOString().split('T')[0]);
    current.setDate(current.getDate() + 1);
  }
  return dates;
};

// Bulk Mark Attendance (Owner only)
router.post('/bulk', authenticate, authorize(['OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { startDate, endDate, records } = req.body || {};
  const salonId = req.user.salonId;

  if (!startDate || !endDate) {
    return res.status(400).json({ message: 'startDate and endDate are required' });
  }
  if (!records || !Array.isArray(records) || records.length === 0) {
    return res.status(400).json({ message: 'records must be a non-empty array of { staffId, status }' });
  }

  try {
    const dates = getDatesInRange(startDate, endDate);

    const todayStr = new Date().toISOString().split('T')[0];
    for (const d of dates) {
      if (d > todayStr) {
        return res.status(400).json({ message: `Cannot mark attendance for future date: ${d}` });
      }
      if (await checkIfLocked(salonId as string, d)) {
        return res.status(400).json({ message: `Attendance for date ${d} is locked and cannot be modified.` });
      }
    }

    const result = await db.transaction(async (tx) => {
      const updatedOrInserted = [];

      for (const record of records) {
        const { staffId, status } = record;

        // Security: Ensure staff member belongs to this salon
        const staffRecord = await tx.query.staff.findFirst({
          where: and(eq(staff.id, staffId), eq(staff.salonId, salonId as string))
        });
        if (!staffRecord) {
          throw new Error(`Staff member ${staffId} does not belong to your salon`);
        }

        for (const attendanceDate of dates) {
          const existing = await tx.query.attendance.findFirst({
            where: and(
              eq(attendance.staffId, staffId),
              eq(attendance.salonId, salonId as string),
              eq(attendance.date, attendanceDate)
            )
          });

          let finalStatus = status || 'ABSENT';
          if (finalStatus === 'LEAVE') {
            const [yearStr, monthStr] = attendanceDate.split('-');
            const year = parseInt(yearStr);
            const month = parseInt(monthStr);
            const monthStart = `${yearStr}-${monthStr}-01`;
            const lastDay = new Date(year, month, 0).getDate();
            const monthEnd = `${yearStr}-${monthStr}-${lastDay.toString().padStart(2, '0')}`;

            const existingLeaves = await tx.query.attendance.findMany({
              where: and(
                eq(attendance.staffId, staffId),
                eq(attendance.salonId, salonId as string),
                eq(attendance.status, 'LEAVE'),
                gte(attendance.date, monthStart),
                lte(attendance.date, monthEnd)
              )
            });

            const leaveCount = existingLeaves.filter(el => !existing || el.id !== existing.id).length;
            const allowed = staffRecord.allowedLeaves || 0;
            if (leaveCount >= allowed) {
              finalStatus = 'ABSENT';
            }
          }

          if (existing) {
            const [updated] = await tx.update(attendance)
              .set({
                status: finalStatus,
                approvalStatus: 'APPROVED',
                checkIn: (finalStatus === 'ABSENT' || finalStatus === 'LEAVE' || finalStatus === 'PRESENT') ? null : existing.checkIn,
                checkOut: (finalStatus === 'ABSENT' || finalStatus === 'LEAVE' || finalStatus === 'PRESENT') ? null : existing.checkOut,
              })
              .where(eq(attendance.id, existing.id))
              .returning();
            updatedOrInserted.push(updated);
          } else {
            const [inserted] = await tx.insert(attendance).values({
              staffId,
              salonId: salonId as string,
              status: finalStatus,
              date: attendanceDate,
              approvalStatus: 'APPROVED',
              checkIn: null,
              checkOut: null
            }).returning();
            updatedOrInserted.push(inserted);
          }
        }
      }
      return updatedOrInserted;
    });

    res.status(200).json({
      message: `Successfully marked attendance for ${records.length} staff member(s) across ${dates.length} date(s)`,
      count: result.length
    });
  } catch (error) {
    console.error(error);
    const message = error instanceof Error ? error.message : 'Error marking bulk attendance';
    res.status(400).json({ message });
  }
});

// Lock Attendance (Owner only)
router.post('/lock', authenticate, authorize(['OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  const { date } = req.body || {};
  const salonId = req.user.salonId;
  const userId = req.user.id;

  if (!date) return res.status(400).json({ message: 'Date is required to lock attendance' });

  try {
    const todayStr = new Date().toISOString().split('T')[0];
    if (date > todayStr) {
      return res.status(400).json({ message: 'Cannot lock attendance for future dates' });
    }

    const lock = await db.query.attendanceLocks.findFirst({
      where: and(eq(attendanceLocks.salonId, salonId as string), eq(attendanceLocks.date, date as string))
    });

    if (lock) {
      return res.status(200).json({ message: 'Attendance already locked for ' + date, record: lock });
    }

    const [lockRecord] = await db.insert(attendanceLocks).values({
      salonId: salonId as string,
      date,
      lockedBy: userId as string,
    }).returning();

    res.status(201).json({ message: 'Attendance locked successfully for ' + date, record: lockRecord });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error locking attendance' });
  }
});

// Get Lock Status
router.get('/lock-status', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  let salonId = req.user.role === 'SUPER_ADMIN' ? (req.query.salonId as string) : req.user.salonId;
  const { date } = req.query;

  if (!date) return res.status(400).json({ message: 'Date is required to check lock status' });

  try {
    const lock = await db.query.attendanceLocks.findFirst({
      where: and(
        eq(attendanceLocks.salonId, salonId as string),
        eq(attendanceLocks.date, date as string)
      )
    });

    res.json({ date, locked: !!lock, lockRecord: lock || null });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error checking lock status' });
  }
});

export default router;
