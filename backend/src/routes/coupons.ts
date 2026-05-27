import { Router } from 'express';
import { z } from 'zod';
import { db } from '../firebase.js';
import { requireAuth, requireAdmin, type AuthedRequest } from '../middleware/auth.js';

const router = Router();

const couponSchema = z.object({
  code: z.string().min(1).transform((s) => s.toUpperCase()),
  type: z.enum(['fixed', 'percent']),
  value: z.number().positive(),
  validUntil: z.string().datetime().or(z.string().date()),
  active: z.boolean().default(true),
});

router.get('/', requireAuth, requireAdmin, async (_req, res) => {
  const snap = await db.collection('coupons').orderBy('code').get();
  res.json(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
});

router.get('/validate/:code', requireAuth, async (req, res) => {
  const code = req.params.code.toUpperCase();
  const snap = await db.collection('coupons').where('code', '==', code).limit(1).get();
  if (snap.empty) return res.status(404).json({ error: 'Cupom não encontrado' });
  const data = snap.docs[0].data();
  if (!data.active) return res.status(400).json({ error: 'Cupom inativo' });
  if (new Date(data.validUntil) < new Date()) {
    return res.status(400).json({ error: 'Cupom expirado' });
  }
  res.json({ id: snap.docs[0].id, ...data });
});

router.post('/', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = couponSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const ref = await db.collection('coupons').add({ ...parsed.data, createdAt: new Date() });
  const doc = await ref.get();
  res.status(201).json({ id: doc.id, ...doc.data() });
});

router.put('/:id', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = couponSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  await db.collection('coupons').doc(req.params.id).update(parsed.data);
  const doc = await db.collection('coupons').doc(req.params.id).get();
  res.json({ id: doc.id, ...doc.data() });
});

router.delete('/:id', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  await db.collection('coupons').doc(req.params.id).delete();
  res.status(204).end();
});

export default router;
