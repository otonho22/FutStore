import { useEffect, useState, type FormEvent } from 'react';
import { api } from '../../lib/api';
import { brl, formatDate } from '../../lib/format';
import type { Coupon } from '../../types';

type Draft = {
  code: string;
  type: 'percent' | 'fixed';
  value: number;
  validUntil: string;
  active: boolean;
  firstPurchaseOnly: boolean;
  maxUsesPerCustomer: string;
  maxUsesGlobal: string;
};

const EMPTY: Draft = {
  code: '', type: 'percent', value: 10, validUntil: '', active: true,
  firstPurchaseOnly: false, maxUsesPerCustomer: '', maxUsesGlobal: '',
};

export default function AdminCoupons() {
  const [coupons, setCoupons] = useState<Coupon[]>([]);
  const [draft, setDraft] = useState<Draft>(EMPTY);
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
          code: draft.code,
          type: draft.type,
          value: Number(draft.value),
          validUntil: new Date(draft.validUntil).toISOString(),
          active: draft.active,
          firstPurchaseOnly: draft.firstPurchaseOnly,
          maxUsesPerCustomer: draft.maxUsesPerCustomer ? Number(draft.maxUsesPerCustomer) : null,
          maxUsesGlobal: draft.maxUsesGlobal ? Number(draft.maxUsesGlobal) : null,
        }),
      });
      setDraft(EMPTY);
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

          <label style={{ display: 'flex', gap: '0.5rem' }}>
            <input type="checkbox" style={{ width: 'auto' }} checked={draft.firstPurchaseOnly}
              onChange={(e) => setDraft({ ...draft, firstPurchaseOnly: e.target.checked })} />
            <span style={{ color: 'var(--text)' }}>Apenas 1ª compra (RF29)</span>
          </label>

          <div className="row">
            <div style={{ flex: 1 }}><label>Limite por cliente (RF32)</label>
              <input type="number" min={1} placeholder="sem limite" value={draft.maxUsesPerCustomer}
                onChange={(e) => setDraft({ ...draft, maxUsesPerCustomer: e.target.value })} /></div>
            <div style={{ flex: 1 }}><label>Limite global (RF33)</label>
              <input type="number" min={1} placeholder="sem limite" value={draft.maxUsesGlobal}
                onChange={(e) => setDraft({ ...draft, maxUsesGlobal: e.target.value })} /></div>
          </div>

          <button type="submit" className="primary">Criar cupom</button>
        </form>

        <div className="card">
          <h2 className="section-title" style={{ marginTop: 0 }}>Cupons ({coupons.length})</h2>
          <table>
            <thead>
              <tr>
                <th>Código</th><th>Tipo</th><th>Valor</th><th>Validade</th>
                <th>Regras</th><th>Status</th><th />
              </tr>
            </thead>
            <tbody>
              {coupons.map((c) => (
                <tr key={c.id}>
                  <td><strong>{c.code}</strong></td>
                  <td>{c.type === 'percent' ? '%' : 'R$'}</td>
                  <td>{c.type === 'percent' ? `${c.value}%` : brl(c.value)}</td>
                  <td>{formatDate(c.validUntil)}</td>
                  <td className="muted" style={{ fontSize: '0.8rem' }}>
                    {c.firstPurchaseOnly && <div>· 1ª compra</div>}
                    {c.maxUsesPerCustomer != null && <div>· {c.maxUsesPerCustomer}/cliente</div>}
                    {c.maxUsesGlobal != null && <div>· {c.maxUsesGlobal} total</div>}
                    {!c.firstPurchaseOnly && c.maxUsesPerCustomer == null && c.maxUsesGlobal == null && <span>—</span>}
                  </td>
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
