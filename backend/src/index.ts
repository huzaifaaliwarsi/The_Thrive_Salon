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
app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', environment: process.env.NODE_ENV, database: process.env.NODE_ENV === 'production' ? 'configured' : 'thrive_local' });
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
if (require.main === module) {
  const port = Number(process.env.PORT || 3000);
  app.listen(port, process.env.NODE_ENV === 'production' ? '0.0.0.0' : '127.0.0.1', () => console.log(`API ready at http://127.0.0.1:${port} (${process.env.NODE_ENV || 'development'})`));
}
export default app;
