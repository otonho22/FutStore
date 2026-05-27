import { Router } from 'express';
import { z } from 'zod';
import { db, FieldValue } from '../firebase.js';
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

const orderSchema = z.object({
  items: z.array(itemSchema).min(1),
  couponCode: z.string().optional(),
  address: addressSchema,
});

const SHIPPING_FIXED = Number(process.env.SHIPPING_FIXED ?? 25);

router.post('/', requireAuth, async (req: AuthedRequest, res) => {
  const parsed = orderSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { items, couponCode, address } = parsed.data;

  try {
    const orderRef = db.collection('orders').doc();
    const created = await db.runTransaction(async (tx) => {
      const productRefs = items.map((i) => db.collection('products').doc(i.productId));
      const productSnaps = await tx.getAll(...productRefs);

      let subtotal = 0;
      for (let i = 0; i < items.length; i++) {
        const snap = productSnaps[i];
        if (!snap.exists) throw new Error(`Produto ${items[i].productId} não existe`);
        const p = snap.data()!;
        const sz = (p.sizes as { size: string; stock: number }[]).find(
          (s) => s.size === items[i].size,
        );
        if (!sz || sz.stock < items[i].quantity) {
          throw new Error(`Estoque insuficiente para ${p.name} tamanho ${items[i].size}`);
        }
        subtotal += items[i].unitPrice * items[i].quantity;
      }

      let discount = 0;
      let appliedCoupon: string | null = null;
      if (couponCode) {
        const code = couponCode.toUpperCase();
        const couponSnap = await tx.get(
          db.collection('coupons').where('code', '==', code).limit(1),
        );
        if (!couponSnap.empty) {
          const c = couponSnap.docs[0].data();
          if (c.active && new Date(c.validUntil) >= new Date()) {
            discount = c.type === 'percent' ? subtotal * (c.value / 100) : c.value;
            discount = Math.min(discount, subtotal);
            appliedCoupon = code;
          }
        }
      }

      const shipping = SHIPPING_FIXED;
      const total = Math.max(0, subtotal - discount + shipping);

      for (let i = 0; i < items.length; i++) {
        const snap = productSnaps[i];
        const p = snap.data()!;
        const sizes = (p.sizes as { size: string; stock: number }[]).map((s) =>
          s.size === items[i].size ? { ...s, stock: s.stock - items[i].quantity } : s,
        );
        tx.update(productRefs[i], {
          sizes,
          salesCount: FieldValue.increment(items[i].quantity),
        });
      }

      const now = new Date();
      const orderData = {
        userId: req.user!.uid,
        userEmail: req.user!.email ?? null,
        items,
        couponCode: appliedCoupon,
        subtotal,
        discount,
        shipping,
        total,
        address,
        status: 'pendente' as const,
        statusHistory: [{ status: 'pendente', at: now }],
        trackingCode: null,
        createdAt: now,
      };
      tx.set(orderRef, orderData);
      return { id: orderRef.id, ...orderData };
    });

    res.status(201).json(created);
  } catch (e: any) {
    res.status(400).json({ error: e.message ?? 'Erro ao criar pedido' });
  }
});

router.get('/mine', requireAuth, async (req: AuthedRequest, res) => {
  const snap = await db
    .collection('orders')
    .where('userId', '==', req.user!.uid)
    .orderBy('createdAt', 'desc')
    .get();
  res.json(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
});

router.get('/:id', requireAuth, async (req: AuthedRequest, res) => {
  const doc = await db.collection('orders').doc(req.params.id).get();
  if (!doc.exists) return res.status(404).json({ error: 'Not found' });
  const data = doc.data()!;
  if (data.userId !== req.user!.uid && req.user!.role !== 'admin') {
    return res.status(403).json({ error: 'Forbidden' });
  }
  res.json({ id: doc.id, ...data });
});

router.get('/', requireAuth, requireAdmin, async (_req, res) => {
  const snap = await db.collection('orders').orderBy('createdAt', 'desc').limit(200).get();
  res.json(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
});

const statusSchema = z.object({
  status: z.enum(['pendente', 'pago', 'enviado', 'entregue', 'cancelado']),
  trackingCode: z.string().optional(),
});

router.patch('/:id/status', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const ref = db.collection('orders').doc(req.params.id);
  const doc = await ref.get();
  if (!doc.exists) return res.status(404).json({ error: 'Not found' });
  const now = new Date();
  const history = (doc.data()!.statusHistory as any[]) ?? [];
  await ref.update({
    status: parsed.data.status,
    trackingCode: parsed.data.trackingCode ?? doc.data()!.trackingCode ?? null,
    statusHistory: [...history, { status: parsed.data.status, at: now }],
  });
  const updated = await ref.get();
  res.json({ id: updated.id, ...updated.data() });
});

export default router;
