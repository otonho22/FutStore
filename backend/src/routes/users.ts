import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { requireAuth, type AuthedRequest } from '../middleware/auth.js';

const router = Router();

const profileSchema = z.object({
  displayName: z.string().min(1),
  acceptedTerms: z.boolean(),
});

router.post('/me', requireAuth, async (req: AuthedRequest, res) => {
  const parsed = profileSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const user = await prisma.user.upsert({
    where: { id: req.user!.uid },
    create: {
      id: req.user!.uid,
      email: req.user!.email ?? '',
      displayName: parsed.data.displayName,
      acceptedTerms: parsed.data.acceptedTerms,
      role: 'customer',
    },
    update: {
      email: req.user!.email ?? undefined,
      displayName: parsed.data.displayName,
      acceptedTerms: parsed.data.acceptedTerms,
    },
  });
  res.json(user);
});

router.get('/me', requireAuth, async (req: AuthedRequest, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.user!.uid } });
  if (!user) return res.status(404).json({ error: 'Not found' });
  res.json(user);
});

export default router;
