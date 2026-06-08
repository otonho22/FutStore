import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { requireAuth, requireAdmin, type AuthedRequest } from '../middleware/auth.js';

const router = Router();

const couponSchema = z.object({
  code: z.string().min(1).transform((s) => s.toUpperCase()),
  type: z.enum(['fixed', 'percent']),
  value: z.number().positive(),
  validUntil: z.string().datetime().or(z.string().date()),
  active: z.boolean().default(true),
  firstPurchaseOnly: z.boolean().default(false),
  maxUsesPerCustomer: z.number().int().positive().nullable().optional(),
  maxUsesGlobal: z.number().int().positive().nullable().optional(),
});

router.get('/', requireAuth, requireAdmin, async (_req, res) => {
  const coupons = await prisma.coupon.findMany({ orderBy: { code: 'asc' } });
  res.json(coupons);
});

router.get('/validate/:code', requireAuth, async (req: AuthedRequest, res) => {
  const code = req.params.code.toUpperCase();
  const coupon = await prisma.coupon.findUnique({ where: { code } });
  if (!coupon) return res.status(404).json({ error: 'Cupom não encontrado' });
  if (!coupon.active) return res.status(400).json({ error: 'Cupom inativo' });
  if (coupon.validUntil < new Date()) return res.status(400).json({ error: 'Cupom expirado' });

  const userId = req.user!.uid;
  const notCancelled = { status: { not: 'cancelado' } as const };

  if (coupon.firstPurchaseOnly) {
    const prev = await prisma.order.count({ where: { userId, ...notCancelled } });
    if (prev > 0) return res.status(400).json({ error: 'Cupom válido apenas na primeira compra' });
  }
  if (coupon.maxUsesGlobal != null) {
    const used = await prisma.order.count({ where: { couponCode: code, ...notCancelled } });
    if (used >= coupon.maxUsesGlobal) return res.status(400).json({ error: 'Cupom esgotado' });
  }
  if (coupon.maxUsesPerCustomer != null) {
    const usedByUser = await prisma.order.count({ where: { couponCode: code, userId, ...notCancelled } });
    if (usedByUser >= coupon.maxUsesPerCustomer) {
      return res.status(400).json({ error: 'Limite de uso por cliente atingido' });
    }
  }

  res.json(coupon);
});

router.post('/', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = couponSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const created = await prisma.coupon.create({
    data: { ...parsed.data, validUntil: new Date(parsed.data.validUntil) },
  });
  res.status(201).json(created);
});

router.put('/:id', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = couponSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const data: any = { ...parsed.data };
  if (data.validUntil) data.validUntil = new Date(data.validUntil);
  const updated = await prisma.coupon.update({ where: { id: req.params.id }, data });
  res.json(updated);
});

router.delete('/:id', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  await prisma.coupon.delete({ where: { id: req.params.id } });
  res.status(204).end();
});

export default router;
