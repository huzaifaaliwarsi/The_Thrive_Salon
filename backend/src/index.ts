import './config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { pool } from './db';
import auth from './routes/auth';
import salons from './routes/salons';
import staff from './routes/staff';
import services from './routes/services';
import sales from './routes/sales';
import appointments from './routes/appointments';
import attendance from './routes/attendance';
import clients from './routes/clients';
import dashboard from './routes/dashboard';
import expenses from './routes/expenses';
import inventory from './routes/inventory';
import ledger from './routes/ledger';
import purchases from './routes/purchases';
import reports from './routes/reports';
import salary from './routes/salary';
import maintenance from './routes/maintenance';
import zkteco from './routes/zkteco';
import paymentAccounts from './routes/paymentAccounts';
import { securityLock } from './middleware/securityLock';

export const app = express();
app.use(helmet());
app.use(cors({ origin: process.env.NODE_ENV === 'production' ? process.env.FRONTEND_URL : /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/ }));
app.use(express.json({ limit: '10mb' }));
app.use(express.text({ type: 'text/plain' }));
// Safe auto-migration on startup to ensure all tables & columns exist
const runMigration = async () => {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.payment_accounts (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          salon_id UUID NOT NULL REFERENCES public.salons(id) ON DELETE CASCADE,
          account_name TEXT NOT NULL,
          account_title TEXT,
          account_number TEXT,
          iban TEXT,
          type TEXT DEFAULT 'BANK',
          is_active BOOLEAN DEFAULT true,
          created_at TIMESTAMPTZ DEFAULT now(),
          updated_at TIMESTAMPTZ DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS idx_payment_accounts_salon_id ON public.payment_accounts(salon_id);
      ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
      ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;
      ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'CASH';
      ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
      ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_breakdown TEXT;
      ALTER TABLE public.salary_deductions ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'CASH';
      ALTER TABLE public.salary_deductions ADD COLUMN IF NOT EXISTS payment_account_id UUID REFERENCES public.payment_accounts(id) ON DELETE SET NULL;
    `);
    console.log('[DB] Auto-migration check completed.');
    return { ok: true };
  } catch (err: any) {
    console.error('[DB] Auto-migration error:', err.message);
    return { ok: false, error: err.message };
  }
};
runMigration();

app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    const mig = await runMigration();
    res.json({
      status: 'ok',
      version: 'v2-multi-payment',
      environment: process.env.NODE_ENV,
      database: process.env.NODE_ENV === 'production' ? 'configured' : 'thrive_local',
      migration: mig.ok ? 'success' : mig.error
    });
  } catch { res.status(503).json({ status: 'database unavailable' }); }
});
if (process.env.NODE_ENV === 'production') app.use(securityLock);
for (const [name, router] of Object.entries({ 
  auth, salons, staff, services, sales, appointments, attendance, clients, 
  dashboard, expenses, inventory, ledger, purchases, reports, salary, maintenance, zkteco,
  'payment-accounts': paymentAccounts
})) {
  app.use(`/api/${name}`, router);
}
app.use((_req, res) => { res.status(404).json({ message: 'Endpoint not found' }); });
app.use((error: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(error.message);
  res.status(500).json({ message: 'Internal server error' });
});
const port = Number(process.env.PORT || 3000);
app.listen(port, () => console.log(`API ready at port ${port}`));
export default app;
