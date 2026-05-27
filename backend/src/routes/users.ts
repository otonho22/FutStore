import { Router } from 'express';
import { z } from 'zod';
import { db } from '../firebase.js';
import { requireAuth, type AuthedRequest } from '../middleware/auth.js';

const router = Router();

const profileSchema = z.object({
  displayName: z.string().min(1),
  acceptedTerms: z.boolean(),
});

router.post('/me', requireAuth, async (req: AuthedRequest, res) => {
  const parsed = profileSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const ref = db.collection('users').doc(req.user!.uid);
  const existing = await ref.get();
  const role = existing.exists ? existing.data()!.role : 'customer';
  await ref.set(
    {
      email: req.user!.email ?? null,
      displayName: parsed.data.displayName,
      acceptedTerms: parsed.data.acceptedTerms,
      role,
      createdAt: existing.exists ? existing.data()!.createdAt : new Date(),
    },
    { merge: true },
  );
  const doc = await ref.get();
  res.json({ id: doc.id, ...doc.data() });
});

router.get('/me', requireAuth, async (req: AuthedRequest, res) => {
  const doc = await db.collection('users').doc(req.user!.uid).get();
  if (!doc.exists) return res.status(404).json({ error: 'Not found' });
  res.json({ id: doc.id, ...doc.data() });
});

export default router;
