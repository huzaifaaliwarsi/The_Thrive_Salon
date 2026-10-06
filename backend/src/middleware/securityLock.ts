import { Request, Response, NextFunction } from 'express';
import { db } from '../db';
import { sql } from 'drizzle-orm';
import crypto from 'crypto';

// This placeholder will be replaced by the build script before obfuscation.
// DO NOT CHANGE THIS MANUALLY unless you are skipping the build script.
const AUTHORIZED_DOMAIN = '___AUTHORIZED_DOMAIN_PLACEHOLDER___';
const APP_SIGNATURE = '___APP_SIGNATURE_PLACEHOLDER___';

// A simple in-memory cache so we don't query the DB on every single request
let isLocked = false;
let verifiedWatermark = false;

export const securityLock = async (req: Request, res: Response, next: NextFunction) => {
  if (isLocked) {
    return res.status(403).json({ error: 'License verification failed. This application is locked.' });
  }

  try {
    // 1. Domain Check
    // If the authorized domain hasn't been set by the build script, we bypass (for local development)
    if (AUTHORIZED_DOMAIN !== '___AUTHORIZED_DOMAIN_PLACEHOLDER___' && AUTHORIZED_DOMAIN !== 'localhost') {
      const host = req.hostname;
      // Also check origin to prevent API spoofing from other frontends
      const origin = req.headers.origin;

      let isHostValid = host === AUTHORIZED_DOMAIN || host === `api.${AUTHORIZED_DOMAIN}` || host === `app.${AUTHORIZED_DOMAIN}` || host.endsWith('.vercel.app');
      
      if (origin) {
        try {
          const originHost = new URL(origin).hostname;
          if (originHost !== AUTHORIZED_DOMAIN && originHost !== `api.${AUTHORIZED_DOMAIN}` && originHost !== `app.${AUTHORIZED_DOMAIN}` && !originHost.endsWith('.vercel.app') && originHost !== 'localhost') {
            isHostValid = false;
          }
        } catch (e) {
          isHostValid = false;
        }
      }

      if (!isHostValid) {
        console.error(`SECURITY ALERT: Unauthorized host/origin detected. Expected: ${AUTHORIZED_DOMAIN}, Got Host: ${host}, Origin: ${origin}`);
        isLocked = true;
        return res.status(403).json({ error: 'Invalid license domain.' });
      }
    }

    // 2. Database Watermark Check (Only run once per boot)
    if (!verifiedWatermark) {
      // We use the salons table to store a hidden watermark in a dummy record or we can just check if the DB is the original one.
      // A better approach is to create a dedicated table, but to avoid migrations, we can store it in the 'is_suspended' column of a dummy salon, 
      // or simply rely on the fact that the DB URL matches what we expect (difficult to verify securely).
      // Let's create a hidden table dynamically if it doesn't exist to store the watermark.
      
      await db.execute(sql`
        CREATE TABLE IF NOT EXISTS _sys_config (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      `);

      const result = await db.execute(sql`SELECT value FROM _sys_config WHERE key = 'watermark'`);
      
      if (result.rows.length === 0) {
        // First run: Inject the watermark
        // The watermark is a hash of the app signature and some random salt. 
        // We will just store the expected app signature (which is injected at build time).
        await db.execute(sql`INSERT INTO _sys_config (key, value) VALUES ('watermark', ${APP_SIGNATURE})`);
        verifiedWatermark = true;
      } else {
        // Subsequent runs: Verify the watermark matches the built-in signature
        const storedWatermark = result.rows[0].value as string;
        
        // If the signature is a placeholder, it means we are in dev mode
        if (APP_SIGNATURE !== '___APP_SIGNATURE_PLACEHOLDER___') {
          if (storedWatermark !== APP_SIGNATURE) {
            console.error('SECURITY ALERT: Database watermark mismatch. This database belongs to a different installation.');
            isLocked = true;
            return res.status(403).json({ error: 'License verification failed (DB mismatch).' });
          }
        }
        verifiedWatermark = true;
      }
    }

    next();
  } catch (err) {
    console.error('Error in security lock:', err);
    // Fail closed
    isLocked = true;
    return res.status(500).json({ error: 'Internal Security Error' });
  }
};
