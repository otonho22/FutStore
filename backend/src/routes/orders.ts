import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { requireAuth, requireAdmin, type AuthedRequest } from '../middleware/auth.js';
import { sendMail } from '../lib/mailer.js';
import {
  orderConfirmationEmail,
  orderPaidEmail,
  orderShippedEmail,
  orderDeliveredEmail,
  type OrderEmailData,
} from '../lib/mail-templates.js';

const APP_URL = process.env.APP_URL ?? 'http://localhost:5173';

type EmailableStatus = 'pendente' | 'pago' | 'enviado' | 'entregue';

// Dispara o e-mail correspondente ao estado atual do pedido. Fire-and-forget:
// erros são engolidos pelo próprio mailer — pedido nunca quebra por causa
// de e-mail (se SMTP cair, internet cair, senha errar, etc.).
function emailForStatus(status: EmailableStatus, data: OrderEmailData) {
  switch (status) {
    case 'pendente': return orderConfirmationEmail(data, APP_URL);
    case 'pago':     return orderPaidEmail(data, APP_URL);
    case 'enviado':  return orderShippedEmail(data, APP_URL);
    case 'entregue': return orderDeliveredEmail(data, APP_URL);
  }
}

function fireOrderEmail(to: string | null | undefined, status: EmailableStatus, data: OrderEmailData) {
  if (!to) return; // pedido sem e-mail do comprador (admin local, p.ex.) — não tenta enviar
  const { subject, html } = emailForStatus(status, data);
  // .catch é redundante (mailer já trata) mas garante que nenhum reject vaze.
  sendMail({ to, subject, html }).catch((e) => console.error('[mailer] unhandled:', e?.message));
}

const router = Router();

// Aceita URL absoluta (http/https) ou path absoluto (/jerseys/...) — mesma
// regra usada em products.ts pra imagens locais servidas pelo frontend.
const imageRef = z.string().min(1).refine(
  (s) => s.startsWith('/') || /^https?:\/\//.test(s),
  { message: 'Deve ser URL http(s) ou caminho começando com /' },
);

const itemSchema = z.object({
  productId: z.string().min(1),
  name: z.string().min(1),
  size: z.string().min(1),
  unitPrice: z.number().positive(),
  quantity: z.number().int().positive(),
  imageUrl: imageRef.optional(),
});

const addressSchema = z.object({
  fullName: z.string().min(1),
  street: z.string().min(1),
  number: z.string().min(1),
  complement: z.string().optional(),
  city: z.string().min(1),
  state: z.string().min(2),
  zip: z.string().min(8),
});

const paymentSchema = z.object({
  method: z.enum(['credit_card', 'pix', 'boleto']),
  brand: z.string().optional(),
  last4: z.string().regex(/^\d{4}$/).optional(),
  holderName: z.string().optional(),
}).refine(
  (p) => p.method !== 'credit_card' || (!!p.last4 && !!p.holderName),
  { message: 'Cartão exige last4 e holderName' },
);

const orderSchema = z.object({
  items: z.array(itemSchema).min(1),
  couponCode: z.string().optional(),
  address: addressSchema,
  payment: paymentSchema,
});

const statusSchema = z.object({
  status: z.enum(['pendente', 'pago', 'enviado', 'entregue', 'cancelado']),
  trackingCode: z.string().optional(),
});

const SHIPPING_FIXED = Number(process.env.SHIPPING_FIXED ?? 25);

function serialize(o: any) {
  return {
    id: o.id,
    userId: o.userId,
    userEmail: o.userEmail,
    items: (o.items ?? []).map((i: any) => ({
      productId: i.productId,
      name: i.name,
      size: i.size,
      unitPrice: i.unitPrice,
      quantity: i.quantity,
      imageUrl: i.imageUrl ?? undefined,
    })),
    couponCode: o.couponCode,
    subtotal: o.subtotal,
    discount: o.discount,
    shipping: o.shipping,
    total: o.total,
    status: o.status,
    statusHistory: o.statusHistory ?? [],
    trackingCode: o.trackingCode,
    createdAt: o.createdAt,
    address: {
      fullName: o.addressFullName,
      street: o.addressStreet,
      number: o.addressNumber,
      complement: o.addressComplement ?? undefined,
      city: o.addressCity,
      state: o.addressState,
      zip: o.addressZip,
    },
    payment: {
      method: o.paymentMethod,
      brand: o.paymentBrand ?? undefined,
      last4: o.paymentLast4 ?? undefined,
      holderName: o.paymentHolderName ?? undefined,
    },
  };
}

router.post('/', requireAuth, async (req: AuthedRequest, res) => {
  const parsed = orderSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { items, couponCode, address, payment } = parsed.data;

  try {
    const created = await prisma.$transaction(async (tx) => {
      // 1) Garante que o user existe (pode ser primeiro pedido via login Google sem POST /users/me)
      await tx.user.upsert({
        where: { id: req.user!.uid },
        create: {
          id: req.user!.uid,
          email: req.user!.email ?? '',
          role: 'customer',
        },
        update: {},
      });

      // 2) Carrega produtos e valida estoque
      const productIds = items.map((i) => i.productId);
      const products = await tx.product.findMany({
        where: { id: { in: productIds } },
        include: { sizes: true },
      });

      let subtotal = 0;
      for (const item of items) {
        const product = products.find((p) => p.id === item.productId);
        if (!product) throw new Error(`Produto ${item.productId} não existe`);
        const sz = product.sizes.find((s) => s.size === item.size);
        if (!sz || sz.stock < item.quantity) {
          throw new Error(`Estoque insuficiente para ${product.name} tamanho ${item.size}`);
        }
        subtotal += item.unitPrice * item.quantity;
      }

      // 3) Cupom (opcional) — replica as regras de /coupons/validate/:code dentro da transação
      let discount = 0;
      let appliedCoupon: string | null = null;
      if (couponCode) {
        const code = couponCode.toUpperCase();
        const coupon = await tx.coupon.findUnique({ where: { code } });
        if (coupon && coupon.active && coupon.validUntil >= new Date()) {
          const userId = req.user!.uid;
          const notCancelled = { status: { not: 'cancelado' } as const };

          if (coupon.firstPurchaseOnly) {
            const prev = await tx.order.count({ where: { userId, ...notCancelled } });
            if (prev > 0) throw new Error('Cupom válido apenas na primeira compra');
          }
          if (coupon.maxUsesGlobal != null) {
            const used = await tx.order.count({ where: { couponCode: code, ...notCancelled } });
            if (used >= coupon.maxUsesGlobal) throw new Error('Cupom esgotado');
          }
          if (coupon.maxUsesPerCustomer != null) {
            const usedByUser = await tx.order.count({ where: { couponCode: code, userId, ...notCancelled } });
            if (usedByUser >= coupon.maxUsesPerCustomer) throw new Error('Limite de uso por cliente atingido');
          }

          discount = coupon.type === 'percent' ? subtotal * (coupon.value / 100) : coupon.value;
          discount = Math.min(discount, subtotal);
          appliedCoupon = code;
        }
      }

      const shipping = SHIPPING_FIXED;
      const total = Math.max(0, subtotal - discount + shipping);

      // 4) Decrementa estoque + incrementa salesCount
      for (const item of items) {
        await tx.productSize.update({
          where: { productId_size: { productId: item.productId, size: item.size } },
          data: { stock: { decrement: item.quantity } },
        });
        await tx.product.update({
          where: { id: item.productId },
          data: { salesCount: { increment: item.quantity } },
        });
      }

      // 5) Cria o pedido
      const now = new Date();
      const order = await tx.order.create({
        data: {
          userId: req.user!.uid,
          userEmail: req.user!.email ?? null,
          couponCode: appliedCoupon,
          subtotal,
          discount,
          shipping,
          total,
          status: 'pendente',
          trackingCode: null,
          statusHistory: [{ status: 'pendente', at: now.toISOString() }] as any,
          addressFullName: address.fullName,
          addressStreet: address.street,
          addressNumber: address.number,
          addressComplement: address.complement ?? null,
          addressCity: address.city,
          addressState: address.state,
          addressZip: address.zip,
          paymentMethod: payment.method,
          paymentBrand: payment.brand ?? null,
          paymentLast4: payment.last4 ?? null,
          paymentHolderName: payment.holderName ?? null,
          items: {
            create: items.map((i) => ({
              productId: i.productId,
              name: i.name,
              size: i.size,
              unitPrice: i.unitPrice,
              quantity: i.quantity,
              imageUrl: i.imageUrl ?? null,
            })),
          },
        },
        include: { items: true },
      });

      return order;
    });

    // Dispara e-mail de "Pedido recebido" — fire-and-forget, não bloqueia o response.
    fireOrderEmail(created.userEmail, 'pendente', {
      id: created.id,
      customerName: created.addressFullName,
      items: created.items.map((i) => ({
        name: i.name, size: i.size, quantity: i.quantity, unitPrice: i.unitPrice,
      })),
      total: created.total,
      city: created.addressCity,
      state: created.addressState,
    });

    res.status(201).json(serialize(created));
  } catch (e: any) {
    res.status(400).json({ error: e.message ?? 'Erro ao criar pedido' });
  }
});

router.get('/bi/summary', requireAuth, requireAdmin, async (req, res) => {
  const { from, to, category, status } = req.query as Record<string, string | undefined>;

  const where: any = {};
  if (from || to) {
    where.createdAt = {};
    if (from) where.createdAt.gte = new Date(from);
    if (to) {
      const end = new Date(to);
      end.setHours(23, 59, 59, 999);
      where.createdAt.lte = end;
    }
  }
  if (status) where.status = status;

  const orders = await prisma.order.findMany({
    where,
    include: { items: { include: { product: true } } },
  });

  const topProductsMap = new Map<string, { productId: string; name: string; qty: number; revenue: number }>();
  const bySizeMap = new Map<string, number>();
  const byCategoryMap = new Map<string, number>();
  let totalRevenue = 0;
  let totalOrders = 0;

  for (const order of orders) {
    let matched = 0;
    let revenueForOrder = 0;
    for (const item of order.items) {
      const itemCat = item.product?.category ?? 'Outros';
      if (category && itemCat !== category) continue;
      matched++;
      revenueForOrder += item.unitPrice * item.quantity;

      const cur = topProductsMap.get(item.productId);
      if (cur) { cur.qty += item.quantity; cur.revenue += item.unitPrice * item.quantity; }
      else topProductsMap.set(item.productId, {
        productId: item.productId, name: item.name,
        qty: item.quantity, revenue: item.unitPrice * item.quantity,
      });

      bySizeMap.set(item.size, (bySizeMap.get(item.size) ?? 0) + item.quantity);
      byCategoryMap.set(itemCat, (byCategoryMap.get(itemCat) ?? 0) + item.quantity);
    }
    if (matched > 0) {
      totalOrders++;
      totalRevenue += category ? revenueForOrder : order.total;
    }
  }

  res.json({
    topProducts: Array.from(topProductsMap.values()).sort((a, b) => b.qty - a.qty).slice(0, 10),
    bySize: Array.from(bySizeMap.entries()).map(([size, qty]) => ({ size, qty }))
      .sort((a, b) => b.qty - a.qty),
    byCategory: Array.from(byCategoryMap.entries()).map(([cat, qty]) => ({ category: cat, qty })),
    totalOrders,
    totalRevenue,
  });
});

// Rastreio público — qualquer um com o ID do pedido OU o código de rastreio
// dos Correios pode consultar. Retorna versão "magra" do pedido: sem totais,
// pagamento, e-mail do comprador, rua/número/CEP. Mostra só o que faz sentido
// pra tela de rastreamento: status, histórico, itens, cidade/UF de entrega.
router.get('/track/:code', async (req, res) => {
  const code = req.params.code.trim();
  if (code.length < 4) return res.status(400).json({ error: 'Código muito curto' });

  // Tenta primeiro por trackingCode (mais provável), depois por id do pedido.
  let order = await prisma.order.findFirst({
    where: { trackingCode: code },
    include: { items: true },
  });
  if (!order) {
    order = await prisma.order.findUnique({
      where: { id: code },
      include: { items: true },
    });
  }
  if (!order) return res.status(404).json({ error: 'Pedido não encontrado' });

  res.json({
    id: order.id,
    status: order.status,
    trackingCode: order.trackingCode,
    createdAt: order.createdAt,
    statusHistory: order.statusHistory ?? [],
    delivery: {
      city: order.addressCity,
      state: order.addressState,
    },
    items: order.items.map((i) => ({
      name: i.name,
      size: i.size,
      quantity: i.quantity,
    })),
  });
});

router.get('/mine', requireAuth, async (req: AuthedRequest, res) => {
  const orders = await prisma.order.findMany({
    where: { userId: req.user!.uid },
    orderBy: { createdAt: 'desc' },
    include: { items: true },
  });
  res.json(orders.map(serialize));
});

router.get('/:id', requireAuth, async (req: AuthedRequest, res) => {
  const order = await prisma.order.findUnique({
    where: { id: req.params.id },
    include: { items: true },
  });
  if (!order) return res.status(404).json({ error: 'Not found' });
  if (order.userId !== req.user!.uid && req.user!.role !== 'admin') {
    return res.status(403).json({ error: 'Forbidden' });
  }
  res.json(serialize(order));
});

router.get('/', requireAuth, requireAdmin, async (_req, res) => {
  const orders = await prisma.order.findMany({
    orderBy: { createdAt: 'desc' },
    take: 200,
    include: { items: true },
  });
  res.json(orders.map(serialize));
});

router.patch('/:id/status', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const existing = await prisma.order.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: 'Not found' });
  const history = (existing.statusHistory as any[]) ?? [];
  const now = new Date();
  const updated = await prisma.order.update({
    where: { id: req.params.id },
    data: {
      status: parsed.data.status,
      trackingCode: parsed.data.trackingCode ?? existing.trackingCode ?? null,
      statusHistory: [...history, { status: parsed.data.status, at: now.toISOString() }] as any,
    },
    include: { items: true },
  });

  // Dispara e-mail só pra etapas "úteis" pro cliente. "cancelado" não manda
  // e-mail por enquanto (poderia, mas precisaria de template novo).
  const newStatus = parsed.data.status;
  if (newStatus === 'pago' || newStatus === 'enviado' || newStatus === 'entregue') {
    fireOrderEmail(updated.userEmail, newStatus, {
      id: updated.id,
      customerName: updated.addressFullName,
      items: updated.items.map((i) => ({
        name: i.name, size: i.size, quantity: i.quantity, unitPrice: i.unitPrice,
      })),
      total: updated.total,
      trackingCode: updated.trackingCode,
      city: updated.addressCity,
      state: updated.addressState,
    });
  }

  res.json(serialize(updated));
});

export default router;
