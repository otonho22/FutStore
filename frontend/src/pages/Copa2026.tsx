import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { brl } from '../lib/format';
import { useCart } from '../context/CartContext';
import JerseyImage from '../components/JerseyImage';
import type { Product } from '../types';

const CATEGORY = 'Copa do Mundo 2026';
const PROMO_PCT = 15;
const PROMO_CODE = 'COPA2026';

function discounted(price: number): number {
  return price * (1 - PROMO_PCT / 100);
}

const CONFED_ORDER = [
  'CONMEBOL', 'CONCACAF (Host)', 'CONCACAF', 'UEFA', 'CAF', 'AFC', 'OFC', 'Playoff',
];

function detectConfed(p: Product): string {
  // Description ends with "— XXX." (added in seed). Brasil custom strings won't match.
  const m = p.description.match(/—\s*([^.]+)\.?\s*$/);
  return m ? m[1].trim() : 'Outros';
}

export default function Copa2026() {
  const navigate = useNavigate();
  const { add } = useCart();
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [confedFilter, setConfedFilter] = useState<string>('all');

  useEffect(() => {
    api<Product[]>(`/api/products?category=${encodeURIComponent(CATEGORY)}&limit=100`)
      .then(setProducts)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  const brasil = useMemo(() => products.filter((p) => p.team === 'Brasil'), [products]);
  const brasilJogador = brasil.find((p) => p.name.includes('Jogador'));
  const brasilTorcedor = brasil.find((p) => p.name.includes('Torcedor'));
  const others = useMemo(() => products.filter((p) => p.team !== 'Brasil'), [products]);

  const grouped = useMemo(() => {
    const map = new Map<string, Product[]>();
    for (const p of others) {
      const c = detectConfed(p);
      const arr = map.get(c) ?? [];
      arr.push(p);
      map.set(c, arr);
    }
    return Array.from(map.entries()).sort(([a], [b]) => {
      const ia = CONFED_ORDER.indexOf(a); const ib = CONFED_ORDER.indexOf(b);
      return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
    });
  }, [others]);

  const visibleConfeds = confedFilter === 'all' ? grouped : grouped.filter(([c]) => c === confedFilter);

  function addPromo(p: Product) {
    const firstSize = p.sizes.find((s) => s.stock > 0);
    if (!firstSize) return;
    add({
      productId: p.id, name: p.name, size: firstSize.size,
      unitPrice: p.price, quantity: 1, imageUrl: p.imageUrl,
    });
    navigate('/cart');
  }

  return (
    <div className="copa2026">
      <style>{`
        .copa2026 {
          background: #000;
          color: #fff;
          margin: 0 -2rem -4rem;
          padding: 0;
          min-height: 100vh;
          font-family: 'Inter', -apple-system, sans-serif;
        }
        @media (max-width: 768px) {
          .copa2026 { margin: 0 -1.25rem -2rem; }
        }
        .copa-hero {
          position: relative;
          overflow: hidden;
          background: linear-gradient(135deg, #009c3b 0%, #002776 50%, #000 100%);
          padding: 3rem 2rem;
          min-height: 520px;
          display: grid;
          grid-template-columns: 1.1fr 1fr;
          align-items: center;
          gap: 2rem;
        }
        @media (max-width: 900px) {
          .copa-hero { grid-template-columns: 1fr; min-height: auto; padding: 2rem 1rem; }
        }
        .copa-hero::before {
          content: '';
          position: absolute;
          inset: 0;
          background: radial-gradient(ellipse at top right, rgba(251, 191, 36, 0.18), transparent 60%);
          pointer-events: none;
        }
        .copa-hero-text { position: relative; z-index: 1; }
        .copa-eyebrow {
          display: inline-block;
          font-size: 0.75rem;
          letter-spacing: 0.2em;
          font-weight: 600;
          padding: 6px 12px;
          border: 1px solid rgba(251, 191, 36, 0.6);
          color: #fbbf24;
          border-radius: 999px;
          margin-bottom: 1.2rem;
          text-transform: uppercase;
        }
        .copa-title {
          font-size: clamp(2.5rem, 6vw, 5rem);
          font-weight: 900;
          line-height: 0.95;
          letter-spacing: -0.03em;
          margin: 0 0 1rem;
          text-transform: uppercase;
        }
        .copa-title .yellow { color: #fbbf24; }
        .copa-subtitle {
          font-size: clamp(1rem, 1.4vw, 1.2rem);
          color: rgba(255,255,255,0.75);
          margin: 0 0 2rem;
          max-width: 480px;
          line-height: 1.5;
        }
        .copa-cta-row { display: flex; gap: 12px; flex-wrap: wrap; }
        .copa-btn {
          padding: 14px 28px;
          border-radius: 999px;
          border: none;
          font-weight: 700;
          font-size: 0.95rem;
          cursor: pointer;
          letter-spacing: 0.02em;
          transition: transform 0.15s, background 0.15s;
        }
        .copa-btn:hover { transform: translateY(-2px); }
        .copa-btn-primary { background: #fff; color: #000; }
        .copa-btn-ghost { background: transparent; color: #fff; border: 1px solid rgba(255,255,255,0.4); }
        .copa-promo-badge {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          background: #fbbf24;
          color: #000;
          font-weight: 800;
          font-size: 0.8rem;
          padding: 6px 12px;
          border-radius: 6px;
          letter-spacing: 0.05em;
          margin-top: 1rem;
        }
        .copa-hero-img {
          position: relative;
          z-index: 1;
          aspect-ratio: 1/1;
          max-width: 480px;
          margin: 0 auto;
          border-radius: 16px;
          overflow: hidden;
          box-shadow: 0 30px 80px rgba(0,0,0,0.5);
          transform: rotate(-2deg);
        }

        .copa-section { padding: 4rem 2rem; }
        @media (max-width: 768px) { .copa-section { padding: 2.5rem 1rem; } }
        .copa-section-head {
          display: flex;
          justify-content: space-between;
          align-items: flex-end;
          margin-bottom: 2rem;
          gap: 1rem;
          flex-wrap: wrap;
        }
        .copa-section-title {
          font-size: clamp(1.8rem, 3vw, 2.8rem);
          font-weight: 900;
          letter-spacing: -0.02em;
          margin: 0;
          text-transform: uppercase;
        }
        .copa-section-sub { color: rgba(255,255,255,0.6); font-size: 0.95rem; margin-top: 0.5rem; }

        .brasil-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 1.5rem;
          max-width: 1100px;
          margin: 0 auto;
        }
        @media (max-width: 700px) { .brasil-grid { grid-template-columns: 1fr; } }

        .brasil-card {
          background: linear-gradient(180deg, #0e0e0e, #161616);
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 16px;
          overflow: hidden;
          transition: border-color 0.2s, transform 0.2s;
          cursor: pointer;
          position: relative;
        }
        .brasil-card:hover { border-color: #fbbf24; transform: translateY(-4px); }
        .brasil-card-img {
          aspect-ratio: 1/1;
          background: #1a1a1a;
          position: relative;
          overflow: hidden;
        }
        .brasil-card-img > * { width: 100%; height: 100%; }
        .brasil-tag {
          position: absolute; top: 14px; left: 14px;
          background: #fbbf24; color: #000;
          font-size: 0.7rem; font-weight: 800;
          padding: 4px 10px; border-radius: 4px;
          letter-spacing: 0.05em;
          z-index: 2;
        }
        .brasil-tag.discount { background: #ef4444; color: #fff; top: 14px; left: auto; right: 14px; }
        .brasil-card-body { padding: 1.5rem; }
        .brasil-kicker {
          font-size: 0.7rem; letter-spacing: 0.15em;
          color: #fbbf24; font-weight: 600; text-transform: uppercase;
          margin-bottom: 0.4rem;
        }
        .brasil-name {
          font-size: 1.4rem; font-weight: 800; margin: 0 0 0.5rem;
          letter-spacing: -0.01em;
        }
        .brasil-desc { color: rgba(255,255,255,0.6); font-size: 0.9rem; line-height: 1.4; margin-bottom: 1.2rem; }
        .price-row { display: flex; align-items: baseline; gap: 0.6rem; margin-bottom: 1.2rem; }
        .price-now { font-size: 1.6rem; font-weight: 800; color: #fff; }
        .price-was { color: rgba(255,255,255,0.4); text-decoration: line-through; font-size: 0.95rem; }
        .price-pct { color: #22c55e; font-weight: 700; font-size: 0.85rem; }

        .confed-filter {
          display: flex; gap: 8px; flex-wrap: wrap;
          margin-bottom: 1.5rem;
        }
        .confed-chip {
          background: rgba(255,255,255,0.05);
          color: rgba(255,255,255,0.7);
          border: 1px solid rgba(255,255,255,0.1);
          padding: 8px 16px;
          border-radius: 999px;
          font-size: 0.85rem;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.15s;
        }
        .confed-chip:hover { color: #fff; border-color: rgba(255,255,255,0.3); }
        .confed-chip.active { background: #fff; color: #000; border-color: #fff; }

        .confed-block { margin-bottom: 3rem; }
        .confed-header { font-size: 0.85rem; letter-spacing: 0.2em; font-weight: 700; color: rgba(255,255,255,0.5); margin-bottom: 1rem; text-transform: uppercase; }
        .teams-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
          gap: 1rem;
        }
        .team-card {
          background: #0e0e0e;
          border: 1px solid rgba(255,255,255,0.06);
          border-radius: 12px;
          overflow: hidden;
          text-decoration: none;
          color: inherit;
          transition: transform 0.15s, border-color 0.15s;
          display: block;
        }
        .team-card:hover { transform: translateY(-3px); border-color: rgba(255,255,255,0.2); }
        .team-card-img { aspect-ratio: 1/1; background: #1a1a1a; }
        .team-card-img > * { width: 100%; height: 100%; }
        .team-card-body { padding: 0.9rem 1rem 1.1rem; }
        .team-card-name { font-size: 0.95rem; font-weight: 700; margin: 0 0 0.3rem; }
        .team-card-price { font-size: 1rem; font-weight: 700; color: #fff; }
        .team-card-promo { display: inline-block; font-size: 0.65rem; background: #fbbf24; color: #000; padding: 2px 6px; border-radius: 3px; font-weight: 800; margin-left: 6px; vertical-align: middle; }

        .copa-loading, .copa-error { text-align: center; padding: 4rem; color: rgba(255,255,255,0.6); }
      `}</style>

      <section className="copa-hero">
        <div className="copa-hero-text">
          <span className="copa-eyebrow">FIFA World Cup 2026</span>
          <h1 className="copa-title">
            BRASIL<br />
            <span className="yellow">RUMO AO HEXA</span>
          </h1>
          <p className="copa-subtitle">
            A camisa oficial da Seleção 2026 chegou. Versões Jogador e Torcedor disponíveis agora — com tudo que o futebol brasileiro representa.
          </p>
          <div className="copa-cta-row">
            <a href="#brasil-section" className="copa-btn copa-btn-primary">Comprar Brasil</a>
            <a href="#todas-section" className="copa-btn copa-btn-ghost">Ver todas as seleções</a>
          </div>
          <div className="copa-promo-badge">
            🎟️ Use <strong style={{ letterSpacing: '0.1em' }}>{PROMO_CODE}</strong> · {PROMO_PCT}% OFF em toda Copa
          </div>
        </div>
        <div className="copa-hero-img">
          <JerseyImage imageUrl="/jerseys/brasil-jogador.jpg" team="Brasil" name="Brasil 2026" alt="Camisa Brasil 2026" rounded={false} />
        </div>
      </section>

      {error && <div className="copa-error">{error}</div>}
      {loading && <div className="copa-loading">Carregando seleções…</div>}

      {!loading && brasil.length > 0 && (
        <section className="copa-section" id="brasil-section" style={{ background: '#0a0a0a' }}>
          <div className="copa-section-head">
            <div>
              <h2 className="copa-section-title">A Camisa do Brasil</h2>
              <div className="copa-section-sub">Duas versões. Mesma paixão.</div>
            </div>
          </div>
          <div className="brasil-grid">
            {[brasilJogador, brasilTorcedor].filter(Boolean).map((p) => {
              const kicker = p!.name.includes('Jogador') ? 'Versão Atleta · Premium' : 'Versão Fã · Conforto';
              const oldPrice = p!.price;
              const newPrice = discounted(oldPrice);
              return (
                <div key={p!.id} className="brasil-card" onClick={() => navigate(`/catalog/${p!.id}`)}>
                  <span className="brasil-tag">{p!.name.includes('Jogador') ? 'JOGADOR' : 'TORCEDOR'}</span>
                  <span className="brasil-tag discount">-{PROMO_PCT}% OFF</span>
                  <div className="brasil-card-img">
                    <JerseyImage imageUrl={p!.imageUrl} team="Brasil" name={p!.name} rounded={false} />
                  </div>
                  <div className="brasil-card-body">
                    <div className="brasil-kicker">{kicker}</div>
                    <h3 className="brasil-name">{p!.name.replace('Brasil 2026 — ', '')}</h3>
                    <p className="brasil-desc">{p!.description}</p>
                    <div className="price-row">
                      <span className="price-now">{brl(newPrice)}</span>
                      <span className="price-was">{brl(oldPrice)}</span>
                      <span className="price-pct">-{PROMO_PCT}%</span>
                    </div>
                    <button className="copa-btn copa-btn-primary" style={{ width: '100%' }}
                      onClick={(e) => { e.stopPropagation(); addPromo(p!); }}>
                      Adicionar ao carrinho
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {!loading && others.length > 0 && (
        <section className="copa-section" id="todas-section">
          <div className="copa-section-head">
            <div>
              <h2 className="copa-section-title">Todas as 48 Seleções</h2>
              <div className="copa-section-sub">{others.length} camisas oficiais · -{PROMO_PCT}% com cupom {PROMO_CODE}</div>
            </div>
          </div>

          <div className="confed-filter">
            <button className={`confed-chip ${confedFilter === 'all' ? 'active' : ''}`}
              onClick={() => setConfedFilter('all')}>Todas</button>
            {grouped.map(([c]) => (
              <button key={c} className={`confed-chip ${confedFilter === c ? 'active' : ''}`}
                onClick={() => setConfedFilter(c)}>{c}</button>
            ))}
          </div>

          {visibleConfeds.map(([confed, list]) => (
            <div key={confed} className="confed-block">
              <h3 className="confed-header">{confed} · {list.length} seleções</h3>
              <div className="teams-grid">
                {list.map((p) => {
                  const newPrice = discounted(p.price);
                  return (
                    <Link key={p.id} to={`/catalog/${p.id}`} className="team-card">
                      <div className="team-card-img">
                        <JerseyImage imageUrl={p.imageUrl} team={p.team} name={p.name} rounded={false} />
                      </div>
                      <div className="team-card-body">
                        <div className="team-card-name">{p.team}<span className="team-card-promo">-{PROMO_PCT}%</span></div>
                        <div className="team-card-price">{brl(newPrice)}
                          <span style={{ color: 'rgba(255,255,255,0.35)', fontSize: '0.78rem', textDecoration: 'line-through', marginLeft: 6, fontWeight: 400 }}>
                            {brl(p.price)}
                          </span>
                        </div>
                      </div>
                    </Link>
                  );
                })}
              </div>
            </div>
          ))}
        </section>
      )}
    </div>
  );
}
