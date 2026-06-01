import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';
import { api } from '../lib/api';
import { brl } from '../lib/format';
import QuickAdd from '../components/QuickAdd';
import type { Product } from '../types';

export default function Dashboard() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<Product[]>('/api/products?sort=salesCount&limit=10')
      .then(setProducts)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  const top5 = products.slice(0, 5).map((p) => ({
    name: p.name.length > 14 ? p.name.slice(0, 14) + '…' : p.name,
    vendas: p.salesCount ?? 0,
  }));

  return (
    <div>
      <h1 className="page-title">Dashboard</h1>
      <p className="muted">As camisas mais vendidas da loja.</p>

      {error && <div className="alert error">{error}</div>}

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
          <h2 className="section-title" style={{ marginTop: 0 }}>Top 5 — vendas</h2>
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
                  <img src={p.imageUrl} alt={p.name} />
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
