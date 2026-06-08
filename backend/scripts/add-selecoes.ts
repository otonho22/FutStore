import 'dotenv/config';
import { prisma } from '../src/db.js';

// Adiciona seleções nacionais ao catálogo regular (categoria "Seleções").
// Idempotente: pula times que já têm produto na mesma categoria.
// Não toca em produtos existentes (estoque, pedidos preservados).

const CATEGORY = 'Seleções';

type Variant = { label: string; priceDelta?: number; salesCount: number };
type SelecaoSeed = {
  team: string;
  description: string;
  basePrice: number;
  imageUrl: string;
  variants: Variant[];
};

const SELECOES: SelecaoSeed[] = [
  {
    team: 'Portugal',
    description: 'Tuga — vermelha tradicional, navegadores do gramado.',
    basePrice: 449.9,
    imageUrl: '/jerseys/portugal-fifa.jpg',
    variants: [
      { label: 'Camisa I (Home)', salesCount: 25 },
      { label: 'Camisa II (Away)', salesCount: 11 },
    ],
  },
  {
    team: 'França',
    description: 'Les Bleus — azul profundo, elegância europeia.',
    basePrice: 449.9,
    imageUrl: '/jerseys/franca.jpg',
    variants: [
      { label: 'Camisa I (Home)', salesCount: 28 },
      { label: 'Camisa II (Away)', salesCount: 12 },
    ],
  },
  {
    team: 'Inglaterra',
    description: 'Three Lions — branca clássica, berço do futebol.',
    basePrice: 449.9,
    imageUrl: '/jerseys/inglaterra.jpg',
    variants: [
      { label: 'Camisa I (Home)', salesCount: 22 },
      { label: 'Camisa II (Away)', salesCount: 9 },
    ],
  },
  {
    team: 'Alemanha',
    description: 'Die Mannschaft — branca com listras pretas, máquina de eficiência.',
    basePrice: 439.9,
    imageUrl: '/jerseys/alemanha.jpg',
    variants: [
      { label: 'Camisa I (Home)', salesCount: 26 },
      { label: 'Camisa II (Away)', salesCount: 10 },
    ],
  },
  {
    team: 'Espanha',
    description: 'La Roja — vermelha furiosa, tiki-taka.',
    basePrice: 439.9,
    imageUrl: '/jerseys/espanha-fifa.jpg',
    variants: [
      { label: 'Camisa I (Home)', salesCount: 24 },
      { label: 'Camisa II (Away)', salesCount: 9 },
    ],
  },
  {
    team: 'México',
    description: 'El Tri — verde vibrante, calor centro-americano.',
    basePrice: 389.9,
    imageUrl: '/jerseys/mexico-fifa.jpg',
    variants: [
      { label: 'Camisa I (Home)', salesCount: 15 },
      { label: 'Camisa II (Away)', salesCount: 6 },
    ],
  },
  {
    team: 'Estados Unidos',
    description: 'USMNT — branca com listras, futebol em ascensão.',
    basePrice: 389.9,
    imageUrl: '/jerseys/estados-unidos.jpg',
    variants: [
      { label: 'Camisa I (Home)', salesCount: 13 },
      { label: 'Camisa II (Away)', salesCount: 5 },
    ],
  },
  {
    team: 'Japão',
    description: 'Samurai Blue — azul profundo, disciplina e técnica.',
    basePrice: 399.9,
    imageUrl: '/jerseys/japao-fifa.jpg',
    variants: [
      { label: 'Camisa I (Home)', salesCount: 17 },
      { label: 'Camisa II (Away)', salesCount: 7 },
    ],
  },
];

async function main() {
  console.log('🌐 Adicionando seleções ao catálogo regular…');

  let added = 0;
  let skipped = 0;

  for (const sel of SELECOES) {
    // Idempotência: se já existe qualquer produto desse time na categoria, pula
    const existing = await prisma.product.findFirst({
      where: { team: sel.team, category: CATEGORY },
    });
    if (existing) {
      console.log(`  ⏭️  ${sel.team} — já existe (${existing.name}), pulando`);
      skipped++;
      continue;
    }

    for (const v of sel.variants) {
      const name = `${sel.team} ${v.label} 24/25`;
      await prisma.product.create({
        data: {
          name,
          team: sel.team,
          description: sel.description,
          price: sel.basePrice + (v.priceDelta ?? 0),
          imageUrl: sel.imageUrl,
          category: CATEGORY,
          salesCount: v.salesCount,
          active: true,
          sizes: {
            create: [
              { size: 'P', stock: 8, minStock: 3 },
              { size: 'M', stock: 15, minStock: 5 },
              { size: 'G', stock: 12, minStock: 5 },
              { size: 'GG', stock: 5, minStock: 3 },
            ],
          },
        },
      });
      added++;
    }
    console.log(`  ✓ ${sel.team} — ${sel.variants.length} variantes criadas`);
  }

  console.log(`\n🏁 ${added} produtos novos, ${skipped} times já existiam.`);
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => { console.error(e); await prisma.$disconnect(); process.exit(1); });
