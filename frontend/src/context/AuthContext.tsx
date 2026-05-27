import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import {
  onAuthStateChanged,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  signOut,
  type User,
} from 'firebase/auth';
import { auth } from '../lib/firebase';
import { api } from '../lib/api';

interface AuthState {
  user: User | null;
  role: 'admin' | 'customer' | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  signup: (email: string, password: string, displayName: string) => Promise<void>;
  logout: () => Promise<void>;
  refreshRole: () => Promise<void>;
}

const AuthContext = createContext<AuthState | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [role, setRole] = useState<'admin' | 'customer' | null>(null);
  const [loading, setLoading] = useState(true);

  async function readRole(u: User) {
    const token = await u.getIdTokenResult();
    return (token.claims.role as 'admin' | 'customer' | undefined) ?? 'customer';
  }

  useEffect(() => {
    return onAuthStateChanged(auth, async (u) => {
      setUser(u);
      if (u) {
        setRole(await readRole(u));
      } else {
        setRole(null);
      }
      setLoading(false);
    });
  }, []);

  async function login(email: string, password: string) {
    await signInWithEmailAndPassword(auth, email, password);
  }

  async function signup(email: string, password: string, displayName: string) {
    const cred = await createUserWithEmailAndPassword(auth, email, password);
    await cred.user.getIdToken(true);
    await api('/api/users/me', {
      method: 'POST',
      body: JSON.stringify({ displayName, acceptedTerms: true }),
    });
  }

  async function logout() {
    await signOut(auth);
  }

  async function refreshRole() {
    if (auth.currentUser) {
      await auth.currentUser.getIdToken(true);
      setRole(await readRole(auth.currentUser));
    }
  }

  return (
    <AuthContext.Provider value={{ user, role, loading, login, signup, logout, refreshRole }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}
