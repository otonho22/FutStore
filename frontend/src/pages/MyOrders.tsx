import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../lib/api';
import { brl, formatDate } from '../lib/format';
import { downloadNfPdf } from '../lib/nfe';
import type { Order } from '../types';

const statusClass: Record<string, string> = {
  pendente: 'warn', pago: 'info', enviado: 'info', entregue: 'success', cancelado: 'danger',
};

export default function MyOrders() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api<Order[]>('/api/orders/mine').then(setOrders).finally(() => setLoading(false));
  }, []);

  return (
    <div>
      <h1 className="page-title">Meus Pedidos</h1>
      {loading ? <p className="muted">Carregando…</p> :
        orders.length === 0 ? (
          <div className="card"><p className="muted">Você ainda não tem pedidos.</p></div>
        ) : (
          <div className="card">
            <table>
              <thead>
                <tr>
                  <th>Pedido</th><th>Data</th><th>Itens</th><th>Total</th><th>Status</th><th />
                </tr>
              </thead>
              <tbody>
                {orders.map((o) => (
                  <tr key={o.id}>
                    <td>#{o.id.slice(0, 8)}</td>
                    <td>{formatDate(o.createdAt)}</td>
                    <td>{o.items.reduce((s, i) => s + i.quantity, 0)}</td>
                    <td>{brl(o.total)}</td>
                    <td><span className={`tag ${statusClass[o.status]}`}>{o.status}</span></td>
                    <td>
                      <div className="row" style={{ gap: 6 }}>
                        <Link to={`/orders/${o.id}`}>Detalhes</Link>
                        <button onClick={() => downloadNfPdf(o)} title="Baixar Nota Fiscal (simulada)">📄 NF</button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
    </div>
  );
}
