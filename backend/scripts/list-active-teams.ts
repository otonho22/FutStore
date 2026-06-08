import 'dotenv/config';
import { prisma } from '../src/db.js';

async function main() {
  const products = await prisma.product.findMany({
    where: { active: true },
    select: { team: true, category: true, name: true },
    orderBy: [{ category: 'asc' }, { team: 'asc' }],
  });

  const byCategory = new Map<string, Set<string>>();
  for (const p of products) {
    if (!byCategory.has(p.category)) byCategory.set(p.category, new Set());
    byCategory.get(p.category)!.add(p.team);
  }

  console.log(`Total: ${products.length} produtos ativos · ${[...new Set(products.map(p => p.team))].length} times distintos\n`);

  for (const [cat, teams] of byCategory) {
    const sorted = [...teams].sort((a, b) => a.localeCompare(b, 'pt-BR'));
    console.log(`📂 ${cat} (${sorted.length} times)`);
    sorted.forEach((t, i) => console.log(`  ${(i + 1).toString().padStart(2)}. ${t}`));
    console.log();
  }
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => { console.error(e); await prisma.$disconnect(); process.exit(1); });
