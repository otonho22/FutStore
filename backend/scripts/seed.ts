import 'dotenv/config';
import { prisma } from '../src/db.js';

function placeholder(text: string, color = '22c55e') {
  return `https://placehold.co/600x600/0f1115/${color}/png?text=${encodeURIComponent(text)}`;
}

type Variant = { label: string; color: string; priceDelta?: number; salesCount: number };
type TeamBundle = {
  team: string;
  category: string;
  basePrice: number;
  description: string;
  variants: Variant[];
};

// 3 variantes por time/seleção (Camisa I = Home, II = Away, III = Third)
const TEAMS: TeamBundle[] = [
  {
    team: 'Flamengo', category: 'Times Brasileiros', basePrice: 349.9,
    description: 'Camisa oficial do Mengão, manto sagrado rubro-negro.',
    variants: [
      { label: 'Camisa I (Home)', color: 'ef4444', salesCount: 32 },
      { label: 'Camisa II (Away)', color: 'f9fafb', salesCount: 18, priceDelta: 0 },
      { label: 'Camisa III (Third)', color: '111827', salesCount: 9, priceDelta: 10 },
    ],
  },
  {
    team: 'Palmeiras', category: 'Times Brasileiros', basePrice: 329.9,
    description: 'Camisa Verdão, listras tradicionais do Palestra.',
    variants: [
      { label: 'Camisa I (Home)', color: '22c55e', salesCount: 28 },
      { label: 'Camisa II (Away)', color: 'f9fafb', salesCount: 12 },
      { label: 'Camisa III (Third)', color: '0f766e', salesCount: 6, priceDelta: 10 },
    ],
  },
  {
    team: 'Corinthians', category: 'Times Brasileiros', basePrice: 319.9,
    description: 'Camisa do Timão, Fiel Torcida.',
    variants: [
      { label: 'Camisa I (Home)', color: 'f9fafb', salesCount: 21 },
      { label: 'Camisa II (Away)', color: '111827', salesCount: 14 },
      { label: 'Camisa III (Third)', color: 'ef4444', salesCount: 4, priceDelta: 20 },
    ],
  },
  {
    team: 'São Paulo', category: 'Times Brasileiros', basePrice: 319.9,
    description: 'Tricolor paulista, tradição na faixa.',
    variants: [
      { label: 'Camisa I (Home)', color: 'ef4444', salesCount: 17 },
      { label: 'Camisa II (Away)', color: 'f9fafb', salesCount: 8 },
    ],
  },
  {
    team: 'Grêmio', category: 'Times Brasileiros', basePrice: 309.9,
    description: 'Tricolor gaúcho — azul, preto e branco.',
    variants: [
      { label: 'Camisa I (Home)', color: '38bdf8', salesCount: 13 },
      { label: 'Camisa II (Away)', color: 'f9fafb', salesCount: 5 },
    ],
  },
  {
    team: 'Real Madrid', category: 'Times Europeus', basePrice: 499.9,
    description: 'Os Merengues — branca clássica.',
    variants: [
      { label: 'Camisa I (Home)', color: 'f1f5f9', salesCount: 36 },
      { label: 'Camisa II (Away)', color: '111827', salesCount: 22 },
      { label: 'Camisa III (Third)', color: 'fbbf24', salesCount: 11, priceDelta: 20 },
    ],
  },
  {
    team: 'FC Barcelona', category: 'Times Europeus', basePrice: 499.9,
    description: 'Blaugrana — listras vermelho e azul.',
    variants: [
      { label: 'Camisa I (Home)', color: 'ef4444', salesCount: 31 },
      { label: 'Camisa II (Away)', color: 'fbbf24', salesCount: 18 },
      { label: 'Camisa III (Third)', color: '0ea5e9', salesCount: 8, priceDelta: 20 },
    ],
  },
  {
    team: 'Manchester City', category: 'Times Europeus', basePrice: 459.9,
    description: 'Sky blue — campeão inglês.',
    variants: [
      { label: 'Camisa I (Home)', color: '38bdf8', salesCount: 20 },
      { label: 'Camisa II (Away)', color: '111827', salesCount: 9 },
    ],
  },
  {
    team: 'Seleção Brasileira', category: 'Seleções', basePrice: 389.9,
    description: 'Amarelinha — paixão de um povo.',
    variants: [
      { label: 'Camisa I (Home)', color: 'fbbf24', salesCount: 42 },
      { label: 'Camisa II (Away)', color: '1d4ed8', salesCount: 19 },
      { label: 'Retrô 1970', color: 'eab308', salesCount: 7, priceDelta: 30 },
    ],
  },
  {
    team: 'Seleção Argentina', category: 'Seleções', basePrice: 389.9,
    description: 'Albiceleste — listras celeste e branca.',
    variants: [
      { label: 'Camisa I (Home)', color: '7dd3fc', salesCount: 26 },
      { label: 'Camisa II (Away)', color: '111827', salesCount: 11 },
    ],
  },
];

async function main() {
  console.log('🌱 Populando catálogo (PostgreSQL via Prisma)...');

  let count = 0;
  for (const t of TEAMS) {
    for (const v of t.variants) {
      const name = `${t.team} ${v.label} 24/25`;
      await prisma.product.create({
        data: {
          name,
          team: t.team,
          description: t.description,
          price: t.basePrice + (v.priceDelta ?? 0),
          imageUrl: placeholder(`${t.team}\n${v.label}`, v.color),
          category: t.category,
          salesCount: v.salesCount,
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
      count++;
    }
  }
  console.log(`✓ ${count} produtos criados (${TEAMS.length} times com 2-3 variantes).`);

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
