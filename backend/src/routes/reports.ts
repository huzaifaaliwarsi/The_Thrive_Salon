import { Router } from 'express';
import { db } from '../db';
import { sales, expenses, staff, attendance, salaryDeductions, inventoryItems, inventoryTransactions, ledgerEntries, purchases, clients, vendors, staffSalaryHistory, salons } from '../db/schema';
import { authenticate, authorize, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { eq, and, gte, lte, sql, inArray, lt, sum, isNotNull, ne, desc } from 'drizzle-orm';
import { isOnlineSql, getSalonGallaBalances } from '../utils/ledger';

const router = Router();

// Helper: Get default date range
const getDefaultDateRange = (): [Date, Date] => {
  const end = new Date();
  end.setHours(23, 59, 59, 999);
  const start = new Date();
  start.setDate(start.getDate() - 30);
  start.setHours(0, 0, 0, 0);
  return [start, end];
};

// Helper: Validate period length (max 365 days)
const validatePeriodLength = (start: Date, end: Date): boolean => {
  const diffMs = end.getTime() - start.getTime();
  const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
  return diffDays <= 365;
};

const normalizePeriod = (p: any): string => {
  if (!p) return 'unknown';
  const d = p instanceof Date ? p : new Date(p);
  return isNaN(d.getTime()) ? 'unknown' : d.toISOString().split('T')[0];
};

// Get Sales and Profit Reports (Owner and Staff)
router.get('/summary', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  let salonId = req.user.salonId;
  if (req.user.role === 'SUPER_ADMIN') {
    salonId = req.query.salonId as string;
  }
  console.log(`[Reports] v1.6 - Request for Salon: ${salonId} @ ${new Date().toISOString()}`);
  // Validate salonId for security
  if (!salonId) {
    return res.status(403).json({ message: 'Unauthorized: No salon ID' });
  }
  const { startDate, endDate, groupBy, timezoneOffset } = req.query;
  let offset = parseInt(timezoneOffset as string) || 0;
  // If offset is positive (e.g. 300 for PKT UTC+5 from Flutter), convert to milliseconds to subtract from UTC
  const offsetMs = (offset > 0 ? -offset : Math.abs(offset)) * 60 * 1000;

  try {
    // Validate and parse dates (handle timezone properly)
    let start: Date, end: Date;
    try {
      const startParam = (startDate as string) || '';
      const endParam = (endDate as string) || '';

      if (!startParam || !endParam) {
        const [defaultStart, defaultEnd] = getDefaultDateRange();
        start = defaultStart;
        end = defaultEnd;
      } else if (startParam.length === 10 && endParam.length === 10) {
        // YYYY-MM-DD format from client
        const [sy, sm, sd] = startParam.split('-').map(Number);
        const [ey, em, ed] = endParam.split('-').map(Number);

        // Construct UTC timestamps for start and end of local days
        const baseStartUtc = Date.UTC(sy, sm - 1, sd, 0, 0, 0, 0);
        const baseEndUtc = Date.UTC(ey, em - 1, ed, 23, 59, 59, 999);

        start = offset !== 0 ? new Date(baseStartUtc + offsetMs) : new Date(baseStartUtc);
        end = offset !== 0 ? new Date(baseEndUtc + offsetMs) : new Date(baseEndUtc);
      } else {
        start = new Date(startParam);
        end = new Date(endParam);
      }

      var startStr = startParam.substring(0, 10);
      var endStr = endParam.substring(0, 10);
      var startIso = start.toISOString();
      var endIso = end.toISOString();
    } catch (e) {
      return res.status(400).json({ message: 'Invalid date format. Use ISO format (YYYY-MM-DD or YYYY-MM-DDTHH:mm:ss)' });
    }


    // Validate date range
    if (start > end) {
      return res.status(400).json({ message: 'Start date must be before end date' });
    }

    // Validate period length (max 365 days)
    if (!validatePeriodLength(start, end)) {
      return res.status(400).json({ message: 'Report period cannot exceed 365 days' });
    }

    let resolvedStaffId: string | undefined;
    let cachedStaffRecord: any = null;

    if (req.user.role === 'STAFF') {
      cachedStaffRecord = await db.query.staff.findFirst({
        where: and(eq(staff.userId, req.user.id as string), eq(staff.salonId, salonId as string))
      });
      if (cachedStaffRecord) {
        resolvedStaffId = cachedStaffRecord.id;
      } else {
        return res.json({
          totalSales: 0,
          saleCount: 0,
          totalExpenses: 0,
          commission: 0,
          profit: 0,
          period: { start, end },
          breakdown: []
        });
      }
    } else if ((req.user.role === 'OWNER' || req.user.role === 'SUPER_ADMIN') && req.query.staffId) {
      const queryStaffId = req.query.staffId as string;
      try {
        const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
        if (uuidRegex.test(queryStaffId)) {
          cachedStaffRecord = await db.query.staff.findFirst({
            where: and(eq(staff.id, queryStaffId), eq(staff.salonId, salonId as string))
          });

          if (cachedStaffRecord && cachedStaffRecord.salonId === salonId) {
            resolvedStaffId = cachedStaffRecord.id;
          } else if (cachedStaffRecord) {
            return res.status(403).json({ message: 'Unauthorized: Staff does not belong to this salon' });
          }
        } else {
          return res.status(400).json({ message: 'Invalid Staff ID format' });
        }
      } catch (err) {
        console.error('[Report] Error looking up staff:', err);
      }
    }

    const effectiveStaffId = resolvedStaffId;
    
    // Cache all staff
    const allActiveStaff = await db.query.staff.findMany({
      where: eq(staff.salonId, salonId as string)
    });
    const staffMap = new Map(allActiveStaff.map(s => [s.id, s]));

    let salesWhere = and(
      eq(sales.salonId, salonId as string),
      eq(sales.status, 'ACTIVE'),
      gte(sales.createdAt, start),
      lte(sales.createdAt, end)
    );
    if (effectiveStaffId) {
      salesWhere = and(salesWhere, eq(sales.staffId, effectiveStaffId))!;
    }

    const attendanceCounts = new Map<string, number>();


    // 1. Core Metrics
    let totalInventoryCost = 0;
    let totalInternalRevenue = 0;
    // Removed duplicate totalInventoryCost calculation. It is properly calculated below from utilized stock (OUT transactions).

    let totalSalesResult: any[] = [];
    let netServiceSales = 0;
    let netProductSales = 0;
    try {
      console.log(`[Reports] Fetching sales metrics with payment date attribution...`);

      // 1a. Billings and invoices created in period
      const billingsRes = await db.select({
        totalBillings: sql<number>`sum(CAST(${sales.total} AS NUMERIC))`,
        tax: sum(sales.taxAmount),
        count: sql<number>`count(${sales.id})`
      }).from(sales).where(and(
        eq(sales.salonId, salonId as string),
        eq(sales.status, 'ACTIVE'),
        gte(sales.createdAt, start),
        lte(sales.createdAt, end),
        effectiveStaffId ? eq(sales.staffId, effectiveStaffId) : undefined
      ));

      // 1b. Payments collected in period (attributed to payment date via ratio)
      const paymentsRes = await db.execute(sql`
        SELECT 
          sum(CAST(l.amount AS NUMERIC)) as total_paid,
          sum(COALESCE(CAST(s.tax_amount AS NUMERIC) * (CAST(l.amount AS NUMERIC) / NULLIF(CAST(s.total AS NUMERIC), 0)), 0)) as collected_tax,
          sum(COALESCE(CAST(s.discount AS NUMERIC) * (CAST(l.amount AS NUMERIC) / NULLIF(CAST(s.total AS NUMERIC), 0)), 0)) as total_discount
        FROM ledger_entries l
        LEFT JOIN sales s ON l.sale_id = s.id
        WHERE l.salon_id = ${salonId}::uuid
          AND (s.id IS NULL OR s.status = 'ACTIVE')
          AND l.category = 'PAYMENT' AND l.type = 'DEBIT'
          AND l.vendor_id IS NULL
          AND COALESCE(l.date, l.created_at) >= ${startIso}::timestamptz AND COALESCE(l.date, l.created_at) <= ${endIso}::timestamptz
          ${effectiveStaffId ? sql`AND (l.staff_id = ${effectiveStaffId}::uuid OR (s.id IS NOT NULL AND s.staff_id = ${effectiveStaffId}::uuid))` : sql``}
      `);

      const pRow = (paymentsRes.rows[0] as any) || {};
      const bRow = billingsRes[0] || {};

      totalSalesResult = [{
        totalPaid: Math.max(0, Number(pRow.total_paid || 0)),
        totalBillings: Math.max(0, Number(bRow.totalBillings || 0)),
        tax: Number(bRow.tax || 0),
        collectedTax: Math.max(0, Number(pRow.collected_tax || 0)),
        totalDiscountGiven: Math.max(0, Number(pRow.total_discount || 0)),
        count: Number(bRow.count || 0)
      }];

      // Calculate Net Service Sales for invoices created in period
      const serviceSalesRes = await db.execute(sql`
        SELECT sum(
          CAST(si.price AS NUMERIC) * CAST(si.quantity AS NUMERIC) - COALESCE(CAST(si.discount_amount AS NUMERIC), 0)
        ) as total
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        LEFT JOIN inventory_items ii ON (
          (si.product_id IS NOT NULL AND si.product_id = ii.id)
          OR (si.service_id IS NOT NULL AND (
            si.service_id = ii.id
            OR (si.service_id::text LIKE 'inv_%' AND replace(si.service_id::text, 'inv_', '')::uuid = ii.id)
          ))
        )
        WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE'
              AND s.created_at >= ${startIso}::timestamptz AND s.created_at <= ${endIso}::timestamptz
              AND si.is_internal = false
              AND ii.id IS NULL
              AND si.product_id IS NULL
              AND (si.service_id IS NULL OR si.service_id::text NOT LIKE 'inv_%')
              ${effectiveStaffId ? sql`AND (si.staff_id = ${effectiveStaffId}::uuid OR (si.staff_id IS NULL AND s.staff_id = ${effectiveStaffId}::uuid))` : sql``}
      `);
      netServiceSales = Number((serviceSalesRes.rows[0] as any)?.total || 0);

      // Calculate Net Product Sales for invoices created in period
      const productSalesRes = await db.execute(sql`
        SELECT sum(
          CAST(si.price AS NUMERIC) * CAST(si.quantity AS NUMERIC) - COALESCE(CAST(si.discount_amount AS NUMERIC), 0)
        ) as total
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        LEFT JOIN inventory_items ii ON (
          (si.product_id IS NOT NULL AND si.product_id = ii.id)
          OR (si.service_id IS NOT NULL AND (
            si.service_id = ii.id
            OR (si.service_id::text LIKE 'inv_%' AND replace(si.service_id::text, 'inv_', '')::uuid = ii.id)
          ))
        )
        WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE'
              AND s.created_at >= ${startIso}::timestamptz AND s.created_at <= ${endIso}::timestamptz
              AND si.is_internal = false
              AND (ii.id IS NOT NULL OR si.product_id IS NOT NULL OR (si.service_id IS NOT NULL AND si.service_id::text LIKE 'inv_%'))
              ${effectiveStaffId ? sql`AND (si.staff_id = ${effectiveStaffId}::uuid OR (si.staff_id IS NULL AND s.staff_id = ${effectiveStaffId}::uuid))` : sql``}
      `);
      netProductSales = Number((productSalesRes.rows[0] as any)?.total || 0);


      // Calculate internal revenue to subtract from total revenue
      const internalSalesResult = await db.execute(sql`
        SELECT sum(CAST(si.price AS NUMERIC) * CAST(si.quantity AS NUMERIC)) as total
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE'
              AND s.created_at >= ${startIso}::timestamptz AND s.created_at <= ${endIso}::timestamptz
              AND si.is_internal = true
              ${effectiveStaffId ? sql`AND s.staff_id = ${effectiveStaffId}::uuid` : sql``}
      `);
      totalInternalRevenue = Number((internalSalesResult.rows[0] as any)?.total || 0);
    } catch (err) {
      console.error('[Reports] Sales Metrics Query Error:', err);
      throw new Error(`Sales query failed: ${err}`);
    }


    let totalCommissionVal = 0;
    try {
      const commissionResult = await db.execute(sql`
        SELECT sum(
          CAST(si.commission_amount AS NUMERIC) * 
          (CAST(l.amount AS NUMERIC) / NULLIF(CAST(s.total AS NUMERIC), 0))
        ) as total
        FROM ledger_entries l
        JOIN sales s ON l.sale_id = s.id
        JOIN sale_items si ON si.sale_id = s.id
        WHERE l.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE'
          AND l.category = 'PAYMENT' AND l.type = 'DEBIT'
          AND l.date >= ${startIso}::timestamptz AND l.date <= ${endIso}::timestamptz
          AND si.is_internal = false
          ${effectiveStaffId ? sql`AND (si.staff_id = ${effectiveStaffId}::uuid OR (si.staff_id IS NULL AND s.staff_id = ${effectiveStaffId}::uuid))` : sql``}
      `);
      totalCommissionVal = Number((commissionResult.rows[0] as any)?.total || 0);
    } catch (err) {
      console.error('[Reports] Commission Query Error:', err);
    }

    let totalExpensesResult: any[] = [];
    let totalSalaryPaid = 0;
    try {
      totalExpensesResult = effectiveStaffId ? [{ total: 0 }] : await db.select({
        total: sum(expenses.amount)
      }).from(expenses).where(and(
        eq(expenses.salonId, salonId as string),
        gte(expenses.date, startStr),
        lte(expenses.date, endStr)
      ));

      if (effectiveStaffId) {
        const salaryPaidRes = await db.select({
          total: sum(expenses.amount)
        }).from(expenses)
          .innerJoin(ledgerEntries, eq(ledgerEntries.expenseId, expenses.id))
          .where(and(
            eq(expenses.salonId, salonId as string),
            eq(expenses.category, 'Salaries'),
            eq(ledgerEntries.staffId, effectiveStaffId),
            gte(expenses.date, startStr),
            lte(expenses.date, endStr)
          ));
        totalSalaryPaid = Number(salaryPaidRes[0]?.total || 0);
      } else {
        const salaryPaidRes = await db.select({
          total: sum(expenses.amount)
        }).from(expenses).where(and(
          eq(expenses.salonId, salonId as string),
          eq(expenses.category, 'Salaries'),
          gte(expenses.date, startStr),
          lte(expenses.date, endStr)
        ));
        totalSalaryPaid = Number(salaryPaidRes[0]?.total || 0);
      }
    } catch (err) {
      console.error('[Reports] Expenses/Salary Paid Query Error:', err);
    }

    // Calculate staff base salaries proportionally for the selected period
    let totalSalaryPortion = 0;
    let totalAttendanceDeductions = 0;
    const attendanceDeductionsList: any[] = [];
    let staffAttendanceSummary: any[] = [];
    try {
      const salonRecord = await db.query.salons.findFirst({
        where: eq(salons.id, salonId as string)
      });
      const salonLateDefault = Number(salonRecord?.lateDeductionRate || 0);
      const salonEarlyDefault = Number(salonRecord?.earlyExitDeductionRate || 0);

      const staffList = await db.query.staff.findMany({
        where: and(
          eq(staff.salonId, salonId as string),
          effectiveStaffId ? eq(staff.id, effectiveStaffId) : undefined
        )
      });

      // Fetch salary history for the salon
      const salaryHistoryList = await db.query.staffSalaryHistory.findMany({
        where: eq(staffSalaryHistory.salonId, salonId as string),
        orderBy: (sh, { asc }) => [asc(sh.effectiveDate)],
      });

      // Fetch attendance for the period (both APPROVED and PENDING)
      const attendanceList = await db.query.attendance.findMany({
        where: and(
          eq(attendance.salonId, salonId as string),
          gte(attendance.date, startStr),
          lte(attendance.date, endStr),
          ne(attendance.approvalStatus, 'REJECTED')
        )
      });

      const formatDateToLocalStr = (d: Date) => {
        const year = d.getFullYear();
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const date = String(d.getDate()).padStart(2, '0');
        return `${year}-${month}-${date}`;
      };

      // Build a fast attendance lookup map: staffId -> Map of date string -> attendance record
      const staffAttendanceMap = new Map<string, Map<string, any>>();
      for (const a of attendanceList) {
        if (a.staffId && a.date) {
          if (!staffAttendanceMap.has(a.staffId)) {
            staffAttendanceMap.set(a.staffId, new Map<string, any>());
          }
          staffAttendanceMap.get(a.staffId)!.set(a.date, a);
        }
      }

      // Group salary history list by staff ID
      const staffSalaryHistoryMap = new Map<string, any[]>();
      for (const sh of salaryHistoryList) {
        if (sh.staffId) {
          if (!staffSalaryHistoryMap.has(sh.staffId)) {
            staffSalaryHistoryMap.set(sh.staffId, []);
          }
          staffSalaryHistoryMap.get(sh.staffId)!.push(sh);
        }
      }

      for (const s of staffList) {
        const staffLateRate = Number(s.lateDeductionRate) > 0 ? Number(s.lateDeductionRate) : salonLateDefault;
        const staffEarlyRate = Number(s.earlyExitDeductionRate) > 0 ? Number(s.earlyExitDeductionRate) : salonEarlyDefault;

        // Enforce salary calculations only start from hire/joining date
        const joiningDateStr = s.joiningDate || (s as any).joining_date;
        const staffJoining = joiningDateStr ? new Date(joiningDateStr) : (s.createdAt ? new Date(s.createdAt) : new Date(0));
        staffJoining.setHours(0, 0, 0, 0);

        let current = new Date(Math.max(start.getTime(), staffJoining.getTime()));
        current.setHours(0, 0, 0, 0);
        const endDay = new Date(end);
        endDay.setHours(0, 0, 0, 0);

        const history = staffSalaryHistoryMap.get(s.id) || [];
        const presentDates = staffAttendanceMap.get(s.id) || new Map<string, any>();

        const allowed = s.allowedLeaves || 0;
        const monthlyPaidLeavesMap = new Map<string, number>();

        while (current <= endDay) {
          const currentDateStr = formatDateToLocalStr(current);
          const yearMonth = currentDateStr.substring(0, 7);

          // Find history entry for this date (history is pre-sorted ascending by effectiveDate)
          let activeSalary = null;
          for (const record of history) {
            if (record.effectiveDate <= currentDateStr) {
              activeSalary = record;
            } else {
              break;
            }
          }
          if (!activeSalary) {
            activeSalary = {
              salaryType: s.salaryType,
              salaryValue: s.salaryValue,
            };
          }

          const val = Number(activeSalary.salaryValue || 0);
          let dailyRate = 0;
          const year = current.getFullYear();
          const month = current.getMonth();
          const daysInMonth = new Date(year, month + 1, 0).getDate();

          if (activeSalary.salaryType === 'COMMISSION') {
            dailyRate = 0;
          } else if (activeSalary.salaryType === 'MONTHLY' || activeSalary.salaryType === 'MONTHLY_PLUS_COMMISSION') {
            const attRecord = presentDates.get(currentDateStr);
            if (attRecord && attRecord.status === 'ABSENT') {
              dailyRate = 0;
            } else if (attRecord && attRecord.status === 'LEAVE') {
              const leavesPaid = monthlyPaidLeavesMap.get(yearMonth) || 0;
              if (leavesPaid < allowed) {
                dailyRate = val / daysInMonth;
                monthlyPaidLeavesMap.set(yearMonth, leavesPaid + 1);
              } else {
                dailyRate = 0;
              }
            } else {
              dailyRate = val / daysInMonth;
            }
          } else if (activeSalary.salaryType?.includes('DAILY')) {
            const attRecord = presentDates.get(currentDateStr);
            if (attRecord && (attRecord.status === 'PRESENT' || attRecord.status === 'LATE' || attRecord.status === 'SUNDAY' || attRecord.status === 'HOLIDAY')) {
              dailyRate = val;
            } else if (attRecord && attRecord.status === 'LEAVE') {
              const leavesPaid = monthlyPaidLeavesMap.get(yearMonth) || 0;
              if (leavesPaid < allowed) {
                dailyRate = val;
                monthlyPaidLeavesMap.set(yearMonth, leavesPaid + 1);
              } else {
                dailyRate = 0;
              }
            } else {
              dailyRate = 0;
            }
          }

          totalSalaryPortion += dailyRate;

          // Late & early exit deductions are calculated if they had an attendance record
          const attRecord = presentDates.get(currentDateStr);
          if (attRecord && dailyRate > 0) {
            if (attRecord.status === 'LATE') {
              const penalty = staffLateRate;
              totalAttendanceDeductions += penalty;
              attendanceDeductionsList.push({
                type: 'DEDUCTION',
                amount: Math.round(penalty * 100) / 100,
                reason: `Late Penalty - ${s.name || 'Staff'} (${currentDateStr})`,
                date: currentDateStr
              });
            }

            if (attRecord.earlyExit === true || attRecord.earlyExit === 'true') {
              const penalty = staffEarlyRate;
              totalAttendanceDeductions += penalty;
              attendanceDeductionsList.push({
                type: 'DEDUCTION',
                amount: Math.round(penalty * 100) / 100,
                reason: `Early Exit Penalty - ${s.name || 'Staff'} (${currentDateStr})`,
                date: currentDateStr
              });
            }
          }
          current.setDate(current.getDate() + 1);
        }
      }
      totalSalaryPortion = Math.round(totalSalaryPortion * 100) / 100;

      // Compile attendance summary per staff member (for daily & monthly wage staff)
      const allAttendanceForSummary = await db.query.attendance.findMany({
        where: and(
          eq(attendance.salonId, salonId as string),
          gte(attendance.date, startStr),
          lte(attendance.date, endStr),
          ne(attendance.approvalStatus, 'REJECTED')
        )
      });

      staffAttendanceSummary = staffList.map(s => {
        const staffAtts = allAttendanceForSummary.filter(a => a.staffId === s.id);
        let presentDays = 0;
        let absentDays = 0;
        let leaveDays = 0;
        let lateDays = 0;
        let earlyExits = 0;
        let sundayDays = 0;
        let holidayDays = 0;

        staffAtts.forEach(a => {
          if (a.status === 'PRESENT') presentDays++;
          else if (a.status === 'ABSENT') absentDays++;
          else if (a.status === 'LEAVE') leaveDays++;
          else if (a.status === 'SUNDAY') sundayDays++;
          else if (a.status === 'HOLIDAY') holidayDays++;
          else if (a.status === 'LATE') {
            lateDays++;
            presentDays++;
          }
          if (a.earlyExit === true || String(a.earlyExit) === 'true') {
            earlyExits++;
          }
        });

        return {
          staffId: s.id,
          name: s.name,
          salaryType: s.salaryType,
          presentDays,
          absentDays,
          leaveDays,
          lateDays,
          earlyExits,
          sundayDays,
          holidayDays
        };
      });
    } catch (err) {
      console.error('[Reports] Salary Calculation Error:', err);
    }

    const monthlyStaffAttendance = (staffAttendanceSummary || []).filter((s: any) => s.salaryType?.includes('MONTHLY'));
    const dailyStaffAttendance = (staffAttendanceSummary || []).filter((s: any) => s.salaryType?.includes('DAILY'));

    // 1. Calculate Product COGS (Cost of Goods Sold for products sold) and Stock Details
    let productCogs = 0;
    let stockPurchasesValue = 0;
    totalInventoryCost = 0;
    let utilizedStockQty = 0;
    let totalStockAvailable = 0;
    let utilizedStockItems: any[] = [];

    try {
      if (!effectiveStaffId) {
        // Calculate true Product COGS (retail products sold + internal salon consumables used)
        const productCogsRes = await db.execute(sql`
          SELECT sum(
            CAST(si.quantity AS NUMERIC) * COALESCE(NULLIF(CAST(ii.unit_price AS NUMERIC), 0), NULLIF(CAST(ii.selling_price AS NUMERIC), 0), CAST(si.price AS NUMERIC), 0)
          ) as cost
          FROM sale_items si
          JOIN sales s ON si.sale_id = s.id
          LEFT JOIN inventory_items ii ON (
            (si.product_id IS NOT NULL AND si.product_id = ii.id)
            OR (si.service_id IS NOT NULL AND (
              si.service_id::text = ii.id::text
              OR si.service_id::text = ('inv_' || ii.id::text)
            ))
          )
          WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE'
                AND s.created_at >= ${startIso}::timestamptz AND s.created_at <= ${endIso}::timestamptz
                AND si.is_internal = false
                AND (ii.id IS NOT NULL OR si.product_id IS NOT NULL OR (si.service_id IS NOT NULL AND si.service_id::text LIKE 'inv_%'))
        `);
        const retailProductCogs = Number((productCogsRes.rows[0] as any)?.cost || 0);

        // Internal Salon Consumables / Stock-Out value for the period
        const stockOutRes = await db.execute(sql`
          SELECT sum(CAST(it.quantity AS NUMERIC) * COALESCE(NULLIF(CAST(ii.unit_price AS NUMERIC), 0), CAST(ii.selling_price AS NUMERIC), 0)) as cost
          FROM inventory_transactions it
          JOIN inventory_items ii ON it.item_id = ii.id
          WHERE it.salon_id = ${salonId}::uuid AND it.type = 'OUT'
                AND it.date >= ${startIso}::timestamptz AND it.date <= ${endIso}::timestamptz
        `);
        const internalStockOutCost = Number((stockOutRes.rows[0] as any)?.cost || 0);

        productCogs = retailProductCogs + internalStockOutCost;
        totalInventoryCost = productCogs; // Maintain backward compatibility for totalInventoryCost as COGS

        // Calculate Stock-In received value for the period (Purchases volume)
        const stockInRes = await db.execute(sql`
          SELECT sum(CAST(it.quantity AS NUMERIC) * COALESCE(NULLIF(CAST(ii.unit_price AS NUMERIC), 0), CAST(ii.selling_price AS NUMERIC), 0)) as cost
          FROM inventory_transactions it
          JOIN inventory_items ii ON it.item_id = ii.id
          WHERE it.salon_id = ${salonId}::uuid AND it.type = 'IN'
                AND it.date >= ${startIso}::timestamptz AND it.date <= ${endIso}::timestamptz
        `);
        stockPurchasesValue = Number((stockInRes.rows[0] as any)?.cost || 0);

        // Fetch products sold/utilized details
        const soldItemsRes = await db.execute(sql`
          SELECT COALESCE(ii.id, si.product_id, si.service_id) as id, COALESCE(ii.name, 'Retail Item') as name, sum(CAST(si.quantity AS NUMERIC)) as quantity, 
                 sum(CAST(si.quantity AS NUMERIC) * COALESCE(NULLIF(CAST(ii.unit_price AS NUMERIC), 0), NULLIF(CAST(ii.selling_price AS NUMERIC), 0), CAST(si.price AS NUMERIC), 0)) as cost
          FROM sale_items si
          JOIN sales s ON si.sale_id = s.id
          LEFT JOIN inventory_items ii ON (
            (si.product_id IS NOT NULL AND si.product_id = ii.id)
            OR (si.service_id IS NOT NULL AND (
              si.service_id::text = ii.id::text
              OR si.service_id::text = ('inv_' || ii.id::text)
            ))
          )
          WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE'
                AND s.created_at >= ${startIso}::timestamptz AND s.created_at <= ${endIso}::timestamptz
                AND si.is_internal = false
                AND (ii.id IS NOT NULL OR si.product_id IS NOT NULL OR (si.service_id IS NOT NULL AND si.service_id::text LIKE 'inv_%'))
          GROUP BY COALESCE(ii.id, si.product_id, si.service_id), COALESCE(ii.name, 'Retail Item')
        `);

        utilizedStockItems = (soldItemsRes.rows as any[]).map(r => {
          utilizedStockQty += Number(r.quantity || 0);
          return {
            itemId: r.id,
            name: r.name,
            quantityUtilized: Number(r.quantity || 0),
            cost: Number(r.cost || 0)
          };
        });

        // Fetch all inventory items currently available in the salon
        const availableRes = await db.select({
          id: inventoryItems.id,
          name: inventoryItems.name,
          stockQuantity: inventoryItems.stockQuantity
        }).from(inventoryItems).where(eq(inventoryItems.salonId, salonId as string));

        totalStockAvailable = availableRes.reduce((sum: number, item: any) => sum + Number(item.stockQuantity || 0), 0);
      }
    } catch (err) {
      console.error('[Reports] Product COGS Query Error:', err);
    }

    const totalSales = Number(totalSalesResult[0]?.totalPaid || 0);
    const totalBillings = Number(totalSalesResult[0]?.totalBillings || 0);
    const fullTax = Number(totalSalesResult[0]?.tax || 0);
    const collectedTax = Number(totalSalesResult[0]?.collectedTax || 0);
    const totalCommission = totalCommissionVal;
    const totalExpenses = effectiveStaffId ? 0 : Number(totalExpensesResult[0]?.total || 0);

    // 2. Deductions and Advances
    let totalSalaryDeductions = 0;
    let totalAdvances = 0;
    let deductionsList: any[] = [];

    try {
      const deductionsRes = await db.select({
        total: sql<number>`SUM(CASE WHEN type = 'DEDUCTION' THEN amount ELSE 0 END)`,
        advances: sql<number>`SUM(CASE WHEN type = 'ADVANCE' THEN amount ELSE 0 END)`
      }).from(salaryDeductions).where(and(
        eq(salaryDeductions.salonId, salonId as string),
        effectiveStaffId ? eq(salaryDeductions.staffId, effectiveStaffId) : undefined,
        gte(salaryDeductions.date, startStr),
        lte(salaryDeductions.date, endStr)
      ));

      totalSalaryDeductions = Number(deductionsRes[0]?.total || 0);
      totalAdvances = Number(deductionsRes[0]?.advances || 0);
    } catch (err) {
      console.error('[Reports] Deductions Query Error:', err);
    }
    
    const cappedDeductionsAmount = effectiveStaffId 
      ? Math.min(totalSalaryDeductions, (totalSalaryPortion + totalCommission) * 0.5)
      : totalSalaryDeductions;
    
    const calculatedNetStaffPay = (totalSalaryPortion + totalCommission) - cappedDeductionsAmount;
    
    // Note: profit is recalculated below after totalPurchaseVolume and clientPayments are aggregated
    let profit = effectiveStaffId
      ? calculatedNetStaffPay
      : 0;

    let netEarningsValue = effectiveStaffId ? (calculatedNetStaffPay - totalAdvances) : profit;
    
    // 2b. Ledger Payments (Money In/Out)
    let ledgerIn = 0;
    let ledgerOut = 0;
    let clientPayments = 0;
    let onlinePayments = 0;
    let vendorPayments = 0;
    let periodCreditPurchases = 0;
    let totalPurchaseVolume = 0;
    let totalVendorPurchasesPaid = 0;
    
    // Global Balances (Current Status)
    let globalReceivables = 0;
    let globalPayables = 0;

    try {
      // 1. Get Global Status (client & vendor balances)

      // 2. Global Status
      const clientBalRes = await db.select({ total: sum(clients.balance) }).from(clients).where(eq(clients.salonId, salonId as string));
      globalReceivables = Number(clientBalRes[0]?.total || 0);

      const vendorBalRes = await db.select({ total: sum(vendors.balance) }).from(vendors).where(eq(vendors.salonId, salonId as string));
      // Since our new logic is Negative = We owe them, Payable = ABS(balance) if balance < 0
      globalPayables = Math.abs(Math.min(0, Number(vendorBalRes[0]?.total || 0)));

      // 3. Ledger Entries for the period (excluding voided sales)
      const ledgerRes = await db.select({
        type: ledgerEntries.type,
        category: ledgerEntries.category,
        isClient: sql<boolean>`${ledgerEntries.clientId} IS NOT NULL`,
        isVendor: sql<boolean>`${ledgerEntries.vendorId} IS NOT NULL`,
        isPurchase: sql<boolean>`${ledgerEntries.purchaseId} IS NOT NULL`,
        isOnline: isOnlineSql,
        total: sum(ledgerEntries.amount)
      }).from(ledgerEntries)
        .leftJoin(sales, eq(ledgerEntries.saleId, sales.id))
        .where(and(
          eq(ledgerEntries.salonId, salonId as string),
          sql`COALESCE(${ledgerEntries.date}, ${ledgerEntries.createdAt}, ${sales.createdAt}) >= ${start}`,
          sql`COALESCE(${ledgerEntries.date}, ${ledgerEntries.createdAt}, ${sales.createdAt}) <= ${end}`,
          sql`(${ledgerEntries.saleId} IS NULL OR ${sales.status} != 'VOID')`
        )).groupBy(
          ledgerEntries.type,
          ledgerEntries.category,
        sql`${ledgerEntries.clientId} IS NOT NULL`,
        sql`${ledgerEntries.vendorId} IS NOT NULL`,
        sql`${ledgerEntries.purchaseId} IS NOT NULL`,
        isOnlineSql
      );

      let anonymousCashPurchases = 0;
      let anonymousOnlinePurchases = 0;
      let cashClientPayments = 0;
      let onlineClientPayments = 0;
      let cashVendorPayments = 0;
      let onlineVendorPayments = 0;

      ledgerRes.forEach(r => {
        const amt = Number(r.total || 0);
        
        // General Cash Inflows (moneyIn)
        if (r.category === 'PAYMENT' && r.type === 'DEBIT' && !r.isVendor) {
          if (!r.isOnline) ledgerIn += amt;
        } else if (r.category === 'STAFF_DEDUCTION' && r.type === 'CREDIT') {
          if (!r.isOnline) ledgerIn += amt;
        } else if (r.category === 'RECONCILIATION_ADJUSTMENT' && r.type === 'CREDIT') {
          if (!r.isOnline) ledgerIn += amt;
        }
        
        // General Cash Outflows (moneyOut)
        if (r.category === 'EXPENSE') {
          if (!r.isOnline) ledgerOut += amt;
        } else if (r.category === 'PURCHASE' && r.type === 'DEBIT' && !r.isVendor) {
          if (!r.isOnline) {
            ledgerOut += amt;
            anonymousCashPurchases += amt;
          } else {
            anonymousOnlinePurchases += amt;
          }
        } else if ((r.category === 'PAYMENT' || r.category === 'PURCHASE') && r.type === 'DEBIT' && r.isVendor) {
          if (!r.isOnline) {
            ledgerOut += amt;
            cashVendorPayments += amt;
          } else {
            onlineVendorPayments += amt;
          }
        } else if (r.category === 'STAFF_ADVANCE' && r.type === 'DEBIT') {
          if (!r.isOnline) ledgerOut += amt;
        } else if (r.category === 'VOID_REVERSAL' && r.type === 'CREDIT') {
          if (!r.isOnline) ledgerOut += amt;
        } else if (r.category === 'RECONCILIATION_ADJUSTMENT' && r.type === 'DEBIT') {
          if (!r.isOnline) ledgerOut += amt;
        }
        
        // Entity specific
        if (r.category === 'PAYMENT' && r.type === 'DEBIT' && !r.isVendor) {
          if (r.isOnline) onlineClientPayments += amt;
          else cashClientPayments += amt;
        }
        if (r.category === 'VOID_REVERSAL' && r.type === 'CREDIT' && !r.isVendor) {
          if (r.isOnline) onlineClientPayments -= amt;
          else cashClientPayments -= amt;
        }

        if (r.isVendor && r.type === 'DEBIT') vendorPayments += amt;

        // Credit purchase tracking (unpaid part)
        if (r.isPurchase && r.type === 'CREDIT') periodCreditPurchases += amt;
      });

      clientPayments = Math.max(0, cashClientPayments + onlineClientPayments);
      onlinePayments = Math.max(0, onlineClientPayments);

      totalVendorPurchasesPaid = vendorPayments + anonymousCashPurchases + anonymousOnlinePurchases;
      totalPurchaseVolume = totalVendorPurchasesPaid;
      const netSales = netServiceSales + netProductSales;
      const totalCollectedRevenue = Math.max(totalSales, clientPayments);
      const netCollectedRevenue = Math.max(0, totalCollectedRevenue - collectedTax);
      const effectiveRevenue = Math.max(netSales, netCollectedRevenue);

      if (!effectiveStaffId) {
        profit = effectiveRevenue - totalExpenses - productCogs;
        netEarningsValue = profit;
      }
    } catch (err) {
      console.error('[Reports] Ledger Summary Error:', err);
    }

    const netSales = netServiceSales + netProductSales;
    const totalCollectedRevenue = Math.max(totalSales, clientPayments);
    const netCollectedRevenue = Math.max(0, totalCollectedRevenue - collectedTax);
    const grossRevenue = Math.max(netSales, netCollectedRevenue);
    const grossProfit = grossRevenue - productCogs;

    // 3. Breakdown
    let breakdown: any[] = [];
    const validGroupBy = ['day', 'week', 'month', 'quarter'];
    const groupByParam = groupBy && validGroupBy.includes(groupBy as string) ? (groupBy as string) : 'month';
    const interval = groupByParam as 'day' | 'week' | 'month' | 'quarter';

    let salesBreakdown: any = { rows: [] };
    let internalBreakdown: any = { rows: [] };
    let collectionsBreakdown: any = { rows: [] };
    try {
      salesBreakdown = await db.execute(sql`
        SELECT date_trunc(${sql.raw("'" + interval + "'")}, s.created_at + (${offset} || ' minutes')::interval) as period, 
               sum(
                 CAST(si.price AS NUMERIC) * CAST(si.quantity AS NUMERIC) - COALESCE(CAST(si.discount_amount AS NUMERIC), 0)
               ) as total,
               sum(
                 CAST(si.commission_amount AS NUMERIC)
               ) as commission
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE' 
              AND s.created_at >= ${startIso}::timestamptz AND s.created_at <= ${endIso}::timestamptz
              AND si.is_internal = false
        ${effectiveStaffId ? sql`AND (si.staff_id = ${effectiveStaffId}::uuid OR (si.staff_id IS NULL AND s.staff_id = ${effectiveStaffId}::uuid))` : sql``}
        GROUP BY period
        ORDER BY period ASC
      `);

      // Collections breakdown (Cash & Online collected per period based on payment date)
      collectionsBreakdown = await db.execute(sql`
        SELECT date_trunc(${sql.raw("'" + interval + "'")}, COALESCE(l.date, l.created_at) + (${offset} || ' minutes')::interval) as period, 
               sum(CASE WHEN ${isOnlineSql} THEN CAST(l.amount AS NUMERIC) ELSE 0 END) as online_collected,
               sum(CASE WHEN NOT ${isOnlineSql} THEN CAST(l.amount AS NUMERIC) ELSE 0 END) as cash_collected,
               sum(CAST(l.amount AS NUMERIC)) as total_collected
        FROM ledger_entries l
        LEFT JOIN sales s ON l.sale_id = s.id
        WHERE l.salon_id = ${salonId}::uuid
              AND (s.id IS NULL OR s.status = 'ACTIVE')
              AND l.category = 'PAYMENT' AND l.type = 'DEBIT'
              AND l.vendor_id IS NULL
              AND COALESCE(l.date, l.created_at) >= ${startIso}::timestamptz AND COALESCE(l.date, l.created_at) <= ${endIso}::timestamptz
        ${effectiveStaffId ? sql`AND (l.staff_id = ${effectiveStaffId}::uuid OR (s.id IS NOT NULL AND s.staff_id = ${effectiveStaffId}::uuid))` : sql``}
        GROUP BY period
        ORDER BY period ASC
      `);

      // Get internal revenue breakdown to subtract
      internalBreakdown = await db.execute(sql`
        SELECT date_trunc(${sql.raw("'" + interval + "'")}, s.created_at + (${offset} || ' minutes')::interval) as period, 
               sum(CAST(si.price AS NUMERIC) * CAST(si.quantity AS NUMERIC)) as total
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE' 
              AND s.created_at >= ${startIso}::timestamptz AND s.created_at <= ${endIso}::timestamptz
              AND si.is_internal = true
              ${effectiveStaffId ? sql`AND (si.staff_id = ${effectiveStaffId}::uuid OR (si.staff_id IS NULL AND s.staff_id = ${effectiveStaffId}::uuid))` : sql``}
        GROUP BY period
      `);

      // Adjust main breakdown rows
      (salesBreakdown.rows as any[]).forEach(row => {
        const matchingInternal = (internalBreakdown.rows as any[]).find(ir => 
          normalizePeriod(ir.period) === normalizePeriod(row.period)
        );
        if (matchingInternal) {
          row.total = Math.max(0, Number(row.total || 0));
        }
      });
    } catch (err) {
      console.error('[Reports] Sales Breakdown Query Error:', err);
    }

    let expensesBreakdown: any = { rows: [] };
    let salariesBreakdown: any = { rows: [] };
    try {
      expensesBreakdown = effectiveStaffId ? { rows: [] } : await db.execute(sql`
        SELECT date_trunc(${sql.raw("'" + interval + "'")}, CAST(${expenses.date} AS DATE)) as period, sum(${expenses.amount}) as total
        FROM ${expenses}
        WHERE ${expenses.salonId} = ${salonId}::uuid AND CAST(${expenses.date} AS DATE) >= ${startStr} AND CAST(${expenses.date} AS DATE) <= ${endStr}
        GROUP BY period
        ORDER BY period ASC
      `);

      salariesBreakdown = effectiveStaffId ? { rows: [] } : await db.execute(sql`
        SELECT date_trunc(${sql.raw("'" + interval + "'")}, CAST(${expenses.date} AS DATE)) as period, sum(${expenses.amount}) as total
        FROM ${expenses}
        WHERE ${expenses.salonId} = ${salonId}::uuid AND ${expenses.category} = 'Salaries' AND CAST(${expenses.date} AS DATE) >= ${startStr} AND CAST(${expenses.date} AS DATE) <= ${endStr}
        GROUP BY period
        ORDER BY period ASC
      `);
    } catch (err) {
      console.error('[Reports] Expenses/Salaries Breakdown Query Error:', err);
    }

    let vendorPurchasesBreakdown: any = { rows: [] };
    try {
      vendorPurchasesBreakdown = effectiveStaffId ? { rows: [] } : await db.execute(sql`
        SELECT date_trunc(${sql.raw("'" + interval + "'")}, COALESCE(l.date, l.created_at) + (${offset} || ' minutes')::interval) as period,
               sum(CAST(l.amount AS NUMERIC)) as total
        FROM ledger_entries l
        WHERE l.salon_id = ${salonId}::uuid
          AND l.type = 'DEBIT'
          AND (
            (l.vendor_id IS NOT NULL) OR
            (l.category = 'PURCHASE')
          )
          AND COALESCE(l.date, l.created_at) >= ${startIso}::timestamptz AND COALESCE(l.date, l.created_at) <= ${endIso}::timestamptz
        GROUP BY period
        ORDER BY period ASC
      `);
    } catch (err) {
      console.error('[Reports] Vendor Purchases Breakdown Error:', err);
    }

    let inventoryBreakdownRows: any[] = [];
    let billedTaxRows: any[] = [];
    let taxBreakdownRows: any[] = [];
    if (!effectiveStaffId) {
      try {
        const invRes = await db.execute(sql`
          SELECT date_trunc(${sql.raw("'" + interval + "'")}, period_time) as period, 
                 sum(cost) as total
          FROM (
            SELECT (s.created_at + (${offset} || ' minutes')::interval) as period_time, 
                   CAST(si.quantity AS NUMERIC) * COALESCE(NULLIF(CAST(ii.unit_price AS NUMERIC), 0), NULLIF(CAST(ii.selling_price AS NUMERIC), 0), CAST(si.price AS NUMERIC), 0) as cost
            FROM sale_items si
            JOIN sales s ON si.sale_id = s.id
            LEFT JOIN inventory_items ii ON (
              (si.product_id IS NOT NULL AND si.product_id = ii.id)
              OR (si.service_id IS NOT NULL AND (
                si.service_id::text = ii.id::text
                OR si.service_id::text = ('inv_' || ii.id::text)
              ))
            )
            WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE'
                  AND s.created_at >= ${startIso}::timestamptz AND s.created_at <= ${endIso}::timestamptz
                  AND si.is_internal = false
                  AND (ii.id IS NOT NULL OR si.product_id IS NOT NULL OR (si.service_id IS NOT NULL AND si.service_id::text LIKE 'inv_%'))
            UNION ALL
            SELECT (it.date + (${offset} || ' minutes')::interval) as period_time,
                   CAST(it.quantity AS NUMERIC) * COALESCE(NULLIF(CAST(ii.unit_price AS NUMERIC), 0), CAST(ii.selling_price AS NUMERIC), 0) as cost
            FROM inventory_transactions it
            JOIN inventory_items ii ON it.item_id = ii.id
            WHERE it.salon_id = ${salonId}::uuid AND it.type = 'OUT'
                  AND it.date >= ${startIso}::timestamptz AND it.date <= ${endIso}::timestamptz
          ) cogs_sub
          GROUP BY period
          ORDER BY period ASC
        `);
        inventoryBreakdownRows = invRes.rows;
      } catch (err) {
        console.error('[Reports] Inventory COGS Breakdown Query Error:', err);
      }

      try {
        const billedTaxRes = await db.execute(sql`
          SELECT date_trunc(${sql.raw("'" + interval + "'")}, s.created_at + (${offset} || ' minutes')::interval) as period, 
                 sum(CAST(s.tax_amount AS NUMERIC)) as total_tax
          FROM sales s
          WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE'
                AND s.created_at >= ${startIso}::timestamptz AND s.created_at <= ${endIso}::timestamptz
          GROUP BY period
          ORDER BY period ASC
        `);
        billedTaxRows = billedTaxRes.rows;

        const taxRes = await db.execute(sql`
          SELECT date_trunc(${sql.raw("'" + interval + "'")}, l.date + (${offset} || ' minutes')::interval) as period, 
                 sum(CAST(s.tax_amount AS NUMERIC) * (CAST(l.amount AS NUMERIC) / NULLIF(CAST(s.total AS NUMERIC), 0))) as collected_tax
          FROM ledger_entries l
          JOIN sales s ON l.sale_id = s.id
          WHERE s.salon_id = ${salonId}::uuid AND s.status = 'ACTIVE'
                AND l.category = 'PAYMENT' AND l.type = 'DEBIT'
                AND l.date >= ${startIso}::timestamptz AND l.date <= ${endIso}::timestamptz
          GROUP BY period
          ORDER BY period ASC
        `);
        taxBreakdownRows = taxRes.rows;
      } catch (err) {
        console.error('[Reports] Tax Breakdown Query Error:', err);
      }
    }


    const periods = new Set([
      ...((salesBreakdown.rows as any[]) || []).map(r => normalizePeriod(r.period)),
      ...((collectionsBreakdown.rows as any[]) || []).map(r => normalizePeriod(r.period)),
      ...((internalBreakdown.rows as any[]) || []).map(r => normalizePeriod(r.period)),
      ...((expensesBreakdown.rows as any[]) || []).map(r => normalizePeriod(r.period)),
      ...((salariesBreakdown.rows as any[]) || []).map(r => normalizePeriod(r.period)),
      ...((vendorPurchasesBreakdown.rows as any[]) || []).map(r => normalizePeriod(r.period)),
      ...(inventoryBreakdownRows || []).map(r => normalizePeriod(r.period)),
      ...(billedTaxRows || []).map(r => normalizePeriod(r.period)),
      ...(taxBreakdownRows || []).map(r => normalizePeriod(r.period))
    ]);

    if (periods.size === 0 && start) periods.add(normalizePeriod(new Date(start.getTime() + offset * 60000)));

    const salaryPerPeriod = periods.size > 0 ? totalSalaryPortion / periods.size : 0;

    const salesMap = new Map(((salesBreakdown.rows as any[]) || []).map(r => [normalizePeriod(r.period), r]));
    const collectionsMap = new Map(((collectionsBreakdown.rows as any[]) || []).map(r => [normalizePeriod(r.period), r]));
    const internalMap = new Map(((internalBreakdown.rows as any[]) || []).map(r => [normalizePeriod(r.period), r]));
    const expensesMap = new Map(((expensesBreakdown.rows as any[]) || []).map(r => [normalizePeriod(r.period), r]));
    const vendorPurchasesMap = new Map(((vendorPurchasesBreakdown.rows as any[]) || []).map(r => [normalizePeriod(r.period), r]));
    const inventoryMap = new Map((inventoryBreakdownRows || []).map(r => [normalizePeriod(r.period), r]));
    const salariesMap = new Map(((salariesBreakdown.rows as any[]) || []).map(r => [normalizePeriod(r.period), r]));
    const billedTaxMap = new Map((billedTaxRows || []).map(r => [normalizePeriod(r.period), r]));
    const taxMap = new Map((taxBreakdownRows || []).map(r => [normalizePeriod(r.period), r]));

    breakdown = Array.from(periods).sort().map(p => {
      const s = salesMap.get(p);
      const col = collectionsMap.get(p);
      const internalVal = Number(internalMap.get(p)?.total || 0);
      const e = expensesMap.get(p);
      const vp = vendorPurchasesMap.get(p);
      const inv = inventoryMap.get(p);
      const sal = salariesMap.get(p);
      const bt = billedTaxMap.get(p);
      const t = taxMap.get(p);
      
      const sTotal = Number(s?.total || 0);
      const cashCol = Number(col?.cash_collected || 0);
      const onlineCol = Number(col?.online_collected || 0);
      const totalCol = Number(col?.total_collected || 0);
      const eTotal = Number(e?.total || 0);
      const vpTotal = Number(vp?.total || 0);
      const cTotal = Number(s?.commission || 0);
      const cogsTotal = Number(inv?.total || 0);
      const salPaidTotal = Number(sal?.total || 0);
      const collectedTaxVal = Number(t?.collected_tax || 0);
      const fullTaxVal = Number(bt?.total_tax || 0);

      return {
        period: p,
        sales: sTotal,
        cashCollected: cashCol,
        onlineCollected: onlineCol,
        totalCollected: totalCol,
        expenses: eTotal,
        vendorPurchases: vpTotal,
        commission: cTotal,
        inventory: cogsTotal,
        productCogs: cogsTotal,
        tax: collectedTaxVal || fullTaxVal,
        collectedTax: collectedTaxVal,
        fullTax: fullTaxVal,
        allocatedSalary: salaryPerPeriod,
        salaryPaid: salPaidTotal,
        profit: effectiveStaffId 
          ? (cTotal + salaryPerPeriod) 
          : (sTotal - eTotal - cogsTotal - cTotal)
      };
    });

    // 4. Metadata and Attendance
    let attendanceDetails: any = null;
    if (effectiveStaffId) {
      try {
        const countsResult = await db.select({ 
          status: attendance.status, 
          count: sql<number>`COUNT(*)` 
        }).from(attendance).where(and(
          eq(attendance.staffId, effectiveStaffId), 
          eq(attendance.salonId, salonId as string), 
          ne(attendance.approvalStatus, 'REJECTED'), 
          gte(attendance.date, startStr), 
          lte(attendance.date, endStr)
        )).groupBy(attendance.status);

        attendanceDetails = { presentDays: 0, absentDays: 0, leaveDays: 0, lateDays: 0, attendanceList: [] };
        (countsResult || []).forEach(r => {
          if (r.status === 'PRESENT') attendanceDetails.presentDays = Number(r.count || 0);
          if (r.status === 'ABSENT') attendanceDetails.absentDays = Number(r.count || 0);
          if (r.status === 'LEAVE') attendanceDetails.leaveDays = Number(r.count || 0);
          if (r.status === 'LATE') attendanceDetails.lateDays = Number(r.count || 0);
        });

        const attendanceRecords = await db.query.attendance.findMany({
          where: and(
            eq(attendance.staffId, effectiveStaffId), 
            eq(attendance.salonId, salonId as string), 
            gte(attendance.date, startStr), 
            lte(attendance.date, endStr), 
            ne(attendance.approvalStatus, 'REJECTED')
          ),
          orderBy: (attendance, { desc }) => [desc(attendance.date)],
        });
        attendanceDetails.attendanceList = (attendanceRecords || []).map(a => ({ 
          date: a.date, 
          status: a.status, 
          checkIn: a.checkIn, 
          checkOut: a.checkOut 
        }));

        const deductionsListRes = await db.query.salaryDeductions.findMany({
          where: and(
            eq(salaryDeductions.staffId, effectiveStaffId), 
            eq(salaryDeductions.salonId, salonId as string), 
            gte(salaryDeductions.date, startStr), 
            lte(salaryDeductions.date, endStr)
          ),
          orderBy: (sd, { desc }) => [desc(sd.date), desc(sd.createdAt)]
        });
        deductionsList = (deductionsListRes || []).map((d: any) => ({ 
          type: d.type || 'DEDUCTION', 
          amount: Number(d.amount || 0), 
          reason: d.reason || '', 
          date: d.date 
        })).filter((d: any) => d.amount !== 0);
      } catch (err) {
        console.error('[Reports] Attendance/Deductions Detail Error:', err);
      }
    }

    let drawerBalances: any = null;
    try {
      drawerBalances = await getSalonGallaBalances(salonId as string, start, end);
    } catch (gErr) {
      console.error('[Reports] Drawer Balances Error:', gErr);
    }

    const baseResponse = {
      period: { start, end },
      totalSales,
      totalBillings,
      onlinePayments,
      onlineBreakdown: drawerBalances?.onlineBreakdown || {},
      productCogs,
      totalInventoryCost: productCogs,
      stockPurchasesValue,
      grossProfit,
      saleCount: Number(totalSalesResult[0]?.count || 0),
      totalExpenses: effectiveStaffId ? 0 : totalExpenses,
      vendorExpenses: effectiveStaffId ? 0 : totalVendorPurchasesPaid,
      totalExpensesWithVendor: effectiveStaffId ? 0 : (totalExpenses + totalVendorPurchasesPaid),
      commission: totalCommission,
      totalTax: fullTax,
      collectedTax: collectedTax,
      profit,
      breakdown,
      attendanceDetails,
      deductionsList,
      staffAttendanceSummary,
      monthlyStaffAttendance,
      dailyStaffAttendance,
      utilizedStockQty,
      totalStockAvailable,
      utilizedStockItems,
      suggestedAttendanceDeductions: Number(totalAttendanceDeductions || 0),
      suggestedDeductionsList: attendanceDeductionsList,
      salaryDeductions: Number(cappedDeductionsAmount || 0),
      advances: Number(totalAdvances || 0),
      netEarnings: Number(netEarningsValue || 0),
      ledgerIn,
      ledgerOut,
      clientPayments,
      vendorPayments,
      periodCreditPurchases,
      totalPurchaseVolume,
      totalInternalUse: effectiveStaffId ? 0 : totalInternalRevenue,
      globalReceivables,
      globalPayables,
      drawerBalances
    };

    res.json(effectiveStaffId ? {
      ...baseResponse,
      baseSalary: Number(totalSalaryPortion || 0),
      totalSalaryPaid: Number(totalSalaryPaid || 0),
      netServiceSales,
      netProductSales,
      totalDiscountGiven: Number(totalSalesResult[0]?.totalDiscountGiven || 0),
    } : {
      ...baseResponse,
      totalSalaryCosts: Number(totalSalaryPortion || 0),
      totalSalaryPaid: Number(totalSalaryPaid || 0),
      netServiceSales,
      netProductSales,
      totalDiscountGiven: Number(totalSalesResult[0]?.totalDiscountGiven || 0),
    });

  } catch (error: any) {
    console.error('[Reports] Critical Summary Error:', error);
    res.status(500).json({ 
      message: `Error generating report: ${error.message || error}`, 
      error: error.message,
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined 
    });
  }
});

// New Endpoint: Top Services
router.get('/top-services', authenticate, authorize(['SUPER_ADMIN', 'OWNER', 'STAFF']), checkSubscription, async (req: AuthRequest, res) => {
  let salonId = req.user.salonId;
  if (req.user.role === 'SUPER_ADMIN') {
    salonId = req.query.salonId as string;
  }
  if (!salonId) return res.status(403).json({ message: 'Unauthorized: No salon ID' });
  const { startDate, endDate, limit = '5' } = req.query;

  try {
    let start: Date, end: Date;
    if (!startDate || !endDate) {
      const [defaultStart, defaultEnd] = getDefaultDateRange();
      start = startDate ? new Date(startDate as string) : defaultStart;
      end = endDate ? new Date(endDate as string) : defaultEnd;
    } else {
      start = new Date(startDate as string);
      end = new Date(endDate as string);
    }
    if (!(startDate as string)?.includes('T')) start.setHours(0, 0, 0, 0);
    if (!(endDate as string)?.includes('T')) end.setHours(23, 59, 59, 999);
    
    const startIso = start.toISOString();
    const endIso = end.toISOString();
    
    const limitNum = parseInt(limit as string, 10);
    const safeLimit = Math.min(!isNaN(limitNum) && limitNum > 0 ? limitNum : 5, 100);

    let effectiveStaffId = req.user.role === 'STAFF' ? (await db.query.staff.findFirst({ where: and(eq(staff.userId, req.user.id as string), eq(staff.salonId, salonId as string)) }))?.id : req.query.staffId as string;

    const topServices = await db.execute(sql`
      SELECT COALESCE(s.name, i.name, 'Unknown') as name, 
             count(si.id) as count, 
             sum(
               (CAST(si.price AS NUMERIC) * CAST(si.quantity AS NUMERIC) - COALESCE(CAST(si.discount_amount AS NUMERIC), 0)) * 
               (CAST(l.amount AS NUMERIC) / NULLIF(CAST(sa.total AS NUMERIC), 0))
             ) as revenue
      FROM ledger_entries l
      JOIN sales sa ON l.sale_id = sa.id
      JOIN sale_items si ON si.sale_id = sa.id
      LEFT JOIN services s ON si.service_id = s.id
      LEFT JOIN inventory_items i ON si.product_id = i.id
      WHERE sa.salon_id = ${salonId}::uuid AND sa.status = 'ACTIVE'
            AND l.category = 'PAYMENT' AND l.type = 'DEBIT'
            AND l.date >= ${startIso}::timestamptz AND l.date <= ${endIso}::timestamptz
            AND CAST(si.price AS NUMERIC) > 0
            AND CAST(si.quantity AS NUMERIC) > 0
            AND si.is_internal = false
            ${effectiveStaffId ? sql`AND (si.staff_id = ${effectiveStaffId}::uuid OR (si.staff_id IS NULL AND sa.staff_id = ${effectiveStaffId}::uuid))` : sql``}
      GROUP BY 1
      ORDER BY revenue DESC
      LIMIT ${safeLimit}
    `);


    res.json(topServices.rows);
  } catch (error) {
    console.error('Top services error:', error);
    res.status(500).json({ message: 'Error fetching top services' });
  }
});

router.get('/export', authenticate, authorize(['SUPER_ADMIN', 'OWNER']), checkSubscription, async (req: AuthRequest, res) => {
  let salonId = req.user.salonId;
  if (req.user.role === 'SUPER_ADMIN') {
    salonId = req.query.salonId as string;
  }
  if (!salonId) return res.status(403).json({ message: 'Unauthorized: No salon ID' });
  const { startDate, endDate, staffId: queryStaffId } = req.query;

  try {
    let start: Date, end: Date;
    if (!startDate || !endDate) {
      const [defaultStart, defaultEnd] = getDefaultDateRange();
      start = startDate ? new Date(startDate as string) : defaultStart;
      end = endDate ? new Date(endDate as string) : defaultEnd;
    } else {
      start = new Date(startDate as string);
      end = new Date(endDate as string);
    }
    start.setHours(0, 0, 0, 0);
    end.setHours(23, 59, 59, 999);
    
    const startStr = `${start.getFullYear()}-${String(start.getMonth()+1).padStart(2, '0')}-${String(start.getDate()).padStart(2, '0')}`;
    const endStr = `${end.getFullYear()}-${String(end.getMonth()+1).padStart(2, '0')}-${String(end.getDate()).padStart(2, '0')}`;

    let salesWhere = and(
      eq(sales.salonId, salonId as string),
      eq(sales.status, 'ACTIVE'),
      gte(sales.createdAt, start),
      lte(sales.createdAt, end)
    );
    if (queryStaffId) salesWhere = and(salesWhere, eq(sales.staffId, queryStaffId as string))!;

    const salesQuery = await db.query.sales.findMany({
      where: salesWhere,
      orderBy: [desc(sales.createdAt)],
      with: {
        saleItems: {
          with: { service: true, product: true, staff: true }
        },
        staff: true,
        paymentAccount: true
      }
    });

    const csvRows = ['Date,Type,Amount,Description,Staff,Status'];
    salesQuery.forEach(sale => csvRows.push(`${sale.createdAt?.toISOString() || 'N/A'},Sale,${sale.total},Sale ID: ${sale.id},${sale.staff?.name || 'Unassigned'},${sale.status}`));

    const expensesData = await db.select().from(expenses).where(and(eq(expenses.salonId, salonId as string), gte(expenses.date, startStr), lte(expenses.date, endStr)));
    expensesData.forEach(expense => csvRows.push(`${expense.date},Expense,${expense.amount},${expense.name || expense.category || ''},ACTIVE`));

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=report_${startStr}_to_${endStr}.csv`);
    res.status(200).send(csvRows.join('\n'));
  } catch (error) {
    console.error('Export error:', error);
    res.status(500).json({ message: 'Error exporting report' });
  }
});

export default router;
