// Modo local: todas as chamadas a /api/* são resolvidas em memória/localStorage.
// Sem backend, sem rede, sem erros.
import { PRODUCTS, COUPONS } from '../data/products';
import type { Order, OrderStatus } from '../types';

const ORDERS_KEY = 'fs_orders_v1';

function readOrders(): Order[] {
  try {
    const raw = localStorage.getItem(ORDERS_KEY);
    return raw ? (JSON.parse(raw) as Order[]) : [];
  } catch {
    return [];
  }
}

function writeOrders(list: Order[]) {
  localStorage.setItem(ORDERS_KEY, JSON.stringify(list));
}

function cuid(prefix: string) {
  return prefix + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
}

function parseUrl(path: string): { pathname: string; params: URLSearchParams } {
  const url = new URL(path, 'http://x');
  return { pathname: url.pathname, params: url.searchParams };
}

async function delay<T>(value: T, ms = 80): Promise<T> {
  return new Promise((resolve) => setTimeout(() => resolve(value), ms));
}

// ============================================================================
// Roteador local
// ============================================================================
function handle(path: string, options: RequestInit): any {
  const { pathname, params } = parseUrl(path);
  const method = (options.method ?? 'GET').toUpperCase();
  const body = options.body ? JSON.parse(options.body as string) : null;

  // ---- USERS ----
  if (pathname === '/api/users/me') {
    // signup / get profile — no-op, retorna placeholder
    return {
      id: 'local-user',
      email: 'user@local',
      displayName: body?.displayName ?? 'Usuário',
      role: 'customer',
      acceptedTerms: !!body?.acceptedTerms,
      createdAt: new Date().toISOString(),
    };
  }

  // ---- PRODUCTS ----
  if (pathname === '/api/products' && method === 'GET') {
    const sort = params.get('sort') ?? 'createdAt';
    const limit = Math.min(Number(params.get('limit') ?? 50) || 50, 100);
    const category = params.get('category') ?? undefined;
    let list = PRODUCTS.filter((p) => p.active);
    if (category) list = list.filter((p) => p.category === category);
    if (sort === 'salesCount') {
      list = [...list].sort((a, b) => (b.salesCount ?? 0) - (a.salesCount ?? 0));
    } else if (sort === 'price') {
      list = [...list].sort((a, b) => b.price - a.price);
    }
    return list.slice(0, limit);
  }
  const productMatch = pathname.match(/^\/api\/products\/([^/]+)$/);
  if (productMatch && method === 'GET') {
    const id = productMatch[1];
    const p = PRODUCTS.find((x) => x.id === id);
    if (!p) throw new Error('Produto não encontrado');
    return p;
  }

  // ---- COUPONS ----
  const couponValidate = pathname.match(/^\/api\/coupons\/validate\/(.+)$/);
  if (couponValidate && method === 'GET') {
    const code = decodeURIComponent(couponValidate[1]).toUpperCase();
    const c = COUPONS.find((x) => x.code === code);
    if (!c) throw new Error('Cupom não encontrado');
    if (!c.active) throw new Error('Cupom inativo');
    if (new Date(c.validUntil) < new Date()) throw new Error('Cupom expirado');
    return c;
  }

  // ---- ORDERS ----
  if (pathname === '/api/orders' && method === 'POST') {
    const { items, couponCode, address, payment } = body;
    const subtotal = items.reduce(
      (s: number, i: any) => s + i.unitPrice * i.quantity,
      0,
    );
    let discount = 0;
    let appliedCoupon: string | null = null;
    if (couponCode) {
      const c = COUPONS.find((x) => x.code === couponCode.toUpperCase());
      if (c && c.active && new Date(c.validUntil) >= new Date()) {
        discount =
          c.type === 'percent' ? subtotal * (c.value / 100) : c.value;
        discount = Math.min(discount, subtotal);
        appliedCoupon = c.code;
      }
    }
    const shipping = 25;
    const total = Math.max(0, subtotal - discount + shipping);
    const now = new Date().toISOString();
    const order: Order = {
      id: cuid('o-'),
      userId: 'local-user',
      userEmail: null,
      items,
      couponCode: appliedCoupon,
      subtotal,
      discount,
      shipping,
      total,
      address,
      payment,
      status: 'pendente',
      statusHistory: [{ status: 'pendente', at: now }],
      trackingCode: null,
      createdAt: now,
    };
    const all = readOrders();
    all.unshift(order);
    writeOrders(all);
    return order;
  }

  if (pathname === '/api/orders/mine' && method === 'GET') {
    return readOrders();
  }

  const orderMatch = pathname.match(/^\/api\/orders\/([^/]+)$/);
  if (orderMatch && method === 'GET') {
    const id = orderMatch[1];
    const o = readOrders().find((x) => x.id === id);
    if (!o) throw new Error('Pedido não encontrado');
    return o;
  }

  // Admin endpoints (escondidos na sidebar) — retornam vazio em vez de erro
  if (pathname === '/api/orders' && method === 'GET') return [];
  if (pathname === '/api/coupons' && method === 'GET') return COUPONS;
  const couponStatus = pathname.match(/^\/api\/orders\/([^/]+)\/status$/);
  if (couponStatus && method === 'PATCH') {
    const id = couponStatus[1];
    const all = readOrders();
    const idx = all.findIndex((x) => x.id === id);
    if (idx < 0) throw new Error('Pedido não encontrado');
    const status = body.status as OrderStatus;
    all[idx] = {
      ...all[idx],
      status,
      statusHistory: [
        ...all[idx].statusHistory,
        { status, at: new Date().toISOString() },
      ],
    };
    writeOrders(all);
    return all[idx];
  }

  console.warn('[api local] rota não tratada:', method, pathname);
  return null;
}

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  try {
    const result = handle(path, options);
    return delay(result as T);
  } catch (e: any) {
    throw e instanceof Error ? e : new Error(String(e));
  }
}
