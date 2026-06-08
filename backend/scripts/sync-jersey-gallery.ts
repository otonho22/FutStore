import 'dotenv/config';
import { readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { prisma } from '../src/db.js';

// Varre frontend/public/jerseys/ e popula o campo images[] de cada produto
// que aponta pra uma foto local (/jerseys/<slug>.ext). A convenção:
//
//   /jerseys/<slug>.jpg              → imageUrl (principal, já gravado)
//   /jerseys/<slug>-costas.jpg       → galeria (1ª extra, prioridade)
//   /jerseys/<slug>-2.jpg            → galeria (extra)
//   /jerseys/<slug>-3.jpg            → galeria (extra)
//   ...
//
// Funciona pra qualquer categoria (Copa 2026, Brasileirão 2026, etc.) — só
// depende do imageUrl apontar pra /jerseys/. Idempotente: roda quantas vezes
// quiser, só atualiza se a galeria mudou.
//
// Rodar: cd backend && npx tsx scripts/sync-jersey-gallery.ts

const JERSEYS_DIR = resolve(process.cwd(), '..', 'frontend', 'public', 'jerseys');
const PUBLIC_PREFIX = '/jerseys/';
const VALID_EXT = /\.(jpe?g|png|webp)$/i;
const MAX_GALLERY = 4;

// Extrai o "stem" do path /jerseys/foo.jpg → "foo"
function stemFromImageUrl(url: string): string | null {
  if (!url.startsWith(PUBLIC_PREFIX)) return null;
  const file = url.slice(PUBLIC_PREFIX.length);
  return file.replace(VALID_EXT, '');
}

// Ordena variantes: -costas vem primeiro, depois numéricos (-2, -3...), depois resto.
function sortVariants(stem: string, files: string[]): string[] {
  const score = (f: string): [number, number] => {
    const suffix = f.slice(stem.length + 1).replace(VALID_EXT, ''); // remove "<stem>-" e a extensão
    if (suffix === 'costas') return [0, 0];
    const n = parseInt(suffix, 10);
    if (!Number.isNaN(n)) return [1, n];
    return [2, 0];
  };
  return [...files].sort((a, b) => {
    const [pa, na] = score(a);
    const [pb, nb] = score(b);
    return pa - pb || na - nb || a.localeCompare(b);
  });
}

function arraysEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((v, i) => v === b[i]);
}

async function main() {
  let allFiles: string[];
  try {
    allFiles = await readdir(JERSEYS_DIR);
  } catch (e: any) {
    console.error(`❌ Não consegui ler ${JERSEYS_DIR}: ${e.message}`);
    process.exit(1);
  }

  const products = await prisma.product.findMany({
    where: { active: true, imageUrl: { startsWith: PUBLIC_PREFIX } },
    select: { id: true, name: true, team: true, imageUrl: true, images: true },
  });

  let updated = 0;
  let unchanged = 0;
  let noExtras = 0;

  for (const p of products) {
    const stem = stemFromImageUrl(p.imageUrl);
    if (!stem) continue;

    // Procura arquivos "<stem>-*.ext" (mas NÃO o principal "<stem>.ext")
    const prefix = `${stem}-`;
    const variants = allFiles.filter(
      (f) => f.startsWith(prefix) && VALID_EXT.test(f),
    );

    if (variants.length === 0) {
      noExtras++;
      // Se já tinha galeria mas o arquivo sumiu, limpa.
      if (p.images.length > 0) {
        await prisma.product.update({
          where: { id: p.id },
          data: { images: [] },
        });
        console.log(`  🧹 ${p.team.padEnd(18)} galeria limpa (arquivos não encontrados)`);
        updated++;
        noExtras--;
      }
      continue;
    }

    const sorted = sortVariants(stem, variants).slice(0, MAX_GALLERY);
    const newImages = sorted.map((f) => `${PUBLIC_PREFIX}${f}`);

    if (arraysEqual(newImages, p.images)) {
      unchanged++;
      continue;
    }

    await prisma.product.update({
      where: { id: p.id },
      data: { images: newImages },
    });
    console.log(`  ✓ ${p.team.padEnd(18)} ${newImages.length} foto(s) extra: ${sorted.join(', ')}`);
    updated++;
  }

  console.log(`\n🏁 ${updated} atualizados · ${unchanged} já sincronizados · ${noExtras} sem fotos extras.`);
  console.log('\n💡 Pra adicionar a foto de costas de um time, salve:');
  console.log('   frontend/public/jerseys/<mesmo-nome-da-principal>-costas.jpg');
  console.log('   exemplo: flamengo-br-2026-costas.jpg');
  console.log('   depois roda este script de novo.');
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => { console.error(e); await prisma.$disconnect(); process.exit(1); });
