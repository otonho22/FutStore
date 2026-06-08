import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';
import { api } from '../lib/api';
import { brl } from '../lib/format';
import QuickAdd from '../components/QuickAdd';
import JerseyImage from '../components/JerseyImage';
import { useAuth } from '../context/AuthContext';
import type { Product } from '../types';

type BiSummary = {
  topProducts: { productId: string; name: string; qty: number; revenue: number }[];
  bySize: { size: string; qty: number }[];
  byCategory: { category: string; qty: number }[];
  totalOrders: number;
  totalRevenue: number;
};

type Preset = '7' | '30' | '90' | 'all' | 'custom';

function presetRange(p: Preset): { from: string; to: string } {
  if (p === 'all' || p === 'custom') return { from: '', to: '' };
  const days = Number(p);
  const to = new Date();
  const from = new Date();
  from.setDate(from.getDate() - days);
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  return { from: iso(from), to: iso(to) };
}

function buildCsv(s: BiSummary, filters: { from: string; to: string; category: string; status: string }) {
  const lines: string[] = [];
  const esc = (v: any) => `"${String(v).replace(/"/g, '""')}"`;
  lines.push('Relatório FutStore');
  lines.push(`Período;${filters.from || '—'} a ${filters.to || '—'}`);
  lines.push(`Categoria;${filters.category || 'todas'}`);
  lines.push(`Status;${filters.status || 'todos'}`);
  lines.push('');
  lines.push('== Totais ==');
  lines.push('Métrica;Valor');
  lines.push(`Pedidos;${s.totalOrders}`);
  lines.push(`Receita (R$);${s.totalRevenue.toFixed(2)}`);
  lines.push('');
  lines.push('== Mais vendidos ==');
  lines.push('Produto;Quantidade;Receita (R$)');
  s.topProducts.forEach((p) => lines.push(`${esc(p.name)};${p.qty};${p.revenue.toFixed(2)}`));
  lines.push('');
  lines.push('== Por tamanho ==');
  lines.push('Tamanho;Quantidade');
  s.bySize.forEach((b) => lines.push(`${b.size};${b.qty}`));
  lines.push('');
  lines.push('== Por categoria ==');
  lines.push('Categoria;Quantidade');
  s.byCategory.forEach((b) => lines.push(`${esc(b.category)};${b.qty}`));
  return '﻿' + lines.join('\n');
}

export default function Dashboard() {
  const { role } = useAuth();
  const isAdmin = role === 'admin';

  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // BI state (admin only)
  const [preset, setPreset] = useState<Preset>('30');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [category, setCategory] = useState('');
  const [status, setStatus] = useState('');
  const [bi, setBi] = useState<BiSummary | null>(null);
  const [biLoading, setBiLoading] = useState(false);
  const [biError, setBiError] = useState<string | null>(null);

  useEffect(() => {
    api<Product[]>('/api/products?sort=salesCount&limit=10')
      .then(setProducts)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  // For admin: load all products to derive categories & low-stock count
  const [allProducts, setAllProducts] = useState<Product[]>([]);
  useEffect(() => {
    if (!isAdmin) return;
    api<Product[]>('/api/products?limit=100').then(setAllProducts).catch(() => {});
  }, [isAdmin]);

  const categories = useMemo(
    () => Array.from(new Set(allProducts.map((p) => p.category))).sort(),
    [allProducts],
  );
  const lowStockCount = useMemo(
    () => allProducts.reduce((sum, p) => sum + p.sizes.filter((s) => s.stock <= (s.minStock ?? 3)).length, 0),
    [allProducts],
  );

  // Apply preset → from/to
  useEffect(() => {
    if (preset !== 'custom') {
      const r = presetRange(preset);
      setFrom(r.from); setTo(r.to);
    }
  }, [preset]);

  // Fetch BI summary
  useEffect(() => {
    if (!isAdmin) return;
    const params = new URLSearchParams();
    if (from) params.set('from', from);
    if (to) params.set('to', to);
    if (category) params.set('category', category);
    if (status) params.set('status', status);
    setBiLoading(true);
    setBiError(null);
    api<BiSummary>(`/api/orders/bi/summary?${params.toString()}`)
      .then(setBi)
      .catch((e) => setBiError(e.message))
      .finally(() => setBiLoading(false));
  }, [isAdmin, from, to, category, status]);

  const top5 = products.slice(0, 5).map((p) => ({
    name: p.name.length > 14 ? p.name.slice(0, 14) + '…' : p.name,
    vendas: p.salesCount ?? 0,
  }));

  function exportCsv() {
    if (!bi) return;
    const csv = buildCsv(bi, { from, to, category, status });
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'relatorio-futstore.csv';
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  return (
    <div>
      <section className="hero-banner">
        <div className="hero-content">
          <span className="hero-eyebrow">FutStore · Temporada 2026</span>
          <h1 className="hero-title">
            VISTA <span className="accent">A SUA HISTÓRIA</span>
          </h1>
          <p className="hero-sub">
            As camisas oficiais dos maiores clubes do mundo e das seleções da Copa do Mundo 2026 — entrega rápida, parcelamento em até 10x.
          </p>
          <div className="hero-cta">
            <Link to="/catalog"><button className="primary btn-pill">Ver catálogo</button></Link>
            <Link to="/copa-2026"><button className="btn-pill">Copa 2026 →</button></Link>
          </div>
        </div>
        <div style={{ position: 'relative', zIndex: 1, display: 'grid', placeItems: 'center' }}>
          <div style={{ width: 'min(360px, 100%)', aspectRatio: '1/1', borderRadius: 'var(--radius-lg)', overflow: 'hidden', boxShadow: 'var(--shadow-lg)', transform: 'rotate(-3deg)' }}>
            <JerseyImage imageUrl="/jerseys/brasil-jogador.jpg" team="Brasil" name="FutStore" rounded={false} />
          </div>
        </div>
      </section>

      <h2 className="section-title">Top vendas</h2>

      {error && <div className="alert error">{error}</div>}

      {isAdmin && (
        <div className="card" style={{ marginBottom: '1.5rem' }}>
          <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
            <h2 className="section-title" style={{ margin: 0 }}>📊 BI — Admin</h2>
            <button onClick={exportCsv} disabled={!bi}>⬇ Exportar CSV</button>
          </div>

          <div className="row" style={{ flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
            <div className="col" style={{ flex: '1 1 140px' }}>
              <label>Período</label>
              <select value={preset} onChange={(e) => setPreset(e.target.value as Preset)}>
                <option value="7">Últimos 7 dias</option>
                <option value="30">Últimos 30 dias</option>
                <option value="90">Últimos 90 dias</option>
                <option value="all">Tudo</option>
                <option value="custom">Personalizado</option>
              </select>
            </div>
            <div className="col" style={{ flex: '1 1 130px' }}>
              <label>De</label>
              <input type="date" value={from}
                onChange={(e) => { setPreset('custom'); setFrom(e.target.value); }} />
            </div>
            <div className="col" style={{ flex: '1 1 130px' }}>
              <label>Até</label>
              <input type="date" value={to}
                onChange={(e) => { setPreset('custom'); setTo(e.target.value); }} />
            </div>
            <div className="col" style={{ flex: '1 1 160px' }}>
              <label>Categoria</label>
              <select value={category} onChange={(e) => setCategory(e.target.value)}>
                <option value="">Todas</option>
                {categories.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>
            <div className="col" style={{ flex: '1 1 140px' }}>
              <label>Status</label>
              <select value={status} onChange={(e) => setStatus(e.target.value)}>
                <option value="">Todos</option>
                <option value="pendente">Pendente</option>
                <option value="pago">Pago</option>
                <option value="enviado">Enviado</option>
                <option value="entregue">Entregue</option>
                <option value="cancelado">Cancelado</option>
              </select>
            </div>
          </div>

          {biError && <div className="alert error" style={{ marginTop: 12 }}>{biError}</div>}

          <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', marginTop: 16 }}>
            <div className="card">
              <div className="muted">Total de pedidos</div>
              <div style={{ fontSize: '1.8rem', fontWeight: 700 }}>{biLoading ? '…' : (bi?.totalOrders ?? 0)}</div>
            </div>
            <div className="card">
              <div className="muted">Receita</div>
              <div style={{ fontSize: '1.8rem', fontWeight: 700 }}>{biLoading ? '…' : brl(bi?.totalRevenue ?? 0)}</div>
            </div>
            <div className="card">
              <div className="muted">Alertas de estoque</div>
              <div style={{ fontSize: '1.8rem', fontWeight: 700, color: lowStockCount > 0 ? '#fbbf24' : undefined }}>
                {lowStockCount}
              </div>
              <div className="muted" style={{ fontSize: '0.8rem' }}>variações ≤ mínimo</div>
            </div>
          </div>

          {bi && bi.bySize.length > 0 && (
            <div style={{ marginTop: 16 }}>
              <h3 className="section-title" style={{ marginTop: 0 }}>Mais vendidos por tamanho</h3>
              <div style={{ width: '100%', height: 240 }}>
                <ResponsiveContainer>
                  <BarChart data={bi.bySize}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2f3a" />
                    <XAxis dataKey="size" stroke="#9aa0aa" />
                    <YAxis stroke="#9aa0aa" allowDecimals={false} />
                    <Tooltip contentStyle={{ background: '#171a21', border: '1px solid #2a2f3a' }} />
                    <Bar dataKey="qty" fill="#38bdf8" radius={[6, 6, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}

          {bi && bi.topProducts.length > 0 && (
            <div style={{ marginTop: 16 }}>
              <h3 className="section-title" style={{ marginTop: 0 }}>Mais vendidos (período/filtros)</h3>
              <div style={{ width: '100%', height: 240 }}>
                <ResponsiveContainer>
                  <BarChart data={bi.topProducts.slice(0, 8).map((p) => ({
                    name: p.name.length > 16 ? p.name.slice(0, 16) + '…' : p.name,
                    qty: p.qty,
                  }))}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2f3a" />
                    <XAxis dataKey="name" stroke="#9aa0aa" />
                    <YAxis stroke="#9aa0aa" allowDecimals={false} />
                    <Tooltip contentStyle={{ background: '#171a21', border: '1px solid #2a2f3a' }} />
                    <Bar dataKey="qty" fill="#22c55e" radius={[6, 6, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}
        </div>
      )}

      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', marginBottom: '1.5rem' }}>
        <div className="card">
          <div className="muted">Produtos ativos</div>
          <div style={{ fontSize: '1.8rem', fontWeight: 700 }}>{products.length}</div>
        </div>
        <div className="card">
          <div className="muted">Total de vendas (top 10)</div>
          <div style={{ fontSize: '1.8rem', fontWeight: 700 }}>
            {products.reduce((s, p) => s + (p.salesCount ?? 0), 0)}
          </div>
        </div>
        <div className="card">
          <div className="muted">Top campeã</div>
          <div style={{ fontSize: '1.2rem', fontWeight: 600 }}>
            {products[0]?.name ?? '—'}
          </div>
        </div>
      </div>

      {top5.length > 0 && (
        <div className="card" style={{ marginBottom: '1.5rem' }}>
          <h2 className="section-title" style={{ marginTop: 0 }}>Top 5 — vendas (geral)</h2>
          <div style={{ width: '100%', height: 280 }}>
            <ResponsiveContainer>
              <BarChart data={top5}>
                <CartesianGrid strokeDasharray="3 3" stroke="#2a2f3a" />
                <XAxis dataKey="name" stroke="#9aa0aa" />
                <YAxis stroke="#9aa0aa" allowDecimals={false} />
                <Tooltip contentStyle={{ background: '#171a21', border: '1px solid #2a2f3a' }} />
                <Bar dataKey="vendas" fill="#22c55e" radius={[6, 6, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      )}

      <h2 className="section-title">Ranking de mais vendidas</h2>
      {loading ? (
        <p className="muted">Carregando…</p>
      ) : products.length === 0 ? (
        <div className="card">
          <p className="muted">Nenhum produto cadastrado ainda. Se você é admin, comece em <Link to="/admin/products">Produtos</Link>.</p>
        </div>
      ) : (
        <div className="product-grid">
          {products.map((p, idx) => (
            <div key={p.id} className="card product-card">
              <Link to={`/catalog/${p.id}`} style={{ color: 'inherit', display: 'block' }}>
                <div style={{ position: 'relative' }}>
                  <JerseyImage imageUrl={p.imageUrl} team={p.team} name={p.name} alt={p.name} />
                  <span className="tag success" style={{ position: 'absolute', top: 8, left: 8 }}>
                    #{idx + 1} • {p.salesCount ?? 0} vendas
                  </span>
                </div>
                <div className="name">{p.name}</div>
                <div className="muted" style={{ fontSize: '0.85rem' }}>{p.team}</div>
                <div className="price">{brl(p.price)}</div>
              </Link>
              <QuickAdd product={p} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
