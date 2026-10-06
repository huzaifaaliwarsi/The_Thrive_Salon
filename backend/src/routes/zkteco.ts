import { Router } from 'express';
import { db } from '../db';
import { staff, salons, attendance, attendanceLocks } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, isNull, sql } from 'drizzle-orm';
import * as crypto from 'crypto';

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

// =========================================================================
// 1. ZKTeco Cloud ADMS Push Protocol Handshake & Log Receiver
// Compatible with Namecheap Stellar Plus cPanel Node.js (Standard HTTPS / 443)
// =========================================================================

// ADMS Device Handshake / Heartbeat
router.get('/iclock/cdata', async (req, res) => {
  const { SN, options } = req.query;
  console.log(`[ZKTeco ADMS] Handshake from Device SN: ${SN}, Options: ${options}`);
  
  if (SN) {
    try {
      await db.update(salons)
        .set({ 
          zktecoLastSync: new Date(),
          zktecoEnabled: true 
        })
        .where(eq(salons.zktecoDeviceSn, SN as string));
    } catch (_) {}
  }

  // ZKTeco ADMS expects "OK" or server registry parameters
  res.setHeader('Content-Type', 'text/plain');
  res.send('GET OPTION FROM: ' + (SN || 'SERVER') + '\nStamp=9999\nOpStamp=9999\nErrorDelay=30\nDelay=10\nTransTimes=00:00;14:00\nTransInterval=1\nTransFlag=1111000000\nRealtime=1\nEncrypt=0\n');
});

// ADMS Device Punch Receiver (Raw ATTLOG punches)
router.post('/iclock/cdata', async (req, res) => {
  const { SN, table } = req.query;
  const rawBody = req.body ? (typeof req.body === 'string' ? req.body : JSON.stringify(req.body)) : '';
  console.log(`[ZKTeco ADMS] Punch received from SN: ${SN}, Table: ${table}`);

  try {
    if (!SN) {
      return res.status(200).send('OK');
    }

    // Find salon linked to this ZKTeco Device Serial Number
    const salon = await db.query.salons.findFirst({
      where: eq(salons.zktecoDeviceSn, SN as string)
    });

    if (!salon) {
      console.warn(`[ZKTeco ADMS] Unrecognized device serial number: ${SN}`);
      return res.status(200).send('OK');
    }

    await db.update(salons)
      .set({ zktecoLastSync: new Date() })
      .where(eq(salons.id, salon.id));

    // If table is ATTLOG (Attendance Log), parse tab-separated punches
    // Format: PIN \t Time (YYYY-MM-DD HH:MM:SS) \t Status \t VerifyType
    if (table === 'ATTLOG' && rawBody) {
      const lines = rawBody.split('\n');
      for (const line of lines) {
        const parts = line.trim().split('\t');
        if (parts.length >= 2) {
          const pin = parts[0].trim();
          const punchTimeStr = parts[1].trim();
          const punchTime = new Date(punchTimeStr);

          if (pin && !isNaN(punchTime.getTime())) {
            await processSinglePunch(salon.id, pin, punchTime, SN as string);
          }
        }
      }
    }

    return res.status(200).send('OK\n');
  } catch (error) {
    console.error('[ZKTeco ADMS Error]:', error);
    return res.status(200).send('OK\n');
  }
});

// =========================================================================
// 2. Standard REST Webhook & Sync Agent Endpoint
// For Local Bridge Python/Node Agents or Direct JSON Push
// =========================================================================
router.post('/sync-logs', async (req, res) => {
  const { salonId, deviceSn, pushToken, punches } = req.body || {};

  if (!salonId || !Array.isArray(punches)) {
    return res.status(400).json({ message: 'salonId and punches array are required' });
  }

  try {
    const salon = await db.query.salons.findFirst({
      where: eq(salons.id, salonId)
    });

    if (!salon) {
      return res.status(404).json({ message: 'Salon not found' });
    }

    // Token-based validation if token is set
    if (salon.zktecoPushToken && salon.zktecoPushToken !== pushToken) {
      return res.status(401).json({ message: 'Invalid ZKTeco push token' });
    }

    let processedCount = 0;
    for (const p of punches) {
      const pin = p.biometricPin || p.pin || p.userId || p.staffId;
      const punchTime = new Date(p.timestamp || p.time || p.date);
      if (pin && !isNaN(punchTime.getTime())) {
        await processSinglePunch(salon.id, pin.toString(), punchTime, deviceSn || salon.zktecoDeviceSn);
        processedCount++;
      }
    }

    await db.update(salons)
      .set({ 
        zktecoLastSync: new Date(),
        zktecoEnabled: true,
        zktecoDeviceSn: deviceSn || salon.zktecoDeviceSn 
      })
      .where(eq(salons.id, salon.id));

    res.json({ message: 'Logs processed successfully', processedCount });
  } catch (error) {
    console.error('[ZKTeco Sync Error]:', error);
    res.status(500).json({ message: 'Error processing biometric punches' });
  }
});

// =========================================================================
// 3. Punch Processing Logic (Auto Check-In vs Check-Out)
// =========================================================================
async function processSinglePunch(salonId: string, biometricPin: string, punchTime: Date, deviceSn?: string) {
  const staffRecord = await db.query.staff.findFirst({
    where: and(
      eq(staff.salonId, salonId),
      eq(staff.biometricPin, biometricPin)
    )
  });

  if (!staffRecord) {
    console.warn(`[ZKTeco] No staff found in salon ${salonId} with biometric PIN: ${biometricPin}`);
    return;
  }

  const dateStr = punchTime.toISOString().split('T')[0];
  if (await checkIfLocked(salonId, dateStr)) {
    console.warn(`[ZKTeco] Attendance for ${dateStr} is locked in salon ${salonId}. Punch ignored.`);
    return;
  }

  // Find attendance record for this staff on this day
  const existingAttendance = await db.query.attendance.findFirst({
    where: and(
      eq(attendance.staffId, staffRecord.id),
      eq(attendance.salonId, salonId),
      eq(attendance.date, dateStr)
    )
  });

  const salonRecord = await db.query.salons.findFirst({ where: eq(salons.id, salonId) });
  const timezone = salonRecord?.timezone || 'Asia/Karachi';
  const lateTimeLimit = staffRecord.lateTimeLimit || salonRecord?.lateTimeLimit || '09:15';
  const earlyExitLimit = staffRecord.earlyExitTimeLimit || salonRecord?.earlyExitTimeLimit || '17:45';

  const localTimeStr = new Intl.DateTimeFormat('en-GB', {
    timeZone: timezone,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  }).format(punchTime);

  if (!existingAttendance) {
    // 1st Punch of the day -> CHECK-IN
    const status = localTimeStr > lateTimeLimit ? 'LATE' : 'PRESENT';
    await db.insert(attendance).values({
      staffId: staffRecord.id,
      salonId,
      status,
      approvalStatus: 'PENDING',
      date: dateStr,
      checkIn: punchTime,
      source: 'ZKTECO',
      deviceSn: deviceSn || null
    });
    console.log(`[ZKTeco] Check-In recorded for ${staffRecord.name} (PIN: ${biometricPin}) at ${punchTimeStr(punchTime)} -> Status: ${status}`);
  } else {
    // Repeat Punch on same day
    const checkInTime = existingAttendance.checkIn ? new Date(existingAttendance.checkIn) : null;
    
    // Ignore duplicate punches within 3 minutes of check-in
    if (checkInTime && Math.abs(punchTime.getTime() - checkInTime.getTime()) < 3 * 60 * 1000) {
      return;
    }

    const isEarly = localTimeStr < earlyExitLimit;

    // Update Check-Out to the latest punch
    await db.update(attendance)
      .set({
        checkOut: punchTime,
        earlyExit: isEarly,
        source: 'ZKTECO',
        deviceSn: deviceSn || existingAttendance.deviceSn
      })
      .where(eq(attendance.id, existingAttendance.id));

    console.log(`[ZKTeco] Check-Out updated for ${staffRecord.name} (PIN: ${biometricPin}) at ${punchTimeStr(punchTime)} -> Early Exit: ${isEarly}`);
  }
}

function punchTimeStr(d: Date): string {
  return d.toISOString().replace('T', ' ').substring(0, 19);
}

// =========================================================================
// 4. Branch Device Configuration Endpoints (Owner / Admin)
// =========================================================================
router.get('/config', authenticate, authorize(['OWNER', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.query.salonId as string || req.user.salonId) : req.user.salonId;
  if (!salonId) return res.status(400).json({ message: 'Salon ID required' });

  try {
    const salon = await db.query.salons.findFirst({
      where: eq(salons.id, salonId)
    });
    if (!salon) return res.status(404).json({ message: 'Salon not found' });

    // Generate token if not exists
    let token = salon.zktecoPushToken;
    if (!token) {
      token = crypto.randomBytes(16).toString('hex');
      await db.update(salons)
        .set({ zktecoPushToken: token })
        .where(eq(salons.id, salon.id));
    }

    // Get staff PIN list for verification
    const staffList = await db.query.staff.findMany({
      where: eq(staff.salonId, salon.id),
      columns: {
        id: true,
        name: true,
        biometricPin: true,
        phone: true
      }
    });

    const host = req.get('host') || 'localhost';
    const protocol = req.protocol === 'https' || req.headers['x-forwarded-proto'] === 'https' ? 'https' : 'http';
    const baseUrl = process.env.BACKEND_URL || `${protocol}://${host}`;
    const hostOnly = host.split(':')[0];
    const portOnly = host.split(':')[1] || (protocol === 'https' ? '443' : '80');

    res.json({
      deviceSn: salon.zktecoDeviceSn || '',
      deviceName: salon.zktecoDeviceName || 'ZKTeco Biometric Machine',
      pushToken: token,
      lastSync: salon.zktecoLastSync,
      enabled: salon.zktecoEnabled || false,
      serverPushUrl: `${baseUrl}/api/zkteco/iclock/cdata`,
      syncLogsUrl: `${baseUrl}/api/zkteco/sync-logs`,
      serverHost: hostOnly,
      serverPort: portOnly,
      staffEnrollments: staffList
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error loading ZKTeco config' });
  }
});

router.put('/config', authenticate, authorize(['OWNER', 'SUPER_ADMIN']), checkSubscription, async (req: AuthRequest, res) => {
  const salonId = req.user.role === 'SUPER_ADMIN' ? (req.body.salonId || req.query.salonId || req.user.salonId) : req.user.salonId;
  const { deviceSn, deviceName, enabled, regenerateToken } = req.body || {};

  if (!salonId) return res.status(400).json({ message: 'Salon ID required' });

  try {
    const updateData: any = {};
    if (deviceSn !== undefined) updateData.zktecoDeviceSn = deviceSn.trim();
    if (deviceName !== undefined) updateData.zktecoDeviceName = deviceName.trim();
    if (enabled !== undefined) updateData.zktecoEnabled = Boolean(enabled);
    if (regenerateToken) updateData.zktecoPushToken = crypto.randomBytes(16).toString('hex');

    const [updatedSalon] = await db.update(salons)
      .set(updateData)
      .where(eq(salons.id, salonId))
      .returning();

    res.json({
      message: 'ZKTeco device settings updated successfully',
      deviceSn: updatedSalon.zktecoDeviceSn,
      deviceName: updatedSalon.zktecoDeviceName,
      pushToken: updatedSalon.zktecoPushToken,
      enabled: updatedSalon.zktecoEnabled
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Error updating ZKTeco config' });
  }
});

export default router;
