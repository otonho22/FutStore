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
    const message =
      (data && typeof data === 'object' && 'error' in data && typeof data.error === 'string'
        ? data.error
        : null) ?? `HTTP ${res.status}`;
    throw new Error(message);
  }

  return data as T;
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}
