import { useState } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';

const Icon = ({ d }: { d: string }) => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d={d} />
  </svg>
);

const ICONS = {
  dash: 'M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z',
  cat: 'M3 3h7v7H3zM14 3h7v7h-7zM14 14h7v7h-7zM3 14h7v7H3z',
  cart: 'M6 6h15l-1.5 9H7.5L6 6zM6 6L5 3H2M9 21a1 1 0 100-2 1 1 0 000 2zM20 21a1 1 0 100-2 1 1 0 000 2z',
  orders: 'M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6z M14 2v6h6 M8 13h8 M8 17h5',
  admin: 'M12 2l8 4v6c0 5-3.5 9.5-8 10-4.5-.5-8-5-8-10V6l8-4z',
  logout: 'M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4 M16 17l5-5-5-5 M21 12H9',
};

export default function Sidebar() {
  const { user, role, logout } = useAuth();
  const { items } = useCart();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);

  const close = () => setOpen(false);
  const cartCount = items.reduce((s, i) => s + i.quantity, 0);

  async function handleLogout() {
    await logout();
    navigate('/login');
  }

  return (
    <>
      <button className="menu-btn" onClick={() => setOpen(true)} aria-label="Menu">☰</button>
      <div className={`backdrop ${open ? 'open' : ''}`} onClick={close} />
      <aside className={`sidebar ${open ? 'open' : ''}`}>
        <div className="sidebar-brand">⚽ Projetinho Fellas</div>
        <nav onClick={close}>
          <NavLink to="/" end><Icon d={ICONS.dash} /> Dashboard</NavLink>
          <NavLink to="/catalog"><Icon d={ICONS.cat} /> Catálogo</NavLink>
          <NavLink to="/cart">
            <Icon d={ICONS.cart} /> Carrinho
            {cartCount > 0 && <span className="tag success" style={{ marginLeft: 'auto' }}>{cartCount}</span>}
          </NavLink>
          <NavLink to="/orders"><Icon d={ICONS.orders} /> Meus Pedidos</NavLink>
          {role === 'admin' && (
            <>
              <div className="sep" />
              <NavLink to="/admin/products"><Icon d={ICONS.admin} /> Produtos (admin)</NavLink>
              <NavLink to="/admin/coupons"><Icon d={ICONS.admin} /> Cupons (admin)</NavLink>
              <NavLink to="/admin/orders"><Icon d={ICONS.admin} /> Pedidos (admin)</NavLink>
            </>
          )}
        </nav>
        <div className="sidebar-foot">
          <div className="who">{user?.email}</div>
          <button onClick={handleLogout}>
            <Icon d={ICONS.logout} /> Sair
          </button>
        </div>
      </aside>
    </>
  );
}
