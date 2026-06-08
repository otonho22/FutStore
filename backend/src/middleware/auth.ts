import type { Request, Response, NextFunction } from 'express';
import { auth } from '../firebase.js';

export interface AuthedRequest extends Request {
  user?: { uid: string; email?: string; role?: string };
}

// Token compartilhado para o "admin padrão" (adm / adm123) — usado em
// ambientes de demonstração / acadêmicos para liberar todas as funcionalidades
// de admin sem precisar configurar uma conta Firebase com custom claim.
const LOCAL_ADMIN_TOKEN = 'adm-adm123';

function isLocalAdmin(req: Request): boolean {
  const header = req.headers['x-local-admin'];
  const value = Array.isArray(header) ? header[0] : header;
  return value === LOCAL_ADMIN_TOKEN;
}

export async function requireAuth(req: AuthedRequest, res: Response, next: NextFunction) {
  if (isLocalAdmin(req)) {
    req.user = { uid: 'local-admin', email: 'adm', role: 'admin' };
    return next();
  }

  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing bearer token' });
  }
  const token = header.slice(7);
  try {
    const decoded = await auth.verifyIdToken(token);
    req.user = {
      uid: decoded.uid,
      email: decoded.email,
      role: (decoded.role as string | undefined) ?? 'customer',
    };
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

export function requireAdmin(req: AuthedRequest, res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ error: 'Admin only' });
  }
  next();
}
