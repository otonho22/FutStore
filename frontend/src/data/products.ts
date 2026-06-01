import type { Product } from '../types';

function img(text: string, color = '22c55e') {
  return `https://placehold.co/600x600/0f1115/${color}/png?text=${encodeURIComponent(text)}`;
}

const defaultSizes = () => [
  { size: 'P', stock: 8 },
  { size: 'M', stock: 15 },
  { size: 'G', stock: 12 },
  { size: 'GG', stock: 5 },
];

// 26 camisas: 10 times com 2-3 variantes cada
export const PRODUCTS: Product[] = [
  // Flamengo
  { id: 'fla-i', name: 'Flamengo Camisa I (Home) 24/25', team: 'Flamengo', description: 'Camisa oficial do Mengão, manto sagrado rubro-negro.', price: 349.9, imageUrl: img('Flamengo\nHome', 'ef4444'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 32, active: true },
  { id: 'fla-ii', name: 'Flamengo Camisa II (Away) 24/25', team: 'Flamengo', description: 'Camisa II branca do Mengão.', price: 349.9, imageUrl: img('Flamengo\nAway', 'f9fafb'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 18, active: true },
  { id: 'fla-iii', name: 'Flamengo Camisa III (Third) 24/25', team: 'Flamengo', description: 'Camisa III preta — versão alternativa.', price: 359.9, imageUrl: img('Flamengo\nThird', '111827'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 9, active: true },

  // Palmeiras
  { id: 'pal-i', name: 'Palmeiras Camisa I (Home) 24/25', team: 'Palmeiras', description: 'Camisa Verdão, listras tradicionais do Palestra.', price: 329.9, imageUrl: img('Palmeiras\nHome', '22c55e'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 28, active: true },
  { id: 'pal-ii', name: 'Palmeiras Camisa II (Away) 24/25', team: 'Palmeiras', description: 'Camisa II branca do Verdão.', price: 329.9, imageUrl: img('Palmeiras\nAway', 'f9fafb'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 12, active: true },
  { id: 'pal-iii', name: 'Palmeiras Camisa III (Third) 24/25', team: 'Palmeiras', description: 'Camisa III alternativa.', price: 339.9, imageUrl: img('Palmeiras\nThird', '0f766e'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 6, active: true },

  // Corinthians
  { id: 'cor-i', name: 'Corinthians Camisa I (Home) 24/25', team: 'Corinthians', description: 'Camisa branca do Timão, Fiel Torcida.', price: 319.9, imageUrl: img('Corinthians\nHome', 'f9fafb'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 21, active: true },
  { id: 'cor-ii', name: 'Corinthians Camisa II (Away) 24/25', team: 'Corinthians', description: 'Camisa preta do Timão.', price: 319.9, imageUrl: img('Corinthians\nAway', '111827'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 14, active: true },
  { id: 'cor-iii', name: 'Corinthians Camisa III (Third) 24/25', team: 'Corinthians', description: 'Camisa III alternativa.', price: 339.9, imageUrl: img('Corinthians\nThird', 'ef4444'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 4, active: true },

  // São Paulo
  { id: 'spfc-i', name: 'São Paulo Camisa I (Home) 24/25', team: 'São Paulo', description: 'Tricolor paulista, tradição na faixa.', price: 319.9, imageUrl: img('Sao Paulo\nHome', 'ef4444'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 17, active: true },
  { id: 'spfc-ii', name: 'São Paulo Camisa II (Away) 24/25', team: 'São Paulo', description: 'Camisa II branca tricolor.', price: 319.9, imageUrl: img('Sao Paulo\nAway', 'f9fafb'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 8, active: true },

  // Grêmio
  { id: 'gre-i', name: 'Grêmio Camisa I (Home) 24/25', team: 'Grêmio', description: 'Tricolor gaúcho — azul, preto e branco.', price: 309.9, imageUrl: img('Gremio\nHome', '38bdf8'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 13, active: true },
  { id: 'gre-ii', name: 'Grêmio Camisa II (Away) 24/25', team: 'Grêmio', description: 'Camisa II branca do Imortal.', price: 309.9, imageUrl: img('Gremio\nAway', 'f9fafb'), images: [], sizes: defaultSizes(), category: 'Times Brasileiros', salesCount: 5, active: true },

  // Real Madrid
  { id: 'rma-i', name: 'Real Madrid Home 24/25', team: 'Real Madrid', description: 'Os Merengues — branca clássica.', price: 499.9, imageUrl: img('Real Madrid\nHome', 'f1f5f9'), images: [], sizes: defaultSizes(), category: 'Times Europeus', salesCount: 36, active: true },
  { id: 'rma-ii', name: 'Real Madrid Away 24/25', team: 'Real Madrid', description: 'Camisa II preta do Real.', price: 499.9, imageUrl: img('Real Madrid\nAway', '111827'), images: [], sizes: defaultSizes(), category: 'Times Europeus', salesCount: 22, active: true },
  { id: 'rma-iii', name: 'Real Madrid Third 24/25', team: 'Real Madrid', description: 'Camisa III alternativa.', price: 519.9, imageUrl: img('Real Madrid\nThird', 'fbbf24'), images: [], sizes: defaultSizes(), category: 'Times Europeus', salesCount: 11, active: true },

  // Barcelona
  { id: 'bar-i', name: 'FC Barcelona Home 24/25', team: 'FC Barcelona', description: 'Blaugrana — listras vermelho e azul.', price: 499.9, imageUrl: img('Barcelona\nHome', 'ef4444'), images: [], sizes: defaultSizes(), category: 'Times Europeus', salesCount: 31, active: true },
  { id: 'bar-ii', name: 'FC Barcelona Away 24/25', team: 'FC Barcelona', description: 'Camisa II amarela do Barça.', price: 499.9, imageUrl: img('Barcelona\nAway', 'fbbf24'), images: [], sizes: defaultSizes(), category: 'Times Europeus', salesCount: 18, active: true },
  { id: 'bar-iii', name: 'FC Barcelona Third 24/25', team: 'FC Barcelona', description: 'Camisa III alternativa.', price: 519.9, imageUrl: img('Barcelona\nThird', '0ea5e9'), images: [], sizes: defaultSizes(), category: 'Times Europeus', salesCount: 8, active: true },

  // Manchester City
  { id: 'mci-i', name: 'Manchester City Home 24/25', team: 'Manchester City', description: 'Sky blue — campeão inglês.', price: 459.9, imageUrl: img('Man City\nHome', '38bdf8'), images: [], sizes: defaultSizes(), category: 'Times Europeus', salesCount: 20, active: true },
  { id: 'mci-ii', name: 'Manchester City Away 24/25', team: 'Manchester City', description: 'Camisa II preta do City.', price: 459.9, imageUrl: img('Man City\nAway', '111827'), images: [], sizes: defaultSizes(), category: 'Times Europeus', salesCount: 9, active: true },

  // Seleção Brasileira
  { id: 'bra-i', name: 'Brasil Camisa I (Home) 24', team: 'Seleção Brasileira', description: 'Amarelinha — paixão de um povo.', price: 389.9, imageUrl: img('Brasil\nHome', 'fbbf24'), images: [], sizes: defaultSizes(), category: 'Seleções', salesCount: 42, active: true },
  { id: 'bra-ii', name: 'Brasil Camisa II (Away) 24', team: 'Seleção Brasileira', description: 'Camisa II azul da Seleção.', price: 389.9, imageUrl: img('Brasil\nAway', '1d4ed8'), images: [], sizes: defaultSizes(), category: 'Seleções', salesCount: 19, active: true },
  { id: 'bra-retro', name: 'Brasil Retrô 1970', team: 'Seleção Brasileira', description: 'Camisa retrô tricampeã do mundo.', price: 419.9, imageUrl: img('Brasil\nRetro 1970', 'eab308'), images: [], sizes: defaultSizes(), category: 'Seleções', salesCount: 7, active: true },

  // Seleção Argentina
  { id: 'arg-i', name: 'Argentina Camisa I (Home) 24', team: 'Seleção Argentina', description: 'Albiceleste — listras celeste e branca.', price: 389.9, imageUrl: img('Argentina\nHome', '7dd3fc'), images: [], sizes: defaultSizes(), category: 'Seleções', salesCount: 26, active: true },
  { id: 'arg-ii', name: 'Argentina Camisa II (Away) 24', team: 'Seleção Argentina', description: 'Camisa II preta da Argentina.', price: 389.9, imageUrl: img('Argentina\nAway', '111827'), images: [], sizes: defaultSizes(), category: 'Seleções', salesCount: 11, active: true },
];

export const COUPONS = [
  {
    id: 'c-bemvindo',
    code: 'BEMVINDO10',
    type: 'percent' as const,
    value: 10,
    validUntil: new Date(Date.now() + 1000 * 60 * 60 * 24 * 60).toISOString(),
    active: true,
  },
];
