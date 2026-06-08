import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export function ProtectedRoute() {
  const { user, loading } = useAuth();
  const location = useLocation();
  if (loading) return <div style={{ padding: '2rem' }}>Carregando…</div>;
  if (!user) {
    // Preserva o destino original (ex.: /checkout) pra Login redirecionar
    // de volta depois que o cliente autenticar.
    const from = location.pathname + location.search;
    return <Navigate to="/login" replace state={{ from }} />;
  }
  return <Outlet />;
}

export function AdminRoute() {
  const { user, role, loading } = useAuth();
  const location = useLocation();
  if (loading) return <div style={{ padding: '2rem' }}>Carregando…</div>;
  if (!user) {
    const from = location.pathname + location.search;
    return <Navigate to="/login" replace state={{ from }} />;
  }
  if (role !== 'admin') return <Navigate to="/" replace />;
  return <Outlet />;
}
