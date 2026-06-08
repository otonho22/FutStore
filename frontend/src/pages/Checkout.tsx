import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import QRCode from 'qrcode';
import { useCart } from '../context/CartContext';
import { api } from '../lib/api';
import { brl } from '../lib/format';
import { buildPixPayload } from '../lib/pix';
import type { Coupon, Order, Address, PaymentMethod } from '../types';

const PIX_KEY = import.meta.env.VITE_PIX_KEY as string | undefined;
const PIX_NAME = import.meta.env.VITE_PIX_NAME as string | undefined;
const PIX_CITY = import.meta.env.VITE_PIX_CITY as string | undefined;

const SHIPPING = 25;

// Detecta bandeira pelos primeiros dígitos do cartão
function detectBrand(num: string): string | undefined {
  const n = num.replace(/\D/g, '');
  if (/^4/.test(n)) return 'Visa';
  if (/^(5[1-5]|2[2-7])/.test(n)) return 'Mastercard';
  if (/^3[47]/.test(n)) return 'Amex';
  if (/^(6011|65|64[4-9])/.test(n)) return 'Discover';
  if (/^(606282|3841)/.test(n)) return 'Hipercard';
  if (/^(4011|4312|4389|4514|4576|5041|5066|5067|509|6277|6362|6363|6504|6505|6507|6509|6516|6550)/.test(n))
    return 'Elo';
  return undefined;
}

function formatCardNumber(v: string) {
  return v.replace(/\D/g, '').slice(0, 19).replace(/(\d{4})(?=\d)/g, '$1 ');
}

function formatExpiry(v: string) {
  const n = v.replace(/\D/g, '').slice(0, 4);
  return n.length > 2 ? `${n.slice(0, 2)}/${n.slice(2)}` : n;
}

export default function Checkout() {
  const { items, subtotal, clear } = useCart();
  const navigate = useNavigate();
  const [coupon, setCoupon] = useState<Coupon | null>(null);
  const [couponInput, setCouponInput] = useState('');
  const [couponMsg, setCouponMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [address, setAddress] = useState<Address>({
    fullName: '', street: '', number: '', complement: '', city: '', state: '', zip: '',
  });

  // Pagamento
  const [payMethod, setPayMethod] = useState<PaymentMethod>('credit_card');
  const [cardNumber, setCardNumber] = useState('');
  const [cardName, setCardName] = useState('');
  const [cardExpiry, setCardExpiry] = useState('');
  const [cardCvv, setCardCvv] = useState('');

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pixCopied, setPixCopied] = useState(false);
  const pixCanvasRef = useRef<HTMLCanvasElement | null>(null);

  const discount = !coupon
    ? 0
    : Math.min(subtotal, coupon.type === 'percent' ? subtotal * (coupon.value / 100) : coupon.value);
  const total = Math.max(0, subtotal - discount + SHIPPING);
  const brand = detectBrand(cardNumber);

  // Payload do BR Code Pix — recalculado quando muda o total.
  const pixPayload = useMemo(() => {
    if (!PIX_KEY || !PIX_NAME || !PIX_CITY || total <= 0) return null;
    return buildPixPayload({
      key: PIX_KEY,
      name: PIX_NAME,
      city: PIX_CITY,
      amount: Number(total.toFixed(2)),
      txid: `FUTSTORE${Date.now().toString().slice(-10)}`,
    });
  }, [total]);

  // Renderiza QR no canvas quando o PIX está selecionado e o payload existe.
  useEffect(() => {
    if (payMethod !== 'pix' || !pixPayload || !pixCanvasRef.current) return;
    QRCode.toCanvas(pixCanvasRef.current, pixPayload, {
      width: 200,
      margin: 1,
      color: { dark: '#000000', light: '#ffffff' },
    }).catch(() => {});
  }, [payMethod, pixPayload]);

  async function copyPix() {
    if (!pixPayload) return;
    try {
      await navigator.clipboard.writeText(pixPayload);
      setPixCopied(true);
      setTimeout(() => setPixCopied(false), 2000);
    } catch {
      // clipboard pode falhar em http (não-localhost) — silencioso
    }
  }

  async function validateCoupon() {
    if (!couponInput.trim()) return;
    setCouponMsg(null);
    try {
      const c = await api<Coupon>(`/api/coupons/validate/${encodeURIComponent(couponInput.trim())}`);
      setCoupon(c);
      setCouponMsg({ ok: true, text: `Cupom aplicado: ${c.type === 'percent' ? `${c.value}%` : brl(c.value)}` });
    } catch (e: any) {
      setCoupon(null);
      setCouponMsg({ ok: false, text: e.message });
    }
  }

  function buildPaymentPayload() {
    if (payMethod === 'credit_card') {
      const digits = cardNumber.replace(/\D/g, '');
      if (digits.length < 13) throw new Error('Número do cartão inválido.');
      if (!cardName.trim()) throw new Error('Informe o nome impresso no cartão.');
      if (!/^\d{2}\/\d{2}$/.test(cardExpiry)) throw new Error('Validade no formato MM/AA.');
      if (!/^\d{3,4}$/.test(cardCvv)) throw new Error('CVV inválido.');
      return {
        method: 'credit_card' as const,
        brand,
        last4: digits.slice(-4),
        holderName: cardName.trim(),
      };
    }
    return { method: payMethod };
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const payment = buildPaymentPayload();
      const order = await api<Order>('/api/orders', {
        method: 'POST',
        body: JSON.stringify({ items, couponCode: coupon?.code, address, payment }),
      });
      clear();
      navigate(`/orders/${order.id}`);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  }

  if (items.length === 0) {
    return (
      <div>
        <h1 className="page-title">Checkout</h1>
        <div className="card"><p>Adicione itens ao carrinho primeiro.</p></div>
      </div>
    );
  }

  function set<K extends keyof Address>(key: K, value: Address[K]) {
    setAddress((a) => ({ ...a, [key]: value }));
  }

  return (
    <div>
      <h1 className="page-title">Checkout</h1>
      {error && <div className="alert error">{error}</div>}
      <form onSubmit={onSubmit} className="grid"
        style={{ gridTemplateColumns: 'minmax(0, 2fr) minmax(0, 1fr)', alignItems: 'start' }}>
        <div className="col">
          {/* Endereço */}
          <div className="card col">
            <h2 className="section-title" style={{ marginTop: 0 }}>Endereço de entrega</h2>
            <div><label>Nome completo</label>
              <input required value={address.fullName} onChange={(e) => set('fullName', e.target.value)} /></div>
            <div className="row">
              <div style={{ flex: 2 }}><label>Rua</label>
                <input required value={address.street} onChange={(e) => set('street', e.target.value)} /></div>
              <div style={{ flex: 1 }}><label>Número</label>
                <input required value={address.number} onChange={(e) => set('number', e.target.value)} /></div>
            </div>
            <div><label>Complemento</label>
              <input value={address.complement ?? ''} onChange={(e) => set('complement', e.target.value)} /></div>
            <div className="row">
              <div style={{ flex: 2 }}><label>Cidade</label>
                <input required value={address.city} onChange={(e) => set('city', e.target.value)} /></div>
              <div style={{ flex: 1 }}><label>UF</label>
                <input required maxLength={2} value={address.state}
                  onChange={(e) => set('state', e.target.value.toUpperCase())} /></div>
              <div style={{ flex: 1 }}><label>CEP</label>
                <input required value={address.zip} onChange={(e) => set('zip', e.target.value)} /></div>
            </div>
          </div>

          {/* Cupom */}
          <div className="card col">
            <h2 className="section-title" style={{ marginTop: 0 }}>Cupom</h2>
            <div className="row">
              <input placeholder="Digite o código" value={couponInput}
                onChange={(e) => setCouponInput(e.target.value)} style={{ flex: 1 }} />
              <button type="button" onClick={validateCoupon}>Aplicar</button>
            </div>
            {couponMsg && (
              <div className={`alert ${couponMsg.ok ? 'success' : 'error'}`} style={{ marginBottom: 0 }}>
                {couponMsg.text}
              </div>
            )}
          </div>

          {/* Pagamento */}
          <div className="card col">
            <h2 className="section-title" style={{ marginTop: 0 }}>Forma de pagamento</h2>
            <div className="pay-methods">
              <PayOption value="credit_card" current={payMethod} onChange={setPayMethod}
                icon="💳" title="Cartão de crédito" desc="Em até 12x" />
              <PayOption value="pix" current={payMethod} onChange={setPayMethod}
                icon="⚡" title="PIX" desc="5% de desconto, aprovação imediata" />
              <PayOption value="boleto" current={payMethod} onChange={setPayMethod}
                icon="📄" title="Boleto" desc="Aprovação em até 2 dias úteis" />
            </div>

            {payMethod === 'credit_card' && (
              <div className="col" style={{ marginTop: '0.75rem' }}>
                <div>
                  <label>Número do cartão {brand && <span className="tag success">{brand}</span>}</label>
                  <input value={cardNumber} placeholder="0000 0000 0000 0000"
                    onChange={(e) => setCardNumber(formatCardNumber(e.target.value))}
                    inputMode="numeric" autoComplete="cc-number" />
                </div>
                <div>
                  <label>Nome impresso no cartão</label>
                  <input value={cardName} placeholder="COMO ESTÁ NO CARTÃO"
                    onChange={(e) => setCardName(e.target.value.toUpperCase())}
                    autoComplete="cc-name" />
                </div>
                <div className="row">
                  <div style={{ flex: 1 }}>
                    <label>Validade (MM/AA)</label>
                    <input value={cardExpiry} placeholder="MM/AA"
                      onChange={(e) => setCardExpiry(formatExpiry(e.target.value))}
                      inputMode="numeric" autoComplete="cc-exp" />
                  </div>
                  <div style={{ flex: 1 }}>
                    <label>CVV</label>
                    <input value={cardCvv} placeholder="123" maxLength={4}
                      onChange={(e) => setCardCvv(e.target.value.replace(/\D/g, ''))}
                      inputMode="numeric" autoComplete="cc-csc" />
                  </div>
                </div>
                <p className="muted" style={{ fontSize: '0.8rem', margin: 0 }}>
                  🔒 Dados simulados — apenas os últimos 4 dígitos são registrados no pedido.
                </p>
              </div>
            )}

            {payMethod === 'pix' && (
              <div className="card" style={{ background: 'var(--bg-elev-2)', marginTop: '0.75rem' }}>
                {!pixPayload ? (
                  <div className="alert error" style={{ margin: 0 }}>
                    Pix indisponível — defina <code>VITE_PIX_KEY</code>, <code>VITE_PIX_NAME</code> e
                    <code> VITE_PIX_CITY</code> no <code>.env</code> do frontend.
                  </div>
                ) : (
                  <div className="row" style={{ alignItems: 'flex-start', gap: 16, flexWrap: 'wrap' }}>
                    <div style={{ background: '#fff', padding: 10, borderRadius: 8, display: 'grid',
                      placeItems: 'center' }}>
                      <canvas ref={pixCanvasRef} />
                    </div>
                    <div className="col" style={{ flex: 1, minWidth: 220 }}>
                      <div>
                        <strong>Recebedor</strong>
                        <div className="muted" style={{ fontSize: '0.85rem' }}>
                          {PIX_NAME} · {PIX_CITY}
                        </div>
                      </div>
                      <div>
                        <strong>Valor</strong>
                        <div style={{ fontSize: '1.1rem', color: 'var(--primary)' }}>{brl(total)}</div>
                      </div>
                      <div>
                        <strong>Pix Copia e Cola</strong>
                        <code style={{ fontSize: '0.72rem', background: 'var(--bg)', padding: '0.5rem',
                          borderRadius: 6, wordBreak: 'break-all', display: 'block', marginTop: 4 }}>
                          {pixPayload}
                        </code>
                      </div>
                      <button type="button" onClick={copyPix}>
                        {pixCopied ? '✓ Copiado!' : '📋 Copiar código Pix'}
                      </button>
                      <p className="muted" style={{ margin: 0, fontSize: '0.8rem' }}>
                        Escaneie o QR no app do banco ou cole o código acima. Após pagar,
                        clique em <strong>Finalizar pedido</strong> — a confirmação é manual.
                      </p>
                    </div>
                  </div>
                )}
              </div>
            )}

            {payMethod === 'boleto' && (
              <div className="alert" style={{ marginTop: '0.75rem', marginBottom: 0 }}>
                Ao finalizar, o boleto será gerado e enviado para seu e-mail. O pedido fica
                como <strong>pendente</strong> até a compensação (1-2 dias úteis).
              </div>
            )}
          </div>
        </div>

        {/* Resumo */}
        <div className="card col">
          <h2 className="section-title" style={{ marginTop: 0 }}>Resumo</h2>
          {items.map((i) => (
            <div key={`${i.productId}-${i.size}`} className="row" style={{ justifyContent: 'space-between' }}>
              <span className="muted">{i.name} ({i.size}) ×{i.quantity}</span>
              <span>{brl(i.unitPrice * i.quantity)}</span>
            </div>
          ))}
          <div style={{ height: 1, background: 'var(--border)', margin: '0.25rem 0' }} />
          <div className="row" style={{ justifyContent: 'space-between' }}>
            <span className="muted">Subtotal</span><span>{brl(subtotal)}</span>
          </div>
          <div className="row" style={{ justifyContent: 'space-between' }}>
            <span className="muted">Desconto</span><span>-{brl(discount)}</span>
          </div>
          <div className="row" style={{ justifyContent: 'space-between' }}>
            <span className="muted">Frete</span><span>{brl(SHIPPING)}</span>
          </div>
          <div className="row" style={{ justifyContent: 'space-between', fontSize: '1.15rem' }}>
            <strong>Total</strong><strong style={{ color: 'var(--primary)' }}>{brl(total)}</strong>
          </div>
          <button type="submit" className="primary" disabled={submitting}>
            {submitting ? 'Finalizando…' : 'Finalizar pedido'}
          </button>
        </div>
      </form>
    </div>
  );
}

function PayOption({
  value, current, onChange, icon, title, desc,
}: {
  value: PaymentMethod;
  current: PaymentMethod;
  onChange: (m: PaymentMethod) => void;
  icon: string;
  title: string;
  desc: string;
}) {
  const selected = current === value;
  return (
    <label className={`pay-opt ${selected ? 'selected' : ''}`}>
      <input type="radio" name="paymethod" value={value}
        checked={selected} onChange={() => onChange(value)} style={{ display: 'none' }} />
      <span style={{ fontSize: '1.4rem' }}>{icon}</span>
      <div className="col" style={{ gap: 2 }}>
        <strong>{title}</strong>
        <span className="muted" style={{ fontSize: '0.78rem' }}>{desc}</span>
      </div>
    </label>
  );
}
