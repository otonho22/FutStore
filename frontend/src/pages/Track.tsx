import { useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { api } from '../lib/api';

type PublicOrderStatus = 'pendente' | 'pago' | 'enviado' | 'entregue' | 'cancelado';

interface PublicOrder {
  id: string;
  status: PublicOrderStatus;
  trackingCode: string | null;
  createdAt: string;
  statusHistory: { status: PublicOrderStatus; at: string }[];
  delivery: { city: string; state: string };
  items: { name: string; size: string; quantity: number }[];
}

const STEPS: { key: PublicOrderStatus; label: string; icon: string }[] = [
  { key: 'pendente', label: 'Pedido recebido',       icon: '🧾' },
  { key: 'pago',     label: 'Pagamento confirmado',  icon: '💳' },
  { key: 'enviado',  label: 'A caminho',             icon: '🚚' },
  { key: 'entregue', label: 'Entregue',              icon: '📦' },
];

const STATUS_TAG: Record<PublicOrderStatus, string> = {
  pendente: 'warn', pago: 'info', enviado: 'info', entregue: 'success', cancelado: 'danger',
};

function formatDateTime(input: any): string {
  if (!input) return '';
  const d = new Date(input);
  if (isNaN(d.getTime())) return '';
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

function correiosUrl(code: string): string {
  return `https://rastreamento.correios.com.br/app/index.php?objetos=${encodeURIComponent(code)}`;
}

export default function Track() {
  const { code: codeParam } = useParams();
  const navigate = useNavigate();
  const [input, setInput] = useState(codeParam ?? '');
  const [order, setOrder] = useState<PublicOrder | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!codeParam) {
      setOrder(null);
      setError(null);
      return;
    }
    setInput(codeParam);
    setLoading(true);
    setError(null);
    setOrder(null);
    api<PublicOrder>(`/api/orders/track/${encodeURIComponent(codeParam)}`)
      .then(setOrder)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, [codeParam]);

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    const v = input.trim();
    if (!v) return;
    navigate(`/track/${encodeURIComponent(v)}`);
  }

  return (
    <div>
      <h1 className="page-title">Acompanhar pedido</h1>
      <p className="muted">
        Digite o número do pedido ou o código de rastreio dos Correios para ver o status atual.
      </p>

      <form className="card col" onSubmit={onSubmit} style={{ marginBottom: '1.25rem' }}>
        <label htmlFor="track-input">Número do pedido ou código de rastreio</label>
        <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
          <input
            id="track-input"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="ex.: AA123456789BR ou clm9xz..."
            style={{ flex: '1 1 280px', minWidth: 240 }}
            autoComplete="off"
          />
          <button type="submit" className="primary" disabled={loading || !input.trim()}>
            {loading ? 'Buscando…' : 'Rastrear'}
          </button>
        </div>
      </form>

      {loading && <p className="muted">Buscando seu pedido…</p>}

      {error && (
        <div className="alert error">
          {error}
          <div className="muted" style={{ marginTop: 4, fontSize: '0.85rem' }}>
            Confira o código digitado. O número do pedido aparece logo após a finalização da
            compra e o código de rastreio é enviado quando o pedido é despachado.
          </div>
        </div>
      )}

      {order && <TrackResult order={order} />}
    </div>
  );
}

function TrackResult({ order }: { order: PublicOrder }) {
  // Última entrada do histórico em cada etapa — a tela ignora repetições.
  const lastByStatus = new Map<PublicOrderStatus, string>();
  for (const h of order.statusHistory) lastByStatus.set(h.status, h.at);

  const isCancelled = order.status === 'cancelado';
  const currentIdx = STEPS.findIndex((s) => s.key === order.status);

  return (
    <div className="grid" style={{ gridTemplateColumns: 'minmax(0, 2fr) minmax(0, 1fr)', alignItems: 'start', gap: '1rem' }}>
      <div className="card col">
        <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
          <div>
            <div className="muted" style={{ fontSize: '0.85rem' }}>Pedido</div>
            <strong>#{order.id.slice(0, 8).toUpperCase()}</strong>
          </div>
          <span className={`tag ${STATUS_TAG[order.status]}`} style={{ fontSize: '0.9rem' }}>
            {order.status.toUpperCase()}
          </span>
        </div>

        {order.trackingCode && (
          <div className="row" style={{ alignItems: 'center', gap: 8, flexWrap: 'wrap', marginTop: 4 }}>
            <span className="muted" style={{ fontSize: '0.85rem' }}>Código de rastreio:</span>
            <code style={{ background: 'var(--bg)', padding: '0.2rem 0.5rem', borderRadius: 6 }}>
              {order.trackingCode}
            </code>
            <a
              href={correiosUrl(order.trackingCode)}
              target="_blank"
              rel="noopener noreferrer"
              className="util-link"
              style={{ fontSize: '0.85rem' }}
            >
              Ver detalhes nos Correios ↗
            </a>
          </div>
        )}

        <h2 className="section-title" style={{ marginTop: '1rem' }}>Status do envio</h2>

        {isCancelled ? (
          <div className="alert error" style={{ margin: 0 }}>
            ❌ Pedido cancelado em {formatDateTime(lastByStatus.get('cancelado') ?? order.createdAt)}.
          </div>
        ) : (
          <ol className="track-timeline">
            {STEPS.map((step, idx) => {
              const reached = idx <= currentIdx;
              const isCurrent = idx === currentIdx;
              const at = lastByStatus.get(step.key);
              return (
                <li key={step.key} className={`track-step ${reached ? 'reached' : ''} ${isCurrent ? 'current' : ''}`}>
                  <div className="track-dot" aria-hidden>{reached ? '●' : '○'}</div>
                  <div className="track-body">
                    <div className="track-row">
                      <span className="track-icon" aria-hidden>{step.icon}</span>
                      <strong>{step.label}</strong>
                    </div>
                    <div className="muted" style={{ fontSize: '0.85rem' }}>
                      {reached
                        ? at ? formatDateTime(at) : '—'
                        : isCurrent ? 'em andamento…' : 'aguardando'}
                    </div>
                  </div>
                </li>
              );
            })}
          </ol>
        )}
      </div>

      <div className="col">
        <div className="card col">
          <h2 className="section-title" style={{ marginTop: 0 }}>Entrega</h2>
          <div>
            <div className="muted" style={{ fontSize: '0.85rem' }}>Destino</div>
            <strong>{order.delivery.city} / {order.delivery.state}</strong>
          </div>
          <div>
            <div className="muted" style={{ fontSize: '0.85rem' }}>Pedido feito em</div>
            <strong>{formatDateTime(order.createdAt)}</strong>
          </div>
        </div>

        <div className="card col">
          <h2 className="section-title" style={{ marginTop: 0 }}>Itens ({order.items.length})</h2>
          {order.items.map((i, idx) => (
            <div key={idx} className="row" style={{ justifyContent: 'space-between' }}>
              <span>{i.name}</span>
              <span className="muted">{i.size} · ×{i.quantity}</span>
            </div>
          ))}
        </div>

        <Link to="/track" className="util-link">← Buscar outro pedido</Link>
      </div>
    </div>
  );
}
