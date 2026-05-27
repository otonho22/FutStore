import { useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { api } from '../lib/api';
import { brl } from '../lib/format';
import type { Coupon, Order, Address } from '../types';

const SHIPPING = 25;

export default function Checkout() {
  const { items, subtotal, clear } = useCart();
  const navigate = useNavigate();
  const [coupon, setCoupon] = useState<Coupon | null>(null);
  const [couponInput, setCouponInput] = useState('');
  const [couponMsg, setCouponMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [address, setAddress] = useState<Address>({
    fullName: '', street: '', number: '', complement: '', city: '', state: '', zip: '',
  });
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const discount = !coupon
    ? 0
    : Math.min(subtotal, coupon.type === 'percent' ? subtotal * (coupon.value / 100) : coupon.value);
  const total = Math.max(0, subtotal - discount + SHIPPING);

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

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const order = await api<Order>('/api/orders', {
        method: 'POST',
        body: JSON.stringify({ items, couponCode: coupon?.code, address }),
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
        </div>
        <div className="card col">
          <h2 className="section-title" style={{ marginTop: 0 }}>Resumo</h2>
          {items.map((i) => (
            <div key={`${i.productId}-${i.size}`} className="row" style={{ justifyContent: 'space-between' }}>
              <span className="muted">{i.name} ({i.size}) ×{i.quantity}</span>
              <span>{brl(i.unitPrice * i.quantity)}</span>
            </div>
          ))}
          <div className="sep" style={{ height: 1, background: 'var(--border)', margin: '0.25rem 0' }} />
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
