import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import productsRouter from './routes/products.js';
import couponsRouter from './routes/coupons.js';
import ordersRouter from './routes/orders.js';
import usersRouter from './routes/users.js';
import { verifyMailerConfig } from './lib/mailer.js';

const app = express();
const port = Number(process.env.PORT ?? 4000);
const origin = process.env.ALLOWED_ORIGIN ?? 'http://localhost:5173,http://localhost:5174,http://localhost:5175';
const allowedOrigins = origin.split(',').map((s) => s.trim()).filter(Boolean);

app.use(
  cors({
    origin(o, cb) {
      // Allow requests with no origin (curl, server-to-server) and any localhost dev port
      if (!o) return cb(null, true);
      if (allowedOrigins.includes(o)) return cb(null, true);
      if (/^http:\/\/localhost:\d+$/.test(o)) return cb(null, true);
      return cb(new Error(`Origin ${o} not allowed by CORS`));
    },
    credentials: true,
  }),
);
app.use(express.json({ limit: '1mb' }));

app.get('/health', (_req, res) => res.json({ ok: true }));

app.use('/api/products', productsRouter);
app.use('/api/coupons', couponsRouter);
app.use('/api/orders', ordersRouter);
app.use('/api/users', usersRouter);

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err);
  res.status(500).json({ error: 'Internal error' });
});

app.listen(port, () => {
  console.log(`API ready on http://localhost:${port}`);
  // Valida SMTP em background — não bloqueia o boot.
  void verifyMailerConfig();
});
