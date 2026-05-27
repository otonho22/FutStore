import { Router } from 'express';
import { z } from 'zod';
import { db } from '../firebase.js';
import { requireAuth, requireAdmin, type AuthedRequest } from '../middleware/auth.js';

const router = Router();

const sizeSchema = z.object({
  size: z.string().min(1),
  stock: z.number().int().min(0),
});

const productSchema = z.object({
  name: z.string().min(1),
  team: z.string().min(1),
  description: z.string().default(''),
  price: z.number().positive(),
  imageUrl: z.string().url(),
  images: z.array(z.string().url()).max(4).default([]),
  sizes: z.array(sizeSchema).min(1),
  category: z.string().min(1),
  active: z.boolean().default(true),
});

router.get('/', async (req, res) => {
  const sort = (req.query.sort as string) ?? 'createdAt';
  const limit = Math.min(parseInt((req.query.limit as string) ?? '50', 10) || 50, 100);
  const category = req.query.category as string | undefined;

  let q = db.collection('products').where('active', '==', true);
  if (category) q = q.where('category', '==', category);

  const validSorts = ['salesCount', 'price', 'createdAt'];
  const sortField = validSorts.includes(sort) ? sort : 'createdAt';
  const snap = await q.orderBy(sortField, 'desc').limit(limit).get();

  res.json(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
});

router.get('/:id', async (req, res) => {
  const doc = await db.collection('products').doc(req.params.id).get();
  if (!doc.exists) return res.status(404).json({ error: 'Not found' });
  res.json({ id: doc.id, ...doc.data() });
});

router.post('/', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = productSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const ref = await db.collection('products').add({
    ...parsed.data,
    salesCount: 0,
    createdAt: new Date(),
  });
  const doc = await ref.get();
  res.status(201).json({ id: doc.id, ...doc.data() });
});

router.put('/:id', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = productSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  await db.collection('products').doc(req.params.id).update(parsed.data);
  const doc = await db.collection('products').doc(req.params.id).get();
  res.json({ id: doc.id, ...doc.data() });
});

router.delete('/:id', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  await db.collection('products').doc(req.params.id).delete();
  res.status(204).end();
});

export default router;
