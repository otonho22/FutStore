import { useMemo, useState } from 'react';

type Props = {
  imageUrl?: string;
  team?: string;
  name?: string;
  alt?: string;
  size?: number; // px; if not set, fills 100% width
  rounded?: boolean;
  className?: string;
  style?: React.CSSProperties;
};

const TEAM_COLOR: Record<string, string> = {
  // Clubes
  Flamengo: 'ef4444',
  Palmeiras: '22c55e',
  Corinthians: 'f9fafb',
  'São Paulo': 'ef4444',
  Grêmio: '38bdf8',
  'Real Madrid': 'f1f5f9',
  'FC Barcelona': 'ef4444',
  'Manchester City': '38bdf8',
  // Seleções (entradas legadas)
  'Seleção Brasileira': 'fbbf24',
  'Seleção Argentina': '7dd3fc',
  // Copa 2026 — CONMEBOL
  Brasil: 'fbbf24',
  Argentina: '7dd3fc',
  Uruguai: '38bdf8',
  'Colômbia': 'fde047',
  Equador: 'fbbf24',
  Paraguai: 'ef4444',
  Bolívia: '16a34a',
  // CONCACAF
  'Estados Unidos': '1d4ed8',
  México: '16a34a',
  Canadá: 'ef4444',
  'Costa Rica': 'ef4444',
  Panamá: 'dc2626',
  Jamaica: 'fbbf24',
  // UEFA
  França: '1d4ed8',
  Inglaterra: 'f9fafb',
  Espanha: 'dc2626',
  Alemanha: '111827',
  Itália: '1e3a8a',
  Portugal: 'dc2626',
  Holanda: 'f97316',
  Bélgica: 'b91c1c',
  Croácia: 'dc2626',
  Dinamarca: 'dc2626',
  Suíça: 'dc2626',
  Sérvia: 'b91c1c',
  Áustria: 'dc2626',
  Polônia: 'f9fafb',
  'País de Gales': 'dc2626',
  Escócia: '1e40af',
  // CAF
  Marrocos: 'b91c1c',
  Senegal: '16a34a',
  Egito: 'b91c1c',
  Nigéria: '16a34a',
  Argélia: '16a34a',
  Camarões: '16a34a',
  Gana: 'f9fafb',
  Tunísia: 'dc2626',
  'Costa do Marfim': 'f97316',
  // AFC
  Japão: '1e3a8a',
  'Coreia do Sul': 'dc2626',
  'Arábia Saudita': '16a34a',
  Irã: 'f9fafb',
  Austrália: 'fbbf24',
  Catar: '7c1d6f',
  Uzbequistão: 'f9fafb',
  Jordânia: 'b91c1c',
  // OFC + Playoff
  'Nova Zelândia': 'f9fafb',
  Suriname: '16a34a',
};

const TEAM_INITIALS: Record<string, string> = {
  Flamengo: 'FLA', Palmeiras: 'PAL', Corinthians: 'COR', 'São Paulo': 'SAO', Grêmio: 'GRE',
  'Real Madrid': 'RMA', 'FC Barcelona': 'BAR', 'Manchester City': 'MCI',
  'Seleção Brasileira': 'BRA', 'Seleção Argentina': 'ARG',
  // Copa 2026 (códigos FIFA)
  Brasil: 'BRA', Argentina: 'ARG', Uruguai: 'URU', 'Colômbia': 'COL', Equador: 'EQU',
  Paraguai: 'PAR', Bolívia: 'BOL',
  'Estados Unidos': 'USA', México: 'MEX', Canadá: 'CAN', 'Costa Rica': 'CRC',
  Panamá: 'PAN', Jamaica: 'JAM',
  França: 'FRA', Inglaterra: 'ENG', Espanha: 'ESP', Alemanha: 'GER', Itália: 'ITA',
  Portugal: 'POR', Holanda: 'NED', Bélgica: 'BEL', Croácia: 'CRO', Dinamarca: 'DEN',
  Suíça: 'SUI', Sérvia: 'SRB', Áustria: 'AUT', Polônia: 'POL', 'País de Gales': 'WAL', Escócia: 'SCO',
  Marrocos: 'MAR', Senegal: 'SEN', Egito: 'EGY', Nigéria: 'NGA', Argélia: 'ALG',
  Camarões: 'CMR', Gana: 'GHA', Tunísia: 'TUN', 'Costa do Marfim': 'CIV',
  Japão: 'JPN', 'Coreia do Sul': 'KOR', 'Arábia Saudita': 'KSA', Irã: 'IRN',
  Austrália: 'AUS', Catar: 'QAT', Uzbequistão: 'UZB', Jordânia: 'JOR',
  'Nova Zelândia': 'NZL', Suriname: 'SUR',
};

function parsePlaceholderColor(url: string): string | null {
  const m = url.match(/placehold\.co\/\d+x\d+\/[^/]+\/([0-9a-fA-F]{3,8})\//);
  return m ? m[1] : null;
}

function hashToColor(s: string): string {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) & 0xffffff;
  return h.toString(16).padStart(6, '0');
}

function luminance(hex: string): number {
  const h = hex.length === 3 ? hex.split('').map((c) => c + c).join('') : hex.slice(0, 6);
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

function initials(team?: string, name?: string): string {
  if (team && TEAM_INITIALS[team]) return TEAM_INITIALS[team];
  const src = (team || name || '').trim();
  if (!src) return '⚽';
  const parts = src.split(/\s+/);
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return src.slice(0, 3).toUpperCase();
}

export default function JerseyImage({ imageUrl, team, name, alt, size, rounded = true, className, style }: Props) {
  const [imgFailed, setImgFailed] = useState(false);

  const isPlaceholder = !imageUrl || imageUrl.includes('placehold.co');
  const showSvg = isPlaceholder || imgFailed;

  const color = useMemo(() => {
    if (imageUrl) {
      const fromUrl = parsePlaceholderColor(imageUrl);
      if (fromUrl) return fromUrl;
    }
    if (team && TEAM_COLOR[team]) return TEAM_COLOR[team];
    return hashToColor(team || name || 'team');
  }, [imageUrl, team, name]);

  const baseStyle: React.CSSProperties = size
    ? { width: size, height: size, ...style }
    : { width: '100%', aspectRatio: '1 / 1', display: 'block', ...style };
  if (rounded) baseStyle.borderRadius = baseStyle.borderRadius ?? 8;

  if (!showSvg) {
    return (
      <img
        src={imageUrl}
        alt={alt ?? name ?? team ?? ''}
        onError={() => setImgFailed(true)}
        style={{ ...baseStyle, objectFit: 'cover', background: '#171a21' }}
        className={className}
      />
    );
  }

  const lum = luminance(color);
  const textColor = lum > 0.6 ? '#0f1115' : '#ffffff';
  const sleeveColor = lum > 0.6 ? '#0f1115' : '#ffffff';
  const shirt = `#${color}`;
  const label = initials(team, name);

  return (
    <div
      role="img"
      aria-label={alt ?? name ?? team ?? 'Camisa'}
      className={className}
      style={{ ...baseStyle, background: 'linear-gradient(135deg,#171a21,#0f1115)', overflow: 'hidden', position: 'relative' }}
    >
      <svg viewBox="0 0 200 200" width="100%" height="100%" preserveAspectRatio="xMidYMid meet">
        <defs>
          <linearGradient id={`g-${color}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={shirt} stopOpacity="1" />
            <stop offset="100%" stopColor={shirt} stopOpacity="0.85" />
          </linearGradient>
        </defs>
        {/* sleeves */}
        <path d="M30 60 L60 40 L75 75 L50 95 Z" fill={sleeveColor} opacity="0.85" />
        <path d="M170 60 L140 40 L125 75 L150 95 Z" fill={sleeveColor} opacity="0.85" />
        {/* body */}
        <path d="M60 40 L80 30 Q100 50 120 30 L140 40 L135 170 Q100 180 65 170 Z" fill={`url(#g-${color})`} stroke={textColor} strokeOpacity="0.15" strokeWidth="1.5" />
        {/* collar */}
        <path d="M80 30 Q100 50 120 30 L115 45 Q100 58 85 45 Z" fill={textColor} opacity="0.18" />
        {/* number/label */}
        <text x="100" y="120" textAnchor="middle" fontFamily="Inter, system-ui, sans-serif" fontWeight="800" fontSize="36" fill={textColor}>
          {label}
        </text>
      </svg>
    </div>
  );
}
