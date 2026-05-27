import { useEffect, useState, type FormEvent } from 'react';
import { api } from '../../lib/api';
import { brl, formatDate } from '../../lib/format';
import type { Coupon } from '../../types';

export default function AdminCoupons() {
  const [coupons, setCoupons] = useState<Coupon[]>([]);
  const [draft, setDraft] = useState({
    code: '', type: 'percent' as 'percent' | 'fixed', value: 10, validUntil: '', active: true,
  });
  const [error, setError] = useState<string | null>(null);

  async function refresh() {
    setCoupons(await api<Coupon[]>('/api/coupons'));
  }
  useEffect(() => { refresh(); }, []);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      await api('/api/coupons', {
        method: 'POST',
        body: JSON.stringify({
          ...draft,
          value: Number(draft.value),
          validUntil: new Date(draft.validUntil).toISOString(),
        }),
      });
      setDraft({ code: '', type: 'percent', value: 10, validUntil: '', active: true });
      await refresh();
    } catch (e: any) { setError(e.message); }
  }

  async function toggle(c: Coupon) {
    await api(`/api/coupons/${c.id}`, {
      method: 'PUT', body: JSON.stringify({ active: !c.active }),
    });
    await refresh();
  }

  async function onDelete(id: string) {
    if (!confirm('Excluir cupom?')) return;
    await api(`/api/coupons/${id}`, { method: 'DELETE' });
    await refresh();
  }

  return (
    <div>
      <h1 className="page-title">Admin — Cupons</h1>

      <div className="grid" style={{ gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 2fr)', alignItems: 'start' }}>
        <form className="card col" onSubmit={onSubmit}>
          <h2 className="section-title" style={{ marginTop: 0 }}>Novo cupom</h2>
          {error && <div className="alert error">{error}</div>}
          <div><label>Código</label>
            <input required value={draft.code}
              onChange={(e) => setDraft({ ...draft, code: e.target.value.toUpperCase() })} /></div>
          <div className="row">
            <div style={{ flex: 1 }}><label>Tipo</label>
              <select value={draft.type}
                onChange={(e) => setDraft({ ...draft, type: e.target.value as any })}>
                <option value="percent">Percentual (%)</option>
                <option value="fixed">Valor fixo (R$)</option>
              </select>
            </div>
            <div style={{ flex: 1 }}><label>Valor</label>
              <input type="number" min={0} required value={draft.value}
                onChange={(e) => setDraft({ ...draft, value: Number(e.target.value) })} /></div>
          </div>
          <div><label>Válido até</label>
            <input type="date" required value={draft.validUntil}
              onChange={(e) => setDraft({ ...draft, validUntil: e.target.value })} /></div>
          <button type="submit" className="primary">Criar cupom</button>
        </form>

        <div className="card">
          <h2 className="section-title" style={{ marginTop: 0 }}>Cupons ({coupons.length})</h2>
          <table>
            <thead>
              <tr><th>Código</th><th>Tipo</th><th>Valor</th><th>Validade</th><th>Status</th><th /></tr>
            </thead>
            <tbody>
              {coupons.map((c) => (
                <tr key={c.id}>
                  <td><strong>{c.code}</strong></td>
                  <td>{c.type === 'percent' ? '%' : 'R$'}</td>
                  <td>{c.type === 'percent' ? `${c.value}%` : brl(c.value)}</td>
                  <td>{formatDate(c.validUntil)}</td>
                  <td><span className={`tag ${c.active ? 'success' : 'danger'}`}>{c.active ? 'ativo' : 'inativo'}</span></td>
                  <td className="right">
                    <button onClick={() => toggle(c)}>{c.active ? 'Desativar' : 'Ativar'}</button>{' '}
                    <button className="danger" onClick={() => onDelete(c.id)}>Excluir</button>
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
