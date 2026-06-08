import 'dotenv/config';
import { prisma } from '../src/db.js';

// Seed para a aba "Copa do Mundo 2026"
// - 48 times qualificados/confirmados (hosts + classificados das 6 confederações)
// - Brasil tem 2 variantes especiais: Jogador (premium) e Torcedor
// - Cupom COPA2026 (-15%) válido até o fim da Copa
// Categoria: 'Copa do Mundo 2026'

const CATEGORY = 'Copa do Mundo 2026';

type CopaTeam = { name: string; color: string; confed: string; basePrice?: number };

// Fotos locais em /frontend/public/jerseys/<slug>.jpg
// Prioridade: foto oficial FIFA store (camisa fundo branco) > foto jogador Wikimedia > SVG fallback.
// Times sem entrada aqui usam '' (vazio) → JerseyImage cai no SVG colorido com a cor do time.
const TEAM_PHOTO: Record<string, string> = {
  // === FIFA store (camisa fundo branco) ===
  // CONMEBOL
  'Brasil': '/jerseys/brasil-jogador.jpg', // Copa2026.tsx override pra 2 variantes
  'Argentina': '/jerseys/argentina-fifa.jpg',
  'Colômbia': '/jerseys/colombia.jpg',
  'Paraguai': '/jerseys/paraguai-fifa.jpg',
  // CONCACAF
  'Estados Unidos': '/jerseys/estados-unidos.jpg',
  'México': '/jerseys/mexico-fifa.jpg',
  'Costa Rica': '/jerseys/costa-rica.jpg',
  'Jamaica': '/jerseys/jamaica-fifa.jpg',
  // UEFA
  'França': '/jerseys/franca.jpg',
  'Inglaterra': '/jerseys/inglaterra.jpg',
  'Espanha': '/jerseys/espanha-fifa.jpg',
  'Alemanha': '/jerseys/alemanha.jpg',
  'Itália': '/jerseys/italia-fifa.jpg',
  'Portugal': '/jerseys/portugal-fifa.jpg',
  'Holanda': '/jerseys/holanda.jpg',
  'Bélgica': '/jerseys/belgica-fifa.jpg',
  'Croácia': '/jerseys/croacia-fifa.jpg',
  'Suíça': '/jerseys/suica-fifa.jpg',
  'Áustria': '/jerseys/austria.jpg',
  'Polônia': '/jerseys/polonia-fifa.jpg',
  'País de Gales': '/jerseys/pais-de-gales.jpg',
  'Escócia': '/jerseys/escocia.jpg',
  // CAF
  'Marrocos': '/jerseys/marrocos-fifa.jpg',
  'Senegal': '/jerseys/senegal.jpg',
  'Nigéria': '/jerseys/nigeria.jpg',
  'Argélia': '/jerseys/argelia.jpg',
  'Gana': '/jerseys/gana.jpg',
  'Costa do Marfim': '/jerseys/costa-do-marfim.jpg',
  // AFC
  'Japão': '/jerseys/japao-fifa.jpg',
  'Coreia do Sul': '/jerseys/coreia-do-sul-fifa.jpg',
  'Arábia Saudita': '/jerseys/arabia-saudita.jpg',
  'Austrália': '/jerseys/australia.jpg',
  'Catar': '/jerseys/catar-fifa.jpg',
  // OFC
  'Nova Zelândia': '/jerseys/nova-zelandia.jpg',

  // === Wikimedia (foto jogador) — FIFA store não vende esses ===
  'Canadá': '/jerseys/canada.jpg',
  'Uruguai': '/jerseys/uruguai.jpg',
  'Bolívia': '/jerseys/bolivia.jpg',
  'Equador': '/jerseys/equador.jpg',
  'Dinamarca': '/jerseys/dinamarca.jpg',
  'Sérvia': '/jerseys/servia.jpg',
  'Egito': '/jerseys/egito.jpg',
  'Tunísia': '/jerseys/tunisia.jpg',
  'Camarões': '/jerseys/camaroes.jpg',
  'Irã': '/jerseys/ira.jpg',
  'Jordânia': '/jerseys/jordania.jpg',
  'Uzbequistão': '/jerseys/uzbequistao.jpg',

  // === Sem foto (SVG silhueta) ===
  // Panamá, Suriname — FIFA não vende, Wikimedia sem boa opção
};

const COPA_TEAMS: CopaTeam[] = [
  // CONMEBOL
  { name: 'Argentina', color: '7dd3fc', confed: 'CONMEBOL' },
  { name: 'Uruguai', color: '38bdf8', confed: 'CONMEBOL' },
  { name: 'Colômbia', color: 'fde047', confed: 'CONMEBOL' },
  { name: 'Equador', color: 'fbbf24', confed: 'CONMEBOL' },
  { name: 'Paraguai', color: 'ef4444', confed: 'CONMEBOL' },
  { name: 'Bolívia', color: '16a34a', confed: 'CONMEBOL' },

  // CONCACAF (3 hosts + classificados)
  { name: 'Estados Unidos', color: '1d4ed8', confed: 'CONCACAF (Host)', basePrice: 499.9 },
  { name: 'México', color: '16a34a', confed: 'CONCACAF (Host)', basePrice: 499.9 },
  { name: 'Canadá', color: 'ef4444', confed: 'CONCACAF (Host)', basePrice: 499.9 },
  { name: 'Costa Rica', color: 'ef4444', confed: 'CONCACAF' },
  { name: 'Panamá', color: 'dc2626', confed: 'CONCACAF' },
  { name: 'Jamaica', color: 'fbbf24', confed: 'CONCACAF' },

  // UEFA (16)
  { name: 'França', color: '1d4ed8', confed: 'UEFA', basePrice: 549.9 },
  { name: 'Inglaterra', color: 'f9fafb', confed: 'UEFA', basePrice: 549.9 },
  { name: 'Espanha', color: 'dc2626', confed: 'UEFA', basePrice: 549.9 },
  { name: 'Alemanha', color: '111827', confed: 'UEFA', basePrice: 549.9 },
  { name: 'Itália', color: '1e3a8a', confed: 'UEFA', basePrice: 499.9 },
  { name: 'Portugal', color: 'dc2626', confed: 'UEFA', basePrice: 499.9 },
  { name: 'Holanda', color: 'f97316', confed: 'UEFA', basePrice: 499.9 },
  { name: 'Bélgica', color: 'b91c1c', confed: 'UEFA' },
  { name: 'Croácia', color: 'dc2626', confed: 'UEFA' },
  { name: 'Dinamarca', color: 'dc2626', confed: 'UEFA' },
  { name: 'Suíça', color: 'dc2626', confed: 'UEFA' },
  { name: 'Sérvia', color: 'b91c1c', confed: 'UEFA' },
  { name: 'Áustria', color: 'dc2626', confed: 'UEFA' },
  { name: 'Polônia', color: 'f9fafb', confed: 'UEFA' },
  { name: 'País de Gales', color: 'dc2626', confed: 'UEFA' },
  { name: 'Escócia', color: '1e40af', confed: 'UEFA' },

  // CAF (9)
  { name: 'Marrocos', color: 'b91c1c', confed: 'CAF' },
  { name: 'Senegal', color: '16a34a', confed: 'CAF' },
  { name: 'Egito', color: 'b91c1c', confed: 'CAF' },
  { name: 'Nigéria', color: '16a34a', confed: 'CAF' },
  { name: 'Argélia', color: '16a34a', confed: 'CAF' },
  { name: 'Camarões', color: '16a34a', confed: 'CAF' },
  { name: 'Gana', color: 'f9fafb', confed: 'CAF' },
  { name: 'Tunísia', color: 'dc2626', confed: 'CAF' },
  { name: 'Costa do Marfim', color: 'f97316', confed: 'CAF' },

  // AFC (8)
  { name: 'Japão', color: '1e3a8a', confed: 'AFC' },
  { name: 'Coreia do Sul', color: 'dc2626', confed: 'AFC' },
  { name: 'Arábia Saudita', color: '16a34a', confed: 'AFC' },
  { name: 'Irã', color: 'f9fafb', confed: 'AFC' },
  { name: 'Austrália', color: 'fbbf24', confed: 'AFC' },
  { name: 'Catar', color: '7c1d6f', confed: 'AFC' },
  { name: 'Uzbequistão', color: 'f9fafb', confed: 'AFC' },
  { name: 'Jordânia', color: 'b91c1c', confed: 'AFC' },

  // OFC + Inter-confederações
  { name: 'Nova Zelândia', color: 'f9fafb', confed: 'OFC' },
  { name: 'Suriname', color: '16a34a', confed: 'Playoff' },
];

const DEFAULT_PRICE = 379.9;

const sizes = [
  { size: 'P', stock: 8, minStock: 3 },
  { size: 'M', stock: 18, minStock: 5 },
  { size: 'G', stock: 14, minStock: 5 },
  { size: 'GG', stock: 6, minStock: 3 },
];

async function main() {
  console.log('🌍 Populando catálogo da Copa do Mundo 2026...');

  // Limpa Copa products existentes (idempotente)
  const existing = await prisma.product.findMany({
    where: { category: CATEGORY },
    include: { orderItems: { take: 1 } },
  });
  const withOrders = existing.filter((p) => p.orderItems.length > 0);
  if (withOrders.length > 0) {
    console.log(`⚠️  ${withOrders.length} produtos Copa já têm pedidos — não serão removidos. Pulando seed.`);
    return;
  }
  if (existing.length > 0) {
    await prisma.product.deleteMany({ where: { category: CATEGORY } });
    console.log(`  Removidos ${existing.length} produtos Copa antigos.`);
  }

  // BRASIL — 2 variantes especiais (cada uma com foto distinta da FIFA store)
  await prisma.product.create({
    data: {
      name: 'Brasil 2026 — Camisa Jogador',
      team: 'Brasil',
      description: 'Versão oficial Jogador: tecido DriFit, ajuste atlético, escudo termo-aplicado. Idêntica à usada em campo pela Seleção.',
      price: 449.90,
      imageUrl: '/jerseys/brasil-jogador.jpg',
      category: CATEGORY,
      salesCount: 312,
      active: true,
      sizes: { create: sizes.map((s) => ({ ...s, stock: s.stock + 10 })) },
    },
  });
  await prisma.product.create({
    data: {
      name: 'Brasil 2026 — Camisa Torcedor',
      team: 'Brasil',
      description: 'Versão Torcedor: tecido leve e respirável para o dia a dia, escudo bordado. Para vestir as cores em qualquer lugar.',
      price: 299.90,
      imageUrl: '/jerseys/brasil-torcedor.jpg',
      category: CATEGORY,
      salesCount: 587,
      active: true,
      sizes: { create: sizes.map((s) => ({ ...s, stock: s.stock + 20 })) },
    },
  });
  console.log('  ✓ Brasil — 2 variantes (Jogador / Torcedor)');

  // 47 outros times
  let count = 0;
  for (const t of COPA_TEAMS) {
    await prisma.product.create({
      data: {
        name: `${t.name} 2026`,
        team: t.name,
        description: `Camisa oficial da seleção de ${t.name} para a Copa do Mundo 2026 — ${t.confed}.`,
        price: t.basePrice ?? DEFAULT_PRICE,
        imageUrl: TEAM_PHOTO[t.name] ?? '', // foto local se mapeada, senão SVG via JerseyImage
        category: CATEGORY,
        salesCount: Math.floor(Math.random() * 80),
        active: true,
        sizes: { create: sizes },
      },
    });
    count++;
  }
  console.log(`  ✓ ${count} outros times Copa criados.`);

  // Cupom COPA2026 (-15%)
  const validUntil = new Date('2026-08-15');
  const coupon = await prisma.coupon.upsert({
    where: { code: 'COPA2026' },
    update: { value: 15, validUntil, active: true, type: 'percent' },
    create: {
      code: 'COPA2026', type: 'percent', value: 15,
      validUntil, active: true,
      firstPurchaseOnly: false,
    },
  });
  console.log(`  ✓ Cupom ${coupon.code} (-15%) ativo até ${validUntil.toISOString().slice(0, 10)}`);

  console.log(`\n🏆 Total: ${count + 2} produtos da Copa 2026 cadastrados.`);
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => { console.error(e); await prisma.$disconnect(); process.exit(1); });
