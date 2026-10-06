import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import * as schema from './schema';
import { databaseUrl } from '../config';

export const pool = new Pool({
  connectionString: databaseUrl,
  ssl: false
});

export const db = drizzle(pool, { schema });
