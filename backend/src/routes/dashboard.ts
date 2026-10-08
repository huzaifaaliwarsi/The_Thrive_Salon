import { Router } from 'express';
import { db } from '../db';
import { sales, staff, services, inventoryItems, appointments, salons, saleItems, ledgerEntries } from '../db/schema';
import { authenticate, AuthRequest } from '../middleware/auth';
import { checkSubscription } from '../middleware/subscription';
import { sql, eq, and, gte, lte, sum } from 'drizzle-orm';
import { getSalonGallaBalances, isOnlineSql } from '../utils/ledger';

const router = Router();

router.get('/metrics', authenticate, checkSubscription, async (req: AuthRequest, res) => {
  try {
    let salonId = req.user.salonId;
    if (req.user.role === 'SUPER_ADMIN') {
      salonId = (req.query.salonId as string) || req.user.salonId;
      if (!salonId) {
        const firstSalon = await db.query.salons.findFirst();
        if (firstSalon) {
          salonId = firstSalon.id;
        }
      }
    }
    if (!salonId) {
      return res.status(400).json({ message: 'Branch (salonId) is required' });
    }
    let staffId: string | undefined;

    if (req.user.role === 'STAFF') {
      const staffRecord = await db.query.staff.findFirst({
        where: and(eq(staff.userId, req.user.id as string), eq(staff.salonId, salonId as string))
      });
      if (staffRecord) staffId = staffRecord.id;
    }
    
    // Total Sales Metrics
    let totalSalesWhere = and(
      eq(sales.salonId, salonId as string),
      sql`${sales.status} != 'VOID'`,
      sql`${sales.status} != 'DRAFT'`
    );
    if (staffId) {
      totalSalesWhere = and(totalSalesWhere, eq(sales.staffId, staffId));
    }

    const totalSalesResult = await db.select({
      total: sql<string>`sum(CAST(${sales.amountPaid} AS NUMERIC))`,
    }).from(sales).where(totalSalesWhere);

    const salesChannelResult = await db.select({
      isOnline: isOnlineSql,
      total: sum(ledgerEntries.amount)
    }).from(ledgerEntries)
      .leftJoin(sales, eq(ledgerEntries.saleId, sales.id))
      .where(and(
        eq(ledgerEntries.salonId, salonId as string),
        eq(ledgerEntries.category, 'PAYMENT'),
        eq(ledgerEntries.type, 'DEBIT'),
        sql`${ledgerEntries.vendorId} IS NULL`,
        sql`(${ledgerEntries.saleId} IS NULL OR ${sales.status} != 'VOID')`,
        staffId ? eq(ledgerEntries.staffId, staffId) : undefined
      ))
      .groupBy(isOnlineSql);

    let dashCashSales = 0;
    let dashOnlineSales = 0;

    salesChannelResult.forEach(r => {
      const amt = Number(r.total || 0);
      if (r.isOnline) {
        dashOnlineSales += amt;
      } else {
        dashCashSales += amt;
      }
    });

    // Use a 1-year window matching typical Galla Summary usage (prevents old historical
    // negative data from clamping the balance to 0 on the dashboard)
    const gallaEnd = new Date();
    gallaEnd.setHours(23, 59, 59, 999);
    const gallaStart = new Date();
    gallaStart.setDate(gallaStart.getDate() - 365);
    gallaStart.setHours(0, 0, 0, 0);

    const gallaBalances = await getSalonGallaBalances(salonId as string, gallaStart, gallaEnd);

    const effectiveCashBalance = gallaBalances.cashBalance;
    const effectiveOnlineBalance = gallaBalances.onlineBalance;
    const onlineBreakdown = gallaBalances.onlineBreakdown || {};
    const cashSalesFinal = dashCashSales;
    const onlineSalesFinal = dashOnlineSales;
    const finalTotal = cashSalesFinal + onlineSalesFinal;

    const staffCountResult = await db.select({
      count: sql<number>`count(${staff.id})`,
    }).from(staff).where(eq(staff.salonId, salonId as string));

    const serviceCountResult = await db.select({
      count: sql<number>`count(${services.id})`,
    }).from(services).where(and(eq(services.salonId, salonId as string), eq(services.isActive, 'true')));

    // Growth Metrics (Last 30 days vs previous 30 days)
    const now = new Date();
    const thirtyDaysAgo = new Date(now);
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    const sixtyDaysAgo = new Date(now);
    sixtyDaysAgo.setDate(sixtyDaysAgo.getDate() - 60);

    const currentPeriodSales = await db.select({
      total: sql<string>`sum(CAST(${sales.amountPaid} AS NUMERIC))`,
    }).from(sales).where(and(
      totalSalesWhere,
      gte(sales.createdAt, thirtyDaysAgo)
    ));

    const previousPeriodSales = await db.select({
      total: sql<string>`sum(CAST(${sales.amountPaid} AS NUMERIC))`,
    }).from(sales).where(and(
      totalSalesWhere,
      gte(sales.createdAt, sixtyDaysAgo),
      lte(sales.createdAt, thirtyDaysAgo)
    ));

    // Internal use for current period
    const currentInternalRes = await db.select({
      total: sql<string>`sum(${saleItems.price}::numeric * ${saleItems.quantity}::numeric)`
    }).from(saleItems)
      .innerJoin(sales, eq(saleItems.saleId, sales.id))
      .where(and(
        eq(sales.salonId, salonId as string),
        eq(sales.status, 'ACTIVE'),
        eq(saleItems.isInternal, true),
        gte(sales.createdAt, thirtyDaysAgo),
        staffId ? eq(sales.staffId, staffId) : undefined
      ));

    // Internal use for previous period
    const previousInternalRes = await db.select({
      total: sql<string>`sum(${saleItems.price}::numeric * ${saleItems.quantity}::numeric)`
    }).from(saleItems)
      .innerJoin(sales, eq(saleItems.saleId, sales.id))
      .where(and(
        eq(sales.salonId, salonId as string),
        eq(sales.status, 'ACTIVE'),
        eq(saleItems.isInternal, true),
        gte(sales.createdAt, sixtyDaysAgo),
        lte(sales.createdAt, thirtyDaysAgo),
        staffId ? eq(sales.staffId, staffId) : undefined
      ));

    const currentTotal = Math.max(0, parseFloat(currentPeriodSales[0]?.total || '0'));
    const previousTotal = Math.max(0, parseFloat(previousPeriodSales[0]?.total || '0'));
    
    let recentGrowth = 0;
    if (previousTotal > 0) {
      recentGrowth = ((currentTotal - previousTotal) / previousTotal) * 100;
    } else if (currentTotal > 0) {
      recentGrowth = 100;
    }

    // Inventory Alerts
    const oneMonthFromNow = new Date();
    oneMonthFromNow.setMonth(oneMonthFromNow.getMonth() + 1);

    const lowStockItems = await db.query.inventoryItems.findMany({
      where: and(
        eq(inventoryItems.salonId, salonId as string),
        sql`${inventoryItems.stockQuantity}::numeric <= ${inventoryItems.lowStockThreshold}::numeric`
      )
    });

    const nearExpiryItems = await db.query.inventoryItems.findMany({
      where: and(
        eq(inventoryItems.salonId, salonId as string),
        sql`${inventoryItems.expiryDate} <= ${oneMonthFromNow.toISOString().split('T')[0]}`,
        sql`${inventoryItems.expiryDate} >= ${new Date().toISOString().split('T')[0]}`
      )
    });
    
    // Recent Activity (Sales & Appointments)
    const recentSales = await db.query.sales.findMany({
      where: totalSalesWhere,
      orderBy: (sales, { desc }) => [desc(sales.createdAt)],
      limit: 5
    });

    const recentAppointments = await db.query.appointments.findMany({
      where: and(
        eq(appointments.salonId, salonId as string),
        staffId ? eq(appointments.staffId, staffId) : undefined
      ),
      with: {
        service: true
      },
      orderBy: (appointments, { desc }) => [desc(appointments.createdAt)],
      limit: 5
    });

    const recentActivity = [
      ...recentSales.map(s => ({
        id: s.id,
        type: 'SALE',
        title: (s as any).customerName || s.customerPhone || 'Walk-in Client',
        subtitle: `Paid: PKR ${s.amountPaid} / Total: PKR ${s.total}`,
        timestamp: s.createdAt || new Date()
      })),
      ...recentAppointments.map(a => ({
        id: a.id,
        type: 'APPOINTMENT',
        title: a.customerName,
        subtitle: `${(a as any).service?.name || 'Service'} • ${a.status}`,
        timestamp: a.createdAt || new Date()
      }))
    ].sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()).slice(0, 5);

    res.json({
        totalSales: finalTotal,
        cashSales: Math.max(0, cashSalesFinal),
        onlineSales: Math.max(0, onlineSalesFinal),
        onlineBreakdown,
        staffCount: Number(staffCountResult[0]?.count || 0),
        serviceCount: Number(serviceCountResult[0]?.count || 0),
        recentGrowth: Number(recentGrowth.toFixed(1)),
      cashBalance: effectiveCashBalance,
      drawerBalance: effectiveCashBalance,
      onlineBalance: effectiveOnlineBalance,
      onlineDrawerBalance: effectiveOnlineBalance,
      drawerBalances: gallaBalances,
        inventoryAlerts: {
        lowStockCount: lowStockItems.length,
        nearExpiryCount: nearExpiryItems.length,
        lowStockItems: lowStockItems.map(i => ({ id: i.id, name: i.name, stock: i.stockQuantity })),
        nearExpiryItems: nearExpiryItems.map(i => ({ id: i.id, name: i.name, expiry: i.expiryDate }))
      },
      recentActivity
    });
  } catch (error) {
    console.error('Dashboard metrics error:', error);
    res.status(500).json({ message: 'Error fetching dashboard metrics' });
  }
});

export default router;
