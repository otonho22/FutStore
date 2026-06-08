import 'dotenv/config';
import { prisma } from '../src/db.js';

// Esconde da loja os 14 times da Copa 2026 que não têm foto de catálogo
// (FIFA store fundo branco). 12 estão com foto de jogador Wikimedia + 2 com
// SVG silhueta. Soft delete (active=false) preserva pedidos e histórico,
// e é reversível trocando o flag de volta.
//
// Rodar: cd backend && npx tsx scripts/hide-teams-without-photos.ts
// Reverter: trocar UPDATE_ACTIVE pra true e rodar de novo.

const CATEGORY = 'Copa do Mundo 2026';
const UPDATE_ACTIVE = false;

// Sem foto nenhuma (SVG silhueta)
const NO_PHOTO = ['Panamá', 'Suriname'];

// Com foto de jogador (Wikimedia) — não é padrão e-commerce
const PLAYER_PHOTO = [
  'Canadá', 'Uruguai', 'Bolívia', 'Equador',
  'Dinamarca', 'Sérvia',
  'Egito', 'Tunísia', 'Camarões',
  'Irã', 'Jordânia', 'Uzbequistão',
];

const TARGET_TEAMS = [...NO_PHOTO, ...PLAYER_PHOTO];

async function main() {
  console.log(`🎯 ${UPDATE_ACTIVE ? 'Reativando' : 'Desativando'} ${TARGET_TEAMS.length} times da Copa 2026...`);

  const products = await prisma.product.findMany({
    where: { category: CATEGORY, team: { in: TARGET_TEAMS } },
    select: { id: true, name: true, team: true, active: true },
  });

  if (products.length === 0) {
    console.log('⚠️  Nenhum produto encontrado pra esses times. Já foi removido?');
    return;
  }

  const result = await prisma.product.updateMany({
    where: { category: CATEGORY, team: { in: TARGET_TEAMS } },
    data: { active: UPDATE_ACTIVE },
  });

  // Relatório por time
  const byTeam = new Map<string, number>();
  for (const p of products) byTeam.set(p.team, (byTeam.get(p.team) ?? 0) + 1);

  console.log('\nProdutos afetados:');
  for (const t of TARGET_TEAMS) {
    const count = byTeam.get(t) ?? 0;
    const marker = count > 0 ? '✓' : '·';
    console.log(`  ${marker} ${t.padEnd(18)} ${count} produto(s)`);
  }

  console.log(`\n🏁 ${result.count} produtos atualizados (active=${UPDATE_ACTIVE}).`);
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => { console.error(e); await prisma.$disconnect(); process.exit(1); });
