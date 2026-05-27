import { useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function Signup() {
  const { signup } = useAuth();
  const navigate = useNavigate();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [terms, setTerms] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (!terms) {
      setError('Você precisa aceitar os termos.');
      return;
    }
    setError(null);
    setLoading(true);
    try {
      await signup(email, password, name);
      navigate('/');
    } catch (e: any) {
      setError(e.message ?? 'Erro ao cadastrar');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="auth-shell">
      <form className="card auth-card col" onSubmit={onSubmit}>
        <h1 style={{ margin: 0 }}>⚽ Criar conta</h1>
        {error && <div className="alert error">{error}</div>}
        <div>
          <label>Nome</label>
          <input required value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div>
          <label>E-mail</label>
          <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div>
          <label>Senha (mín. 6 caracteres)</label>
          <input type="password" minLength={6} required value={password}
            onChange={(e) => setPassword(e.target.value)} />
        </div>
        <label style={{ display: 'flex', gap: '0.5rem', alignItems: 'flex-start' }}>
          <input type="checkbox" style={{ width: 'auto' }}
            checked={terms} onChange={(e) => setTerms(e.target.checked)} />
          <span style={{ color: 'var(--text)' }}>
            Aceito os termos e a política de privacidade (LGPD).
          </span>
        </label>
        <button type="submit" className="primary" disabled={loading}>
          {loading ? 'Criando…' : 'Cadastrar'}
        </button>
        <p className="muted center" style={{ marginBottom: 0 }}>
          Já tem conta? <Link to="/login">Entrar</Link>
        </p>
      </form>
    </div>
  );
}
