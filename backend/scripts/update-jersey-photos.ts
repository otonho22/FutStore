import 'dotenv/config';
import { prisma } from '../src/db.js';

// Atualiza imageUrl dos produtos existentes para usar as fotos locais em
// /frontend/public/jerseys/<slug>.jpg. Seguro mesmo com pedidos existentes —
// só faz UPDATE, não toca em Order/OrderItem.
const TEAM_PHOTO: Record<string, string> = {
  'Flamengo': '/jerseys/flamengo.jpg',
  'Palmeiras': '/jerseys/palmeiras.jpg',
  'Corinthians': '/jerseys/corinthians.jpg',
  'São Paulo': '/jerseys/sao-paulo.jpg',
  'Grêmio': '/jerseys/gremio.jpg',
  'Real Madrid': '/jerseys/real-madrid.jpg',
  'FC Barcelona': '/jerseys/fc-barcelona.jpg',
  'Manchester City': '/jerseys/manchester-city.jpg',
  'Seleção Brasileira': '/jerseys/selecao-brasileira.jpg',
  'Seleção Argentina': '/jerseys/selecao-argentina.jpg',
};

async function main() {
  const products = await prisma.product.findMany();
  let updated = 0;
  let skipped = 0;
  for (const p of products) {
    const photo = TEAM_PHOTO[p.team];
    if (!photo) { skipped++; continue; }
    await prisma.product.update({ where: { id: p.id }, data: { imageUrl: photo } });
    updated++;
  }
  console.log(`✓ ${updated} produtos atualizados, ${skipped} ignorados (time sem mapeamento).`);
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => { console.error(e); await prisma.$disconnect(); process.exit(1); });
