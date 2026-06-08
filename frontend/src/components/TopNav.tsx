import { useEffect, useState } from 'react';
import { NavLink, useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';

const PROMOS = [
  { icon: '🎟️', text: 'Cupom', strong: 'COPA2026', tail: '— 15% OFF em toda a Copa do Mundo 2026' },
  { icon: '🚚', text: 'Frete grátis', strong: 'em pedidos acima de R$ 399' },
  { icon: '⚡', text: 'Pague em', strong: 'até 10x sem juros', tail: 'no cartão' },
  { icon: '🎁', text: 'Primeira compra?', strong: 'BEMVINDO10', tail: '— 10% no checkout' },
];

const Icon = ({ d, size = 22 }: { d: string; size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <path d={d} />
  </svg>
);

const ICONS = {
  search: 'M11 19a8 8 0 100-16 8 8 0 000 16zM21 21l-4.35-4.35',
  heart: 'M20.84 4.61a5.5 5.5 0 00-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 00-7.78 7.78L12 21l8.84-8.61a5.5 5.5 0 000-7.78z',
  cart: 'M6 6h15l-1.5 9H7.5L6 6zM6 6L5 3H2M9 21a1 1 0 100-2 1 1 0 000 2zM20 21a1 1 0 100-2 1 1 0 000 2z',
  menu: 'M3 6h18M3 12h18M3 18h18',
  close: 'M18 6L6 18M6 6l12 12',
};

export default function TopNav() {
  const { user, role, logout } = useAuth();
  const { items } = useCart();
  const navigate = useNavigate();
  const cartCount = items.reduce((s, i) => s + i.quantity, 0);

  const [promoIdx, setPromoIdx] = useState(0);
  const [menuOpen, setMenuOpen] = useState(false);
  const isAdmin = role === 'admin';

  useEffect(() => {
    const id = setInterval(() => setPromoIdx((i) => (i + 1) % PROMOS.length), 5000);
    return () => clearInterval(id);
  }, []);

  async function handleLogout() {
    await logout();
    setMenuOpen(false);
    navigate('/login');
  }

  const promo = PROMOS[promoIdx];

  return (
    <header className="topnav">
      <div className="topnav-utility">
        <div className="topnav-utility-inner">
          <div className="util-left">
            <Link to="/copa-2026" className="util-link util-brand-link">⚽ Copa 2026</Link>
          </div>
          <div className="util-right">
            <a className="util-link" href="#">Ajuda</a>
            {!user && (
              <Link className="util-cta" to="/login">Entrar</Link>
            )}
            <a className="util-link" href="#">Acompanhar pedido</a>
            {isAdmin && (
              <>
                <NavLink className="util-link" to="/admin/products">Admin · Produtos</NavLink>
                <NavLink className="util-link" to="/admin/coupons">Cupons</NavLink>
                <NavLink className="util-link" to="/admin/orders">Pedidos</NavLink>
              </>
            )}
            {user && (
              <button className="util-link util-btn" onClick={handleLogout}>Sair</button>
            )}
          </div>
        </div>
      </div>

      <div className="topnav-main">
        <div className="topnav-main-inner">
          <Link to="/" className="brand">
            <span className="brand-icon">⚽</span>
            <span className="brand-text">FUTSTORE</span>
          </Link>
          <nav className="primary-nav">
            <NavLink to="/" end>Dashboard</NavLink>
            <NavLink to="/catalog">Catálogo</NavLink>
            <NavLink to="/copa-2026" className="nav-highlight">Copa 2026</NavLink>
            <NavLink to="/orders">Pedidos</NavLink>
          </nav>
          <div className="nav-actions">
            <button className="icon-btn" aria-label="Buscar"><Icon d={ICONS.search} /></button>
            <button className="icon-btn" aria-label="Favoritos"><Icon d={ICONS.heart} /></button>
            <Link to="/cart" className="icon-btn cart-btn" aria-label="Carrinho">
              <Icon d={ICONS.cart} />
              {cartCount > 0 && <span className="cart-badge">{cartCount}</span>}
            </Link>
            <button className="icon-btn mobile-only" aria-label="Menu" onClick={() => setMenuOpen(true)}>
              <Icon d={ICONS.menu} />
            </button>
          </div>
        </div>
      </div>

      <div className="topnav-promo">
        <button className="promo-arrow" aria-label="Anterior"
          onClick={() => setPromoIdx((i) => (i - 1 + PROMOS.length) % PROMOS.length)}>‹</button>
        <div className="promo-text">
          <span className="promo-icon">{promo.icon}</span>
          {promo.text} <strong>{promo.strong}</strong>{promo.tail ? ` ${promo.tail}` : ''}
        </div>
        <button className="promo-arrow" aria-label="Próximo"
          onClick={() => setPromoIdx((i) => (i + 1) % PROMOS.length)}>›</button>
      </div>

      {menuOpen && (
        <>
          <div className="mobile-backdrop" onClick={() => setMenuOpen(false)} />
          <aside className="mobile-drawer">
            <div className="mobile-drawer-head">
              <span className="brand-text">FUTSTORE</span>
              <button className="icon-btn" onClick={() => setMenuOpen(false)} aria-label="Fechar">
                <Icon d={ICONS.close} />
              </button>
            </div>
            <nav className="mobile-nav" onClick={() => setMenuOpen(false)}>
              <NavLink to="/" end>Dashboard</NavLink>
              <NavLink to="/catalog">Catálogo</NavLink>
              <NavLink to="/copa-2026">Copa 2026</NavLink>
              <NavLink to="/orders">Meus Pedidos</NavLink>
              <NavLink to="/cart">Carrinho ({cartCount})</NavLink>
              {isAdmin && (
                <>
                  <div className="mobile-section">Admin</div>
                  <NavLink to="/admin/products">Produtos</NavLink>
                  <NavLink to="/admin/coupons">Cupons</NavLink>
                  <NavLink to="/admin/orders">Pedidos</NavLink>
                </>
              )}
              <div className="mobile-section">{user?.email}</div>
              <button onClick={handleLogout} className="mobile-logout">Sair</button>
            </nav>
          </aside>
        </>
      )}
    </header>
  );
}
