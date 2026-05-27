import 'dotenv/config';
import { auth, db } from '../src/firebase.js';

const email = process.argv[2];
if (!email) {
  console.error('Uso: npm run set-admin -- email@exemplo.com');
  process.exit(1);
}

const user = await auth.getUserByEmail(email);
await auth.setCustomUserClaims(user.uid, { role: 'admin' });
await db.collection('users').doc(user.uid).set({ role: 'admin' }, { merge: true });
console.log(`OK: ${email} agora é admin. Peça para o usuário sair e entrar de novo.`);
