import 'dotenv/config';
import { auth } from '../src/firebase.js';
import { prisma } from '../src/db.js';

const email = process.argv[2];
if (!email) {
  console.error('Uso: npm run set-admin -- email@exemplo.com');
  process.exit(1);
}

const user = await auth.getUserByEmail(email);
await auth.setCustomUserClaims(user.uid, { role: 'admin' });

await prisma.user.upsert({
  where: { id: user.uid },
  create: {
    id: user.uid,
    email: user.email ?? email,
    displayName: user.displayName ?? null,
    role: 'admin',
  },
  update: { role: 'admin' },
});

console.log(`OK: ${email} agora é admin. Peça para o usuário sair e entrar de novo.`);
await prisma.$disconnect();
