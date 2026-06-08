import { auth } from './firebase';

const BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:4000';
const LOCAL_ADMIN_KEY = 'pf_local_admin_v1';
const LOCAL_ADMIN_TOKEN = 'adm-adm123';

function hasLocalAdmin(): boolean {
  try {
    return !!localStorage.getItem(LOCAL_ADMIN_KEY);
  } catch {
    return false;
  }
}

async function authHeader(): Promise<Record<string, string>> {
  if (hasLocalAdmin()) {
    return { 'X-Local-Admin': LOCAL_ADMIN_TOKEN };
  }
  const user = auth.currentUser;
  if (!user) return {};
  const token = await user.getIdToken();
  return { Authorization: `Bearer ${token}` };
}

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(await authHeader()),
    ...((options.headers as Record<string, string>) ?? {}),
  };

  const res = await fetch(`${BASE_URL}${path}`, { ...options, headers });

  if (res.status === 204) return undefined as T;

  const text = await res.text();
  const data = text ? safeJson(text) : null;

  if (!res.ok) {
    throw new Error(extractError(data) ?? `HTTP ${res.status}`);
  }

  return data as T;
}

// Backend devolve `{ error: string }` ou `{ error: ZodFlatten }`. Esta função
// transforma ambos em uma mensagem legível pro alert do checkout/admin.
function extractError(data: unknown): string | null {
  if (!data || typeof data !== 'object') return null;
  const err = (data as { error?: unknown }).error;
  if (typeof err === 'string') return err;
  if (err && typeof err === 'object') {
    const flat = err as { formErrors?: string[]; fieldErrors?: Record<string, string[]> };
    const fieldMsgs = flat.fieldErrors
      ? Object.entries(flat.fieldErrors)
          .flatMap(([field, msgs]) => (msgs ?? []).map((m) => `${field}: ${m}`))
      : [];
    const all = [...(flat.formErrors ?? []), ...fieldMsgs];
    if (all.length > 0) return all.join(' · ');
  }
  return null;
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}
