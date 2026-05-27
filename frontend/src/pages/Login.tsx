import { useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await login(email, password);
      navigate('/');
    } catch (e: any) {
      setError(e.message ?? 'Erro ao entrar');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="auth-shell">
      <form className="card auth-card col" onSubmit={onSubmit}>
        <h1 style={{ margin: 0 }}>⚽ Entrar</h1>
        <p className="muted" style={{ marginTop: 0 }}>Bem-vindo de volta.</p>
        {error && <div className="alert error">{error}</div>}
        <div>
          <label>E-mail</label>
          <input type="email" autoComplete="email" required value={email}
            onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div>
          <label>Senha</label>
          <input type="password" autoComplete="current-password" required value={password}
            onChange={(e) => setPassword(e.target.value)} />
        </div>
        <button type="submit" className="primary" disabled={loading}>
          {loading ? 'Entrando…' : 'Entrar'}
        </button>
        <p className="muted center" style={{ marginBottom: 0 }}>
          Não tem conta? <Link to="/signup">Cadastre-se</Link>
        </p>
      </form>
    </div>
  );
}
