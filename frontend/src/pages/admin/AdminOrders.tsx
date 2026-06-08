import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { brl, formatDate } from '../../lib/format';
import type { Order, OrderStatus } from '../../types';

const STATUSES: OrderStatus[] = ['pendente', 'pago', 'enviado', 'entregue', 'cancelado'];
const statusClass: Record<string, string> = {
  pendente: 'warn', pago: 'info', enviado: 'info', entregue: 'success', cancelado: 'danger',
};

export default function AdminOrders() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);

  async function refresh() {
    setLoading(true);
    setOrders(await api<Order[]>('/api/orders'));
    setLoading(false);
  }
  useEffect(() => { refresh(); }, []);

  async function update(o: Order, status: OrderStatus) {
    let trackingCode: string | undefined = undefined;

    if (status === 'enviado') {
      // Código de rastreio é obrigatório quando muda pra "enviado". Sem ele
      // o e-mail enviado ao cliente não tem o link dos Correios e a tela de
      // rastreio fica sem informação útil. Cancelar/vazio aborta a operação.
      const raw = prompt(
        'Código de rastreio dos Correios (obrigatório):\nEx.: AA123456789BR',
        o.trackingCode ?? '',
      );
      if (raw == null) {
        alert('Mudança de status cancelada.\nPara marcar como "enviado" é preciso informar o código de rastreio.');
        await refresh(); // re-renderiza o select pra voltar pro status anterior
        return;
      }
      const cleaned = raw.trim();
      if (cleaned.length < 8) {
        alert('Código de rastreio inválido. Use o formato dos Correios (ex.: AA123456789BR).');
        await refresh();
        return;
      }
      trackingCode = cleaned;
    }

    await api(`/api/orders/${o.id}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status, trackingCode }),
    });
    await refresh();
  }

  return (
    <div>
      <h1 className="page-title">Admin — Pedidos</h1>
      {loading ? <p className="muted">Carregando…</p> : (
        <div className="card">
          <table>
            <thead>
              <tr>
                <th>#</th><th>Data</th><th>Cliente</th><th>Itens</th><th>Total</th>
                <th>Status</th><th>Alterar</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((o) => (
                <tr key={o.id}>
                  <td>{o.id.slice(0, 8)}</td>
                  <td>{formatDate(o.createdAt)}</td>
                  <td className="muted">{o.userEmail ?? o.userId.slice(0, 6)}</td>
                  <td>{o.items.reduce((s, i) => s + i.quantity, 0)}</td>
                  <td>{brl(o.total)}</td>
                  <td><span className={`tag ${statusClass[o.status]}`}>{o.status}</span></td>
                  <td>
                    <select value={o.status} onChange={(e) => update(o, e.target.value as OrderStatus)}>
                      {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
                    </select>
                  </td>
                </tr>
              ))}
              {orders.length === 0 && (
                <tr><td colSpan={7} className="muted center">Nenhum pedido ainda.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
