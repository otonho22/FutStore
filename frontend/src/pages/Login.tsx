import { useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import GoogleButton from '../components/GoogleButton';

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await login(identifier, password);
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
          <label>Usuário ou e-mail</label>
          <input
            type="text"
            autoComplete="username"
            required
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            placeholder="seu@email.com"
          />
        </div>
        <div>
          <label>Senha</label>
          <input type="password" autoComplete="current-password" required value={password}
            onChange={(e) => setPassword(e.target.value)} />
        </div>
        <button type="submit" className="primary" disabled={loading}>
          {loading ? 'Entrando…' : 'Entrar'}
        </button>
        <div className="auth-divider"><span>ou</span></div>
        <GoogleButton label="Entrar com Google" />
        <p className="muted center" style={{ marginBottom: 0 }}>
          Não tem conta? <Link to="/signup">Cadastre-se</Link>
        </p>
      </form>
    </div>
  );
}
