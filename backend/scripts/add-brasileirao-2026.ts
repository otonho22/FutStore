import 'dotenv/config';
import { prisma } from '../src/db.js';

// Adiciona os 15 clubes da Série A do Brasileirão 2026 ao catálogo,
// categoria "Brasileirão 2026". Idempotente: pula times que já têm produto
// nessa categoria.
//
// Imagens esperadas em /frontend/public/jerseys/<slug>-br-2026.jpg.
// Se o arquivo não existir, o componente JerseyImage cai no SVG silhueta
// colorido (TEAM_COLOR já foi atualizado pra todos esses times).
//
// Rodar: cd backend && npx tsx scripts/add-brasileirao-2026.ts

const CATEGORY = 'Brasileirão 2026';

type ClubSeed = {
  team: string;
  slug: string;
  description: string;
  price: number;
  salesCount: number;
};

const CLUBES: ClubSeed[] = [
  { team: 'Flamengo',      slug: 'flamengo',      description: 'Mengão — manto rubro-negro, paixão da Nação.',          price: 349.9, salesCount: 412 },
  { team: 'Corinthians',   slug: 'corinthians',   description: 'Timão — preto e branco da Fiel.',                       price: 349.9, salesCount: 389 },
  { team: 'São Paulo',     slug: 'sao-paulo',     description: 'Tricolor paulista — tradição e mística do Morumbi.',    price: 349.9, salesCount: 276 },
  { team: 'Palmeiras',     slug: 'palmeiras',     description: 'Verdão — verde imponente do maior campeão brasileiro.', price: 349.9, salesCount: 358 },
  { team: 'Vasco',         slug: 'vasco',         description: 'Cruzmaltino — preto com banda branca, raça carioca.',   price: 329.9, salesCount: 184 },
  { team: 'Santos',        slug: 'santos',        description: 'Peixe — manto branco da Vila Belmiro.',                 price: 329.9, salesCount: 198 },
  { team: 'Grêmio',        slug: 'gremio',        description: 'Imortal Tricolor — azul, preto e branco do Sul.',       price: 329.9, salesCount: 221 },
  { team: 'Internacional', slug: 'internacional', description: 'Colorado — vermelho gigante de Porto Alegre.',          price: 329.9, salesCount: 203 },
  { team: 'Atlético-MG',   slug: 'atletico-mg',   description: 'Galo — preto e branco com a alma de Minas.',            price: 329.9, salesCount: 245 },
  { team: 'Fluminense',    slug: 'fluminense',    description: 'Tricolor das Laranjeiras — grená, verde e branco.',     price: 329.9, salesCount: 167 },
  { team: 'Botafogo',      slug: 'botafogo',      description: 'Glorioso — estrela solitária no manto preto e branco.', price: 329.9, salesCount: 192 },
  { team: 'Cruzeiro',      slug: 'cruzeiro',      description: 'Raposa — azul celeste com cinco estrelas.',             price: 329.9, salesCount: 178 },
  { team: 'Bahia',         slug: 'bahia',         description: 'Esquadrão — tricolor de aço, orgulho do Nordeste.',     price: 309.9, salesCount: 142 },
  { team: 'Fortaleza',     slug: 'fortaleza',     description: 'Leão do Pici — azul e vermelho do Ceará.',              price: 309.9, salesCount: 138 },
  { team: 'Sport',         slug: 'sport',         description: 'Leão da Ilha — rubro-negro pernambucano.',              price: 309.9, salesCount: 119 },
];

const SIZES = [
  { size: 'P',  stock: 10, minStock: 3 },
  { size: 'M',  stock: 18, minStock: 5 },
  { size: 'G',  stock: 14, minStock: 5 },
  { size: 'GG', stock: 6,  minStock: 3 },
];

async function main() {
  console.log(`🇧🇷 Cadastrando ${CLUBES.length} clubes do Brasileirão 2026...\n`);

  let added = 0;
  let skipped = 0;

  for (const c of CLUBES) {
    const existing = await prisma.product.findFirst({
      where: { team: c.team, category: CATEGORY },
    });
    if (existing) {
      console.log(`  ⏭️  ${c.team.padEnd(15)} já existe (${existing.name}), pulando`);
      skipped++;
      continue;
    }

    await prisma.product.create({
      data: {
        name: `${c.team} 2026 — Camisa I`,
        team: c.team,
        description: c.description,
        price: c.price,
        imageUrl: `/jerseys/${c.slug}-br-2026.jpg`,
        category: CATEGORY,
        salesCount: c.salesCount,
        active: true,
        sizes: { create: SIZES },
      },
    });
    console.log(`  ✓ ${c.team.padEnd(15)} criado — imagem esperada em /jerseys/${c.slug}-br-2026.jpg`);
    added++;
  }

  console.log(`\n🏁 ${added} novos · ${skipped} já existiam.`);
  console.log('\n📸 Arquivos de imagem esperados em frontend/public/jerseys/:');
  CLUBES.forEach((c) => console.log(`   ${c.slug}-br-2026.jpg`));
  console.log('\nSem o arquivo, o produto exibe o SVG silhueta com a cor do time (já mapeado em JerseyImage).');
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => { console.error(e); await prisma.$disconnect(); process.exit(1); });
