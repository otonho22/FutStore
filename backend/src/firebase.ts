import 'dotenv/config';
import { initializeApp, cert, applicationDefault, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

function loadCredentials() {
  const path = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (path) {
    const abs = resolve(path);
    if (existsSync(abs)) {
      const json = JSON.parse(readFileSync(abs, 'utf8'));
      return cert(json);
    }
  }
  return applicationDefault();
}

if (!getApps().length) {
  initializeApp({ credential: loadCredentials() });
}

export const auth = getAuth();
