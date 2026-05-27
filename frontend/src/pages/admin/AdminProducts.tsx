import { useEffect, useState, type FormEvent } from 'react';
import { api } from '../../lib/api';
import { brl } from '../../lib/format';
import type { Product, ProductSize } from '../../types';

const EMPTY: Omit<Product, 'id'> = {
  name: '', team: '', description: '', price: 0,
  imageUrl: '', images: [],
  sizes: [
    { size: 'P', stock: 0 }, { size: 'M', stock: 0 },
    { size: 'G', stock: 0 }, { size: 'GG', stock: 0 },
  ],
  category: 'Times Brasileiros', active: true,
};

export default function AdminProducts() {
  const [products, setProducts] = useState<Product[]>([]);
  const [editing, setEditing] = useState<Product | null>(null);
  const [draft, setDraft] = useState<Omit<Product, 'id'>>(EMPTY);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  async function refresh() {
    setProducts(await api<Product[]>('/api/products?limit=100'));
  }
  useEffect(() => { refresh(); }, []);

  function startNew() {
    setEditing(null);
    setDraft(EMPTY);
  }
  function startEdit(p: Product) {
    setEditing(p);
    const { id: _id, ...rest } = p;
    void _id;
    setDraft({ ...EMPTY, ...rest });
  }

  function setSize(idx: number, field: keyof ProductSize, value: any) {
    setDraft((d) => {
      const sizes = [...d.sizes];
      sizes[idx] = { ...sizes[idx], [field]: value };
      return { ...d, sizes };
    });
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSaving(true);
    try {
      const body = {
        ...draft,
        price: Number(draft.price),
        sizes: draft.sizes.map((s) => ({ size: s.size, stock: Number(s.stock) })),
        images: draft.images.filter(Boolean),
      };
      if (editing) {
        await api(`/api/products/${editing.id}`, { method: 'PUT', body: JSON.stringify(body) });
      } else {
        await api('/api/products', { method: 'POST', body: JSON.stringify(body) });
      }
      await refresh();
      startNew();
    } catch (e: any) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  }

  async function onDelete(id: string) {
    if (!confirm('Excluir produto?')) return;
    await api(`/api/products/${id}`, { method: 'DELETE' });
    await refresh();
  }

  return (
    <div>
      <h1 className="page-title">Admin — Produtos</h1>

      <div className="grid" style={{ gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)', alignItems: 'start' }}>
        <form className="card col" onSubmit={onSubmit}>
          <h2 className="section-title" style={{ marginTop: 0 }}>
            {editing ? `Editar: ${editing.name}` : 'Novo produto'}
          </h2>
          {error && <div className="alert error">{error}</div>}
          <div><label>Nome</label>
            <input required value={draft.name}
              onChange={(e) => setDraft({ ...draft, name: e.target.value })} /></div>
          <div className="row">
            <div style={{ flex: 1 }}><label>Time</label>
              <input required value={draft.team}
                onChange={(e) => setDraft({ ...draft, team: e.target.value })} /></div>
            <div style={{ flex: 1 }}><label>Categoria</label>
              <input required value={draft.category}
                onChange={(e) => setDraft({ ...draft, category: e.target.value })} /></div>
          </div>
          <div><label>Descrição</label>
            <textarea rows={3} value={draft.description}
              onChange={(e) => setDraft({ ...draft, description: e.target.value })} /></div>
          <div className="row">
            <div style={{ flex: 1 }}><label>Preço (R$)</label>
              <input type="number" step="0.01" min={0} required value={draft.price}
                onChange={(e) => setDraft({ ...draft, price: Number(e.target.value) })} /></div>
            <div style={{ flex: 2 }}><label>URL da imagem principal</label>
              <input type="url" required value={draft.imageUrl}
                onChange={(e) => setDraft({ ...draft, imageUrl: e.target.value })} /></div>
          </div>
          <div><label>Imagens adicionais (até 4 URLs, uma por linha)</label>
            <textarea rows={2} value={draft.images.join('\n')}
              onChange={(e) => setDraft({ ...draft, images: e.target.value.split('\n').map((s) => s.trim()).filter(Boolean).slice(0, 4) })} /></div>
          <div>
            <label>Tamanhos e estoque</label>
            <div className="row">
              {draft.sizes.map((s, idx) => (
                <div key={idx} className="col" style={{ flex: 1, minWidth: 90 }}>
                  <input value={s.size} onChange={(e) => setSize(idx, 'size', e.target.value)} />
                  <input type="number" min={0} value={s.stock}
                    onChange={(e) => setSize(idx, 'stock', Number(e.target.value))} />
                </div>
              ))}
            </div>
          </div>
          <label style={{ display: 'flex', gap: '0.5rem' }}>
            <input type="checkbox" style={{ width: 'auto' }} checked={draft.active}
              onChange={(e) => setDraft({ ...draft, active: e.target.checked })} />
            <span style={{ color: 'var(--text)' }}>Ativo</span>
          </label>
          <div className="row">
            <button type="submit" className="primary" disabled={saving}>
              {saving ? 'Salvando…' : editing ? 'Salvar alterações' : 'Criar produto'}
            </button>
            {editing && <button type="button" onClick={startNew}>Cancelar</button>}
          </div>
        </form>

        <div className="card">
          <h2 className="section-title" style={{ marginTop: 0 }}>Cadastrados ({products.length})</h2>
          <table>
            <thead>
              <tr><th>Nome</th><th>Time</th><th>Preço</th><th>Vendas</th><th /></tr>
            </thead>
            <tbody>
              {products.map((p) => (
                <tr key={p.id}>
                  <td>{p.name}</td>
                  <td className="muted">{p.team}</td>
                  <td>{brl(p.price)}</td>
                  <td>{p.salesCount ?? 0}</td>
                  <td className="right">
                    <button onClick={() => startEdit(p)}>Editar</button>{' '}
                    <button className="danger" onClick={() => onDelete(p.id)}>Excluir</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
