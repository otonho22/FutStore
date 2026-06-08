import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { api } from '../lib/api';
import { brl, formatDate } from '../lib/format';
import { downloadNfPdf } from '../lib/nfe';
import type { Order } from '../types';

const statusClass: Record<string, string> = {
  pendente: 'warn', pago: 'info', enviado: 'info', entregue: 'success', cancelado: 'danger',
};

export default function OrderDetail() {
  const { id } = useParams();
  const [order, setOrder] = useState<Order | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    api<Order>(`/api/orders/${id}`).then(setOrder).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <div className="alert error">{error}</div>;
  if (!order) return <p className="muted">Carregando…</p>;

  return (
    <div>
      <h1 className="page-title">Pedido #{order.id.slice(0, 8)}</h1>
      <p className="muted">Criado em {formatDate(order.createdAt)}</p>
      <div className="row" style={{ marginBottom: '1rem' }}>
        <span className={`tag ${statusClass[order.status]}`}>{order.status}</span>
        {order.trackingCode && <span className="tag">Rastreio: {order.trackingCode}</span>}
        <button onClick={() => downloadNfPdf(order)}>📄 Baixar Nota Fiscal (PDF) — simulada</button>
      </div>

      <div className="grid" style={{ gridTemplateColumns: 'minmax(0, 2fr) minmax(0, 1fr)', alignItems: 'start' }}>
        <div className="card">
          <h2 className="section-title" style={{ marginTop: 0 }}>Itens</h2>
          <table>
            <thead>
              <tr><th>Produto</th><th>Tamanho</th><th>Qtd</th><th className="right">Subtotal</th></tr>
            </thead>
            <tbody>
              {order.items.map((i) => (
                <tr key={`${i.productId}-${i.size}`}>
                  <td>{i.name}</td>
                  <td>{i.size}</td>
                  <td>{i.quantity}</td>
                  <td className="right">{brl(i.unitPrice * i.quantity)}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <h2 className="section-title">Histórico</h2>
          <ul style={{ paddingLeft: '1rem' }}>
            {order.statusHistory.map((h, idx) => (
              <li key={idx}>
                <span className={`tag ${statusClass[h.status]}`}>{h.status}</span>
                <span className="muted" style={{ marginLeft: '0.5rem' }}>{formatDate(h.at)}</span>
              </li>
            ))}
          </ul>
        </div>
        <div className="col">
          <div className="card col">
            <h2 className="section-title" style={{ marginTop: 0 }}>Endereço</h2>
            <div>{order.address.fullName}</div>
            <div className="muted">
              {order.address.street}, {order.address.number}{order.address.complement ? ` — ${order.address.complement}` : ''}
              <br />
              {order.address.city} / {order.address.state} — {order.address.zip}
            </div>
          </div>
          {order.payment && (
            <div className="card col">
              <h2 className="section-title" style={{ marginTop: 0 }}>Pagamento</h2>
              {order.payment.method === 'credit_card' && (
                <div className="col">
                  <strong>💳 Cartão de crédito{order.payment.brand ? ` · ${order.payment.brand}` : ''}</strong>
                  <span className="muted">
                    •••• •••• •••• {order.payment.last4 ?? '----'}
                  </span>
                  {order.payment.holderName && (
                    <span className="muted">{order.payment.holderName}</span>
                  )}
                </div>
              )}
              {order.payment.method === 'pix' && <strong>⚡ PIX</strong>}
              {order.payment.method === 'boleto' && <strong>📄 Boleto bancário</strong>}
            </div>
          )}
          <div className="card col">
            <h2 className="section-title" style={{ marginTop: 0 }}>Totais</h2>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <span className="muted">Subtotal</span><span>{brl(order.subtotal)}</span>
            </div>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <span className="muted">Desconto</span><span>-{brl(order.discount)}</span>
            </div>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <span className="muted">Frete</span><span>{brl(order.shipping)}</span>
            </div>
            <div className="row" style={{ justifyContent: 'space-between', fontSize: '1.15rem' }}>
              <strong>Total</strong><strong style={{ color: 'var(--primary)' }}>{brl(order.total)}</strong>
            </div>
          </div>
          <Link to="/orders">← Voltar para meus pedidos</Link>
        </div>
      </div>
    </div>
  );
}
