import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
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

function serialize(p: any) {
  return {
    id: p.id,
    name: p.name,
    team: p.team,
    description: p.description,
    price: p.price,
    imageUrl: p.imageUrl,
    images: p.images,
    category: p.category,
    salesCount: p.salesCount,
    active: p.active,
    createdAt: p.createdAt,
    sizes: (p.sizes ?? []).map((s: any) => ({ size: s.size, stock: s.stock })),
  };
}

router.get('/', async (req, res) => {
  const sort = (req.query.sort as string) ?? 'createdAt';
  const limit = Math.min(parseInt((req.query.limit as string) ?? '50', 10) || 50, 100);
  const category = req.query.category as string | undefined;

  const validSorts: Record<string, string> = {
    salesCount: 'salesCount',
    price: 'price',
    createdAt: 'createdAt',
  };
  const sortField = validSorts[sort] ?? 'createdAt';

  const products = await prisma.product.findMany({
    where: { active: true, ...(category ? { category } : {}) },
    orderBy: { [sortField]: 'desc' },
    take: limit,
    include: { sizes: true },
  });

  res.json(products.map(serialize));
});

router.get('/:id', async (req, res) => {
  const p = await prisma.product.findUnique({
    where: { id: req.params.id },
    include: { sizes: true },
  });
  if (!p) return res.status(404).json({ error: 'Not found' });
  res.json(serialize(p));
});

router.post('/', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = productSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { sizes, ...rest } = parsed.data;
  const created = await prisma.product.create({
    data: { ...rest, sizes: { create: sizes } },
    include: { sizes: true },
  });
  res.status(201).json(serialize(created));
});

router.put('/:id', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  const parsed = productSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { sizes, ...rest } = parsed.data;

  await prisma.product.update({ where: { id: req.params.id }, data: rest });
  if (sizes) {
    await prisma.productSize.deleteMany({ where: { productId: req.params.id } });
    await prisma.productSize.createMany({
      data: sizes.map((s) => ({ ...s, productId: req.params.id })),
    });
  }
  const updated = await prisma.product.findUnique({
    where: { id: req.params.id },
    include: { sizes: true },
  });
  res.json(serialize(updated));
});

router.delete('/:id', requireAuth, requireAdmin, async (req: AuthedRequest, res) => {
  await prisma.product.delete({ where: { id: req.params.id } });
  res.status(204).end();
});

export default router;
