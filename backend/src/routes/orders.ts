import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { requireAuth, requireAdmin, type AuthedRequest } from '../middleware/auth.js';

const router = Router();

const itemSchema = z.object({
  productId: z.string().min(1),
  name: z.string().min(1),
  size: z.string().min(1),
  unitPrice: z.number().positive(),
  quantity: z.number().int().positive(),
  imageUrl: z.string().url().optional(),
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

      // 3) Cupom (opcional)
      let discount = 0;
      let appliedCoupon: string | null = null;
      if (couponCode) {
        const code = couponCode.toUpperCase();
        const coupon = await tx.coupon.findUnique({ where: { code } });
        if (coupon && coupon.active && coupon.validUntil >= new Date()) {
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

    res.status(201).json(serialize(created));
  } catch (e: any) {
    res.status(400).json({ error: e.message ?? 'Erro ao criar pedido' });
  }
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
  res.json(serialize(updated));
});

export default router;
