import 'dotenv/config';
import { prisma } from '../src/db.js';

function placeholder(text: string, color = '22c55e') {
  return `https://placehold.co/600x600/0f1115/${color}/png?text=${encodeURIComponent(text)}`;
}

const PRODUCTS = [
  { name: 'Flamengo I 24/25', team: 'Flamengo', category: 'Times Brasileiros',
    description: 'Camisa oficial do Mengão, manto sagrado rubro-negro.',
    price: 349.9, color: 'ef4444', salesCount: 18 },
  { name: 'Palmeiras I 24/25', team: 'Palmeiras', category: 'Times Brasileiros',
    description: 'Camisa Verdão, listras tradicionais do Palestra.',
    price: 329.9, color: '22c55e', salesCount: 22 },
  { name: 'Corinthians I 24/25', team: 'Corinthians', category: 'Times Brasileiros',
    description: 'Camisa branca do Timão, Fiel Torcida.',
    price: 319.9, color: 'e5e7eb', salesCount: 14 },
  { name: 'São Paulo I 24/25', team: 'São Paulo', category: 'Times Brasileiros',
    description: 'Tricolor paulista, tradição na faixa.',
    price: 319.9, color: 'ef4444', salesCount: 9 },
  { name: 'Grêmio I 24/25', team: 'Grêmio', category: 'Times Brasileiros',
    description: 'Tricolor gaúcho — azul, preto e branco.',
    price: 309.9, color: '38bdf8', salesCount: 7 },
  { name: 'Real Madrid Home 24/25', team: 'Real Madrid', category: 'Times Europeus',
    description: 'Os Merengues — branca clássica.',
    price: 499.9, color: 'f1f5f9', salesCount: 28 },
  { name: 'Barcelona Home 24/25', team: 'FC Barcelona', category: 'Times Europeus',
    description: 'Blaugrana — listras vermelho e azul.',
    price: 499.9, color: 'ef4444', salesCount: 25 },
  { name: 'Manchester City Home 24/25', team: 'Manchester City', category: 'Times Europeus',
    description: 'Sky blue — campeão inglês.',
    price: 459.9, color: '38bdf8', salesCount: 16 },
  { name: 'Brasil Seleção I 24', team: 'Seleção Brasileira', category: 'Seleções',
    description: 'Amarelinha — paixão de um povo.',
    price: 389.9, color: 'fbbf24', salesCount: 30 },
  { name: 'Argentina I 24', team: 'Seleção Argentina', category: 'Seleções',
    description: 'Albiceleste — listras celeste e branca.',
    price: 389.9, color: '7dd3fc', salesCount: 12 },
];

async function main() {
  console.log('🌱 Populando catálogo (PostgreSQL via Prisma)...');

  for (const p of PRODUCTS) {
    await prisma.product.create({
      data: {
        name: p.name,
        team: p.team,
        description: p.description,
        price: p.price,
        imageUrl: placeholder(p.team, p.color),
        category: p.category,
        salesCount: p.salesCount,
        active: true,
        sizes: {
          create: [
            { size: 'P', stock: 8 },
            { size: 'M', stock: 15 },
            { size: 'G', stock: 12 },
            { size: 'GG', stock: 5 },
          ],
        },
      },
    });
  }
  console.log(`✓ ${PRODUCTS.length} produtos criados.`);

  const validUntil = new Date(Date.now() + 1000 * 60 * 60 * 24 * 60);
  const coupon = await prisma.coupon.upsert({
    where: { code: 'BEMVINDO10' },
    create: { code: 'BEMVINDO10', type: 'percent', value: 10, validUntil, active: true },
    update: {},
  });
  console.log(`✓ Cupom ${coupon.code} (10%) pronto.`);

  console.log('\nPronto. Acesse o frontend e veja o Dashboard.');
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
