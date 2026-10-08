import path from 'path';
import dotenv from 'dotenv';

dotenv.config({ path: path.resolve(__dirname, '../.env') });

export function validateDatabaseUrl(value: string | undefined, local = process.env.NODE_ENV !== 'production'): string {
  if (!value) throw new Error('DATABASE_URL is required; no production fallback is configured.');
  const url = new URL(value);
  if (local && (url.hostname !== '127.0.0.1' && url.hostname !== 'localhost')) {
    throw new Error('Local mode only permits a local database connection (127.0.0.1 or localhost).');
  }
  return value;
}

export const databaseUrl = validateDatabaseUrl(process.env.DATABASE_URL);
