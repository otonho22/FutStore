import { Navigate, Outlet } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export function ProtectedRoute() {
  const { user, loading } = useAuth();
  if (loading) return <div style={{ padding: '2rem' }}>Carregando…</div>;
  if (!user) return <Navigate to="/login" replace />;
  return <Outlet />;
}

export function AdminRoute() {
  const { user, role, loading } = useAuth();
  if (loading) return <div style={{ padding: '2rem' }}>Carregando…</div>;
  if (!user) return <Navigate to="/login" replace />;
  if (role !== 'admin') return <Navigate to="/" replace />;
  return <Outlet />;
}
