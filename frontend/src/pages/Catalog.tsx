import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../lib/api';
import { brl } from '../lib/format';
import QuickAdd from '../components/QuickAdd';
import JerseyImage from '../components/JerseyImage';
import type { Product } from '../types';

export default function Catalog() {
  const [products, setProducts] = useState<Product[]>([]);
  const [category, setCategory] = useState<string>('all');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api<Product[]>('/api/products?limit=100').then(setProducts).finally(() => setLoading(false));
  }, []);

  const categories = useMemo(() => {
    return Array.from(new Set(products.map((p) => p.category))).sort();
  }, [products]);

  const filtered = category === 'all'
    ? products
    : products.filter((p) => p.category === category);

  return (
    <div>
      <h1 className="page-title">Catálogo</h1>
      <div className="row" style={{ marginBottom: '1rem' }}>
        <label style={{ marginBottom: 0 }}>Categoria:</label>
        <select value={category} onChange={(e) => setCategory(e.target.value)} style={{ maxWidth: 240 }}>
          <option value="all">Todas</option>
          {categories.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
      </div>

      {loading ? (
        <p className="muted">Carregando…</p>
      ) : filtered.length === 0 ? (
        <div className="card"><p className="muted">Nenhum produto encontrado.</p></div>
      ) : (
        <div className="product-grid">
          {filtered.map((p) => (
            <div key={p.id} className="card product-card">
              <Link to={`/catalog/${p.id}`} style={{ color: 'inherit', display: 'block' }}>
                <JerseyImage imageUrl={p.imageUrl} team={p.team} name={p.name} alt={p.name} />
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
